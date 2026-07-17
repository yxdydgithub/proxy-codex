[CmdletBinding()]
param(
    [string]$HostName = "127.0.0.1",
    [int]$Port = 7890,
    [string]$CodexPath,
    [ValidateSet("Desktop", "CLI", "Auto")]
    [string]$LaunchMode = "Desktop",
    [string[]]$CodexArguments = @(),
    [switch]$VerifyOnly,
    [switch]$RestartCodex
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "OK   $Message" -ForegroundColor Green
}

function Write-WarnLine {
    param([string]$Message)
    Write-Host "WARN $Message" -ForegroundColor Yellow
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PortListening {
    param([string]$Address, [int]$ListenPort)

    try {
        $connections = Get-NetTCPConnection -LocalPort $ListenPort -State Listen -ErrorAction Stop
        return @($connections | Where-Object { $_.LocalAddress -in @($Address, "0.0.0.0", "::", "::1") }).Count -gt 0
    }
    catch {
        $netstat = netstat -ano | Select-String ":$ListenPort\s+.*LISTENING"
        return $null -ne $netstat
    }
}

function Get-UserEnvValue {
    param([string]$Name)

    try {
        $value = [Environment]::GetEnvironmentVariable($Name, "User")
    }
    catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value
}

function ConvertTo-WinInetProxyState {
    param(
        [string]$Source,
        [object]$Settings
    )

    $proxyEnable = 0
    if ($null -ne $Settings.ProxyEnable) {
        $proxyEnable = [int]$Settings.ProxyEnable
    }

    $proxyServer = [string]$Settings.ProxyServer
    $autoConfigUrl = [string]$Settings.AutoConfigURL
    $autoDetect = 0
    if ($null -ne $Settings.AutoDetect) {
        $autoDetect = [int]$Settings.AutoDetect
    }

    [PSCustomObject]@{
        Source = $Source
        ProxyEnable = $proxyEnable
        ProxyServer = $proxyServer
        AutoConfigURL = $autoConfigUrl
        AutoDetect = $autoDetect
        ManualProxyEnabled = ($proxyEnable -eq 1 -and -not [string]::IsNullOrWhiteSpace($proxyServer))
        PacProxyEnabled = -not [string]::IsNullOrWhiteSpace($autoConfigUrl)
        SystemProxyEnabled = (($proxyEnable -eq 1 -and -not [string]::IsNullOrWhiteSpace($proxyServer)) -or -not [string]::IsNullOrWhiteSpace($autoConfigUrl))
    }
}

function Get-WinInetProxyStates {
    $states = @()
    $paths = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings")

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($currentSid) {
        $paths += "Registry::HKEY_USERS\$currentSid\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    }

    if ($PSScriptRoot -match "^[A-Za-z]:\\Users\\([^\\]+)\\") {
        $profileUser = $matches[1]
        try {
            $localUser = Get-LocalUser -Name $profileUser -ErrorAction Stop
            if ($localUser.SID) {
                $paths += "Registry::HKEY_USERS\$($localUser.SID.Value)\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
            }
        }
        catch {
            # Local user lookup can be unavailable on some managed machines.
        }
    }

    foreach ($path in ($paths | Select-Object -Unique)) {
        try {
            $settings = Get-ItemProperty $path -ErrorAction Stop
            $states += ConvertTo-WinInetProxyState -Source $path -Settings $settings
        }
        catch {
            $states += [PSCustomObject]@{
                Source = $path
                Error = $_.Exception.Message
                ProxyEnable = $null
                ProxyServer = $null
                AutoConfigURL = $null
                AutoDetect = $null
                ManualProxyEnabled = $false
                PacProxyEnabled = $false
                SystemProxyEnabled = $false
            }
        }
    }

    return $states
}

function Get-ClashConfigCandidates {
    $paths = @()
    $knownDirs = @()

    if ($env:APPDATA) {
        $knownDirs += Join-Path $env:APPDATA "io.github.clash-verge-rev.clash-verge-rev"
    }
    if ($env:LOCALAPPDATA) {
        $knownDirs += Join-Path $env:LOCALAPPDATA "io.github.clash-verge-rev.clash-verge-rev"
    }
    if ($PSScriptRoot -match "^([A-Za-z]:\\Users\\[^\\]+)\\") {
        $profileRoot = $matches[1]
        $knownDirs += Join-Path $profileRoot "AppData\Roaming\io.github.clash-verge-rev.clash-verge-rev"
        $knownDirs += Join-Path $profileRoot "AppData\Local\io.github.clash-verge-rev.clash-verge-rev"
    }

    foreach ($dir in ($knownDirs | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $dir -ErrorAction SilentlyContinue) {
            foreach ($name in @("verge.yaml", "clash-verge.yaml", "config.yaml")) {
                $file = Join-Path $dir $name
                if (Test-Path -LiteralPath $file -ErrorAction SilentlyContinue) {
                    $paths += $file
                }
            }
        }
    }

    return $paths | Select-Object -Unique
}

function Get-YamlScalar {
    param([string]$Text, [string]$Name)

    $escaped = [Regex]::Escape($Name)
    if ($Text -match "(?m)^\s*$escaped\s*:\s*(.*?)\s*$") {
        return $matches[1].Trim(" `"'")
    }

    return $null
}

function Test-TunEnabledInYaml {
    param([string]$Path)

    try {
        $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        Write-WarnLine "无法读取 TUN 配置：$Path；$($_.Exception.Message)"
        return $false
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*tun\s*:") {
            for ($j = $i + 1; $j -lt [Math]::Min($i + 12, $lines.Count); $j++) {
                if ($lines[$j] -match "^\S" -and $lines[$j] -notmatch "^\s*#") {
                    break
                }
                if ($lines[$j] -match "^\s+enable\s*:\s*true\s*$") {
                    return $true
                }
            }
        }
    }

    return $false
}

function Resolve-ExistingFile {
    param([string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return $null
}

function New-CodexTarget {
    param(
        [string]$Path,
        [string]$Kind,
        [string]$DisplayName
    )

    $resolved = Resolve-ExistingFile -Path $Path
    if (-not $resolved) {
        throw "可执行文件不存在：$Path"
    }

    [PSCustomObject]@{
        Path = $resolved
        Kind = $Kind
        DisplayName = $DisplayName
    }
}

function Get-OpenAIAppPackageDirs {
    $dirs = @()

    try {
        $packages = Get-AppxPackage -ErrorAction Stop |
            Where-Object {
                $_.Name -like "OpenAI.ChatGPT*" -or
                $_.Name -like "OpenAI.Codex*" -or
                $_.PackageFullName -like "OpenAI.ChatGPT*" -or
                $_.PackageFullName -like "OpenAI.Codex*"
            } |
            Sort-Object Version -Descending

        foreach ($pkg in $packages) {
            if ($pkg.InstallLocation) {
                $dirs += $pkg.InstallLocation
            }
        }
    }
    catch {
        Write-WarnLine "无法通过 Get-AppxPackage 检查 ChatGPT/Codex 安装包：$($_.Exception.Message)"
    }

    $windowsApps = "C:\Program Files\WindowsApps"
    if (Test-Path -LiteralPath $windowsApps -PathType Container -ErrorAction SilentlyContinue) {
        foreach ($pattern in @("OpenAI.ChatGPT_*", "OpenAI.Codex_*")) {
            $dirs += Get-ChildItem -LiteralPath $windowsApps -Directory -Filter $pattern -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                ForEach-Object { $_.FullName }
        }
    }

    return $dirs | Where-Object { $_ } | Select-Object -Unique
}

function Get-CodexDesktopCandidates {
    $candidates = @()

    foreach ($dir in Get-OpenAIAppPackageDirs) {
        foreach ($relative in @("app\ChatGPT.exe", "app\Codex.exe")) {
            $candidates += Join-Path $dir $relative
        }
    }

    if ($env:LOCALAPPDATA) {
        foreach ($root in @(
                (Join-Path $env:LOCALAPPDATA "Programs\OpenAI\ChatGPT"),
                (Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex"),
                (Join-Path $env:LOCALAPPDATA "Programs\ChatGPT"),
                (Join-Path $env:LOCALAPPDATA "Programs\Codex")
            )) {
            foreach ($name in @("ChatGPT.exe", "Codex.exe")) {
                $candidates += Join-Path $root $name
                $candidates += Join-Path (Join-Path $root "app") $name
            }
        }
    }

    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $binDir = Split-Path -Parent $cmd.Source
        $appDir = Split-Path -Parent $binDir
        foreach ($name in @("ChatGPT.exe", "Codex.exe")) {
            $candidates += Join-Path $appDir $name
            $candidates += Join-Path (Join-Path $appDir "app") $name
        }
    }

    return $candidates | Where-Object { Resolve-ExistingFile -Path $_ } | Select-Object -Unique
}

function Get-CodexCliCandidates {
    $candidates = @()

    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $candidates += $cmd.Source
    }

    foreach ($dir in Get-OpenAIAppPackageDirs) {
        foreach ($relative in @("app\resources\codex.exe", "app\bin\codex.exe")) {
            $candidates += Join-Path $dir $relative
        }
    }

    if ($env:LOCALAPPDATA) {
        foreach ($root in @(
                (Join-Path $env:LOCALAPPDATA "Programs\OpenAI\ChatGPT"),
                (Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex"),
                (Join-Path $env:LOCALAPPDATA "Programs\Codex")
            )) {
            foreach ($relative in @("bin\codex.exe", "resources\codex.exe", "app\resources\codex.exe", "codex.exe")) {
                $candidates += Join-Path $root $relative
            }
        }
    }

    return $candidates | Where-Object { Resolve-ExistingFile -Path $_ } | Select-Object -Unique
}

function Resolve-CodexTarget {
    param(
        [string]$ExplicitPath,
        [string]$Mode
    )

    if ($ExplicitPath) {
        $resolved = Resolve-ExistingFile -Path $ExplicitPath
        if (-not $resolved) {
            throw "指定的 CodexPath 不存在：$ExplicitPath"
        }

        $fileName = [IO.Path]::GetFileName($resolved)
        if ($Mode -eq "CLI" -or ($fileName -ieq "codex.exe" -and $resolved -match "\\(bin|resources)\\codex\.exe$")) {
            $target = (& "New-CodexTarget" -Path $resolved -Kind "CLI" -DisplayName "Codex CLI")
            return $target
        }

        $target = (& "New-CodexTarget" -Path $resolved -Kind "Desktop" -DisplayName "ChatGPT/Codex desktop app")
        return $target
    }

    if ($Mode -in @("Desktop", "Auto")) {
        $desktop = @(Get-CodexDesktopCandidates | Select-Object -First 1)
        if ($desktop.Count -gt 0) {
            $desktopPath = $desktop[0]
            $target = (& "New-CodexTarget" -Path $desktopPath -Kind "Desktop" -DisplayName "ChatGPT/Codex desktop app")
            return $target
        }

        if ($Mode -eq "Desktop") {
            throw "未找到 ChatGPT/Codex 桌面应用。请用 -CodexPath 指定 ChatGPT.exe 或 Codex.exe，或改用 -LaunchMode CLI。"
        }
    }

    $cli = @(Get-CodexCliCandidates | Select-Object -First 1)
    if ($cli.Count -gt 0) {
        $cliPath = $cli[0]
        $target = (& "New-CodexTarget" -Path $cliPath -Kind "CLI" -DisplayName "Codex CLI")
        return $target
    }

    throw "未找到 ChatGPT/Codex 桌面应用或 codex CLI。请用 -CodexPath 指定 ChatGPT.exe、Codex.exe 或 codex.exe。"
}

function Stop-ExistingCodex {
    $processes = @(Get-Process | Where-Object { $_.ProcessName -in @("ChatGPT", "ChatGPT Classic", "Codex", "codex") })
    if ($processes.Count -eq 0) {
        return
    }

    Write-Step "关闭现有 ChatGPT/Codex 进程"
    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.Id -Force
            Write-Ok "已关闭 $($process.ProcessName) pid=$($process.Id)"
        }
        catch {
            Write-WarnLine "无法关闭 $($process.ProcessName) pid=$($process.Id)：$($_.Exception.Message)"
        }
    }
}

function Get-AppUserModelIdForExecutable {
    param([string]$FilePath)

    $resolvedPath = [IO.Path]::GetFullPath($FilePath)

    try {
        foreach ($pkg in Get-AppxPackage -ErrorAction Stop) {
            if (-not $pkg.InstallLocation -or -not $pkg.PackageFamilyName) {
                continue
            }

            $installLocation = [IO.Path]::GetFullPath([string]$pkg.InstallLocation).TrimEnd("\")
            if (-not $resolvedPath.StartsWith("$installLocation\", [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $manifestPath = Join-Path $installLocation "AppxManifest.xml"
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                continue
            }

            [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
            $relativeExecutable = $resolvedPath.Substring($installLocation.Length).TrimStart("\")
            $applications = $manifest.SelectNodes("/*[local-name()='Package']/*[local-name()='Applications']/*[local-name()='Application']")

            foreach ($application in $applications) {
                $manifestExecutable = ([string]$application.Executable).Replace("/", "\").TrimStart("\")
                if ($manifestExecutable -ieq $relativeExecutable -and $application.Id) {
                    return "$($pkg.PackageFamilyName)!$($application.Id)"
                }
            }
        }
    }
    catch {
        Write-WarnLine "无法解析 Windows 应用激活 ID：$($_.Exception.Message)"
    }

    return $null
}

function ConvertTo-WindowsCommandLineArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }
    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashCount = 0

    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
            [void]$builder.Append('"')
            $backslashCount = 0
            continue
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }
        [void]$builder.Append($character)
    }

    if ($backslashCount -gt 0) {
        [void]$builder.Append(('\' * ($backslashCount * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Start-PackagedDesktopApp {
    param(
        [string]$AppUserModelId,
        [string[]]$Arguments
    )

    if (-not ("CodexProxyLauncher.ApplicationActivator" -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CodexProxyLauncher
{
    [Flags]
    internal enum ActivateOptions
    {
        None = 0,
        DesignMode = 1,
        NoErrorUI = 2,
        NoSplashScreen = 4
    }

    [ComImport]
    [Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IApplicationActivationManager
    {
        [PreserveSig]
        int ActivateApplication(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string arguments,
            ActivateOptions options,
            out uint processId);

        [PreserveSig]
        int ActivateForFile(IntPtr appUserModelId, IntPtr itemArray, IntPtr verb, out uint processId);

        [PreserveSig]
        int ActivateForProtocol(IntPtr appUserModelId, IntPtr itemArray, out uint processId);
    }

    public static class ApplicationActivator
    {
        public static uint Activate(string appUserModelId, string arguments)
        {
            Type managerType = Type.GetTypeFromCLSID(new Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C"));
            object managerObject = Activator.CreateInstance(managerType);

            try
            {
                IApplicationActivationManager manager = (IApplicationActivationManager)managerObject;
                uint processId;
                int result = manager.ActivateApplication(appUserModelId, arguments, ActivateOptions.None, out processId);
                Marshal.ThrowExceptionForHR(result);
                return processId;
            }
            finally
            {
                if (managerObject != null && Marshal.IsComObject(managerObject))
                {
                    Marshal.FinalReleaseComObject(managerObject);
                }
            }
        }
    }
}
'@
    }

    $activationArguments = ($Arguments | ForEach-Object {
            ConvertTo-WindowsCommandLineArgument -Argument $_
        }) -join " "
    $activatedProcessId = [CodexProxyLauncher.ApplicationActivator]::Activate($AppUserModelId, $activationArguments)
    return $activatedProcessId
}

function Start-CodexProcessWithProxy {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$ProxyUrl,
        [string]$NoProxy
    )

    $workingDirectory = Split-Path -Parent $FilePath
    $appUserModelId = Get-AppUserModelIdForExecutable -FilePath $FilePath

    if ($appUserModelId) {
        Write-Ok "Windows 应用激活 ID：$appUserModelId"
        $activatedProcessId = Start-PackagedDesktopApp -AppUserModelId $appUserModelId -Arguments $Arguments
        Write-Ok "已通过 Windows 应用激活 API 启动，pid=$activatedProcessId"
        return
    }

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        $psi.WorkingDirectory = $workingDirectory
        $psi.UseShellExecute = $false

        foreach ($argument in $Arguments) {
            [void]$psi.ArgumentList.Add($argument)
        }

        foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")) {
            $psi.Environment[$name] = $ProxyUrl
        }
        foreach ($name in @("NO_PROXY", "no_proxy")) {
            $psi.Environment[$name] = $NoProxy
        }

        [System.Diagnostics.Process]::Start($psi) | Out-Null
        return
    }
    catch {
        $message = $_.Exception.Message
        if ($message -notmatch "Access is denied|拒绝访问") {
            throw
        }

        Write-WarnLine "直接启动失败：$message"
        Write-WarnLine "将使用 ShellExecute 兼容模式启动桌面应用。此模式无法注入环境变量，但会保留 --proxy-server 启动参数。"
    }

    $shellPsi = [System.Diagnostics.ProcessStartInfo]::new()
    $shellPsi.FileName = $FilePath
    $shellPsi.WorkingDirectory = $workingDirectory
    $shellPsi.UseShellExecute = $true
    foreach ($argument in $Arguments) {
        [void]$shellPsi.ArgumentList.Add($argument)
    }

    [System.Diagnostics.Process]::Start($shellPsi) | Out-Null
}

function Invoke-CodexCliWithProxy {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$ProxyUrl,
        [string]$NoProxy
    )

    $names = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy", "NO_PROXY", "no_proxy")
    $previous = @{}
    foreach ($name in $names) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
    }

    try {
        foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")) {
            [Environment]::SetEnvironmentVariable($name, $ProxyUrl, "Process")
        }
        foreach ($name in @("NO_PROXY", "no_proxy")) {
            [Environment]::SetEnvironmentVariable($name, $NoProxy, "Process")
        }

        & $FilePath @Arguments
        return $LASTEXITCODE
    }
    finally {
        foreach ($name in $names) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
        }
    }
}

$proxyUrl = "http://${HostName}:$Port"
$noProxy = "localhost,127.0.0.1,::1"

Write-Step "检查权限"
if (Test-IsAdministrator) {
    Write-WarnLine "当前是管理员 PowerShell；此方案不需要管理员。"
}
else {
    Write-Ok "当前是普通用户 PowerShell"
}

Write-Step "检查是否存在用户级代理环境变量"
$userProxyNames = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy")
$foundUserProxy = $false
foreach ($name in $userProxyNames) {
    $value = Get-UserEnvValue -Name $name
    if ($value) {
        $foundUserProxy = $true
        Write-WarnLine "用户级 $name=$value。建议运行 .\clear-user-proxy-env.ps1 清理，避免影响其它 App。"
    }
}
if (-not $foundUserProxy) {
    Write-Ok "未发现用户级代理环境变量"
}

Write-Step "检查本地代理端口"
if (Test-PortListening -Address $HostName -ListenPort $Port) {
    Write-Ok "${HostName}:$Port 正在监听"
}
else {
    Write-WarnLine "${HostName}:$Port 未监听。请确认 Clash Verge 已启动，mixed-port 为 $Port。"
}

Write-Step "检查 Windows WinINET 系统代理状态"
$winInetStates = @(Get-WinInetProxyStates)
foreach ($state in $winInetStates) {
    Write-Host "Source=$($state.Source)"
    if ($state.Error) {
        Write-Host "  Error=$($state.Error)"
        continue
    }
    Write-Host "  ProxyEnable=$($state.ProxyEnable)"
    Write-Host "  ProxyServer=$($state.ProxyServer)"
    Write-Host "  AutoConfigURL=$($state.AutoConfigURL)"
    Write-Host "  AutoDetect=$($state.AutoDetect)"
}
if (@($winInetStates | Where-Object { $_.SystemProxyEnabled }).Count -gt 0) {
    Write-WarnLine "Windows 系统代理已开启。此方案要求关闭系统代理。"
}
else {
    Write-Ok "Windows 系统代理未开启"
}

Write-Step "检查 Clash Verge 配置文件"
$configs = @(Get-ClashConfigCandidates)
if ($configs.Count -eq 0) {
    Write-WarnLine "未找到 Clash Verge 常见配置目录。若使用便携版，请手动确认 mixed-port 为 $Port，系统代理和 TUN 均关闭。"
}
else {
    $sawMixedPort = $false
    $sawTunEnabled = $false
    $clashSystemProxy = $null
    $clashProxyAutoConfig = $null

    foreach ($config in $configs) {
        Write-Host "配置文件: $config"
        try {
            $text = Get-Content -Raw -LiteralPath $config -ErrorAction Stop
        }
        catch {
            Write-WarnLine "无法读取 Clash Verge 配置文件，已跳过：$config；$($_.Exception.Message)"
            continue
        }

        $mixedPort = Get-YamlScalar -Text $text -Name "mixed-port"
        $vergeMixedPort = Get-YamlScalar -Text $text -Name "verge_mixed_port"
        if ($mixedPort -eq [string]$Port -or $vergeMixedPort -eq [string]$Port) {
            $sawMixedPort = $true
        }

        $systemProxyValue = Get-YamlScalar -Text $text -Name "enable_system_proxy"
        if ($null -ne $systemProxyValue) {
            $clashSystemProxy = $systemProxyValue
        }

        $proxyAutoConfigValue = Get-YamlScalar -Text $text -Name "proxy_auto_config"
        if ($null -ne $proxyAutoConfigValue) {
            $clashProxyAutoConfig = $proxyAutoConfigValue
        }

        if ((Get-YamlScalar -Text $text -Name "enable_tun_mode") -eq "true" -or (Test-TunEnabledInYaml -Path $config)) {
            $sawTunEnabled = $true
        }
    }

    if ($sawMixedPort) {
        Write-Ok "发现 mixed-port/verge_mixed_port: $Port"
    }
    else {
        Write-WarnLine "未在常见配置文件中发现 mixed-port: $Port，请在 Clash Verge 中确认混合端口。"
    }

    if ($clashSystemProxy -eq "true") {
        Write-WarnLine "Clash Verge enable_system_proxy=true。此方案要求在 Clash Verge 中关闭系统代理。"
    }
    elseif ($clashSystemProxy -eq "false") {
        Write-Ok "Clash Verge enable_system_proxy=false"
    }
    else {
        Write-WarnLine "未读取到 Clash Verge enable_system_proxy。"
    }

    if ($clashProxyAutoConfig) {
        Write-Host "proxy_auto_config=$clashProxyAutoConfig"
    }

    if ($sawTunEnabled) {
        Write-WarnLine "Clash Verge 配置显示 TUN 开启。此方案要求关闭 TUN。"
    }
    else {
        Write-Ok "未发现 Clash Verge TUN 开启配置"
    }
}

Write-Step "验证显式代理请求"
try {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $result = & curl.exe --silent --show-error -I --max-time 20 -x $proxyUrl "http://www.gstatic.com/generate_204" 2>&1
    $ErrorActionPreference = $previousErrorActionPreference
    $joined = $result -join "`n"
    if ($joined -match "204 No Content") {
        Write-Ok "显式使用 $proxyUrl 请求成功，返回 204 No Content"
    }
    else {
        Write-WarnLine "代理请求未返回 204。curl 输出如下："
        Write-Host $joined
    }
}
catch {
    if ($previousErrorActionPreference) {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    Write-WarnLine "curl 验证失败：$($_.Exception.Message)"
}

Write-Step "解析 ChatGPT/Codex 启动目标"
$codexTarget = Resolve-CodexTarget -ExplicitPath $CodexPath -Mode $LaunchMode
Write-Ok "目标类型：$($codexTarget.DisplayName)"
Write-Ok "目标路径：$($codexTarget.Path)"

if ($codexTarget.Kind -eq "Desktop") {
    $resolvedAppUserModelId = Get-AppUserModelIdForExecutable -FilePath $codexTarget.Path
    if ($resolvedAppUserModelId) {
        Write-Ok "启动方式：Windows 应用激活 API ($resolvedAppUserModelId)"
    }
    else {
        Write-Ok "启动方式：普通桌面进程"
    }
}

if ($VerifyOnly) {
    Write-Step "完成"
    Write-Host "VerifyOnly 模式不会启动 ChatGPT/Codex。"
    exit 0
}

$runningCodex = @(Get-Process | Where-Object { $_.ProcessName -in @("ChatGPT", "ChatGPT Classic", "Codex", "codex") })
if ($runningCodex.Count -gt 0 -and -not $RestartCodex) {
    Write-WarnLine "检测到 ChatGPT/Codex 已在运行。请先关闭应用，或使用 -RestartCodex，避免旧进程忽略新的代理参数。"
    exit 2
}
elseif ($RestartCodex) {
    Stop-ExistingCodex
}

Write-Step "启动 ChatGPT/Codex，仅对本次进程使用代理"
if ($codexTarget.Kind -eq "Desktop") {
    $arguments = @(
        "--proxy-server=$proxyUrl",
        "--proxy-bypass-list=localhost;127.0.0.1;::1"
    ) + $CodexArguments

    Write-Ok "启动参数：$($arguments -join ' ')"
    Start-CodexProcessWithProxy -FilePath $codexTarget.Path -Arguments $arguments -ProxyUrl $proxyUrl -NoProxy $noProxy
    Write-Ok "已启动 ChatGPT/Codex 桌面应用。代理只通过启动参数和临时进程环境传递，不写入系统或用户环境。"
}
else {
    Write-Ok "CLI 参数：$($CodexArguments -join ' ')"
    Write-Host "Codex CLI 将在当前 PowerShell 窗口中运行；退出 CLI 后，脚本会恢复本进程代理环境变量。"
    $exitCode = Invoke-CodexCliWithProxy -FilePath $codexTarget.Path -Arguments $CodexArguments -ProxyUrl $proxyUrl -NoProxy $noProxy
    exit $exitCode
}

[CmdletBinding()]
param(
    [string]$HostName = "127.0.0.1",
    [int]$Port = 7890,
    [string]$CodexPath,
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

    $output = & reg.exe query "HKCU\Environment" /v $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    foreach ($line in $output) {
        if ($line -match "^\s*$([Regex]::Escape($Name))\s+REG_\w+\s+(.+?)\s*$") {
            return $matches[1]
        }
    }

    return $null
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

    $lines = Get-Content -LiteralPath $Path
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

function Resolve-CodexPath {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (Test-Path -LiteralPath $ExplicitPath) {
            return (Resolve-Path -LiteralPath $ExplicitPath).Path
        }
        throw "指定的 CodexPath 不存在：$ExplicitPath"
    }

    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        $source = $cmd.Source
        $resourcesDir = Split-Path -Parent $source
        $appDir = Split-Path -Parent $resourcesDir
        $desktopExe = Join-Path $appDir "Codex.exe"
        if (Test-Path -LiteralPath $desktopExe) {
            return $desktopExe
        }
    }

    $packages = Get-ChildItem -LiteralPath "C:\Program Files\WindowsApps" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "OpenAI.Codex_*" } |
        Sort-Object LastWriteTime -Descending

    foreach ($pkg in $packages) {
        foreach ($relative in @("app\Codex.exe", "app\resources\codex.exe")) {
            $candidate = Join-Path $pkg.FullName $relative
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return $cmd.Source
    }

    throw "未找到 Codex 可执行文件。请用 -CodexPath 指定 Codex.exe。"
}

function Stop-ExistingCodex {
    $processes = @(Get-Process | Where-Object { $_.ProcessName -in @("Codex", "codex") })
    if ($processes.Count -eq 0) {
        return
    }

    Write-Step "关闭现有 Codex 进程"
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

function Start-CodexProcessWithProxy {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$ProxyUrl,
        [string]$NoProxy
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = Split-Path -Parent $FilePath
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
        $text = Get-Content -Raw -LiteralPath $config

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
    $result = & curl.exe -I --max-time 20 -x $proxyUrl "http://www.gstatic.com/generate_204" 2>&1
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
    Write-WarnLine "curl 验证失败：$($_.Exception.Message)"
}

if ($VerifyOnly) {
    Write-Step "完成"
    Write-Host "VerifyOnly 模式不会启动 Codex。"
    exit 0
}

$runningCodex = @(Get-Process | Where-Object { $_.ProcessName -in @("Codex", "codex") })
if ($runningCodex.Count -gt 0 -and -not $RestartCodex) {
    Write-WarnLine "检测到 Codex 已在运行。请先关闭 Codex，或使用 -RestartCodex，避免旧进程忽略新的代理参数。"
    exit 2
}
elseif ($RestartCodex) {
    Stop-ExistingCodex
}

Write-Step "启动 Codex，仅对 Codex 使用代理"
$resolvedCodexPath = Resolve-CodexPath -ExplicitPath $CodexPath
$arguments = @(
    "--proxy-server=$proxyUrl",
    "--proxy-bypass-list=localhost;127.0.0.1;::1"
)

Write-Ok "Codex 路径：$resolvedCodexPath"
Write-Ok "启动参数：$($arguments -join ' ')"

Start-CodexProcessWithProxy -FilePath $resolvedCodexPath -Arguments $arguments -ProxyUrl $proxyUrl -NoProxy $noProxy

Write-Ok "已启动 Codex。代理只通过启动参数和临时进程环境传递，不写入系统或用户环境。"

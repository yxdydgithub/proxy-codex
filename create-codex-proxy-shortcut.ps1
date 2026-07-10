[CmdletBinding()]
param(
    [string]$ShortcutName = "ChatGPT Codex via Clash Proxy",
    [ValidateSet("Desktop", "CLI", "Auto")]
    [string]$LaunchMode = "Desktop",
    [string]$CodexPath
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "start-codex-with-clash-proxy.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "找不到启动脚本：$scriptPath"
}

$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "$ShortcutName.lnk"
$powershell = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $powershell) {
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershell
$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy Bypass",
    "-File `"$scriptPath`"",
    "-LaunchMode $LaunchMode"
)
if ($CodexPath) {
    $arguments += "-CodexPath `"$CodexPath`""
}
$shortcut.Arguments = $arguments -join " "
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = "Start ChatGPT/Codex with Clash Verge proxy only for this app"
$shortcut.Save()

Write-Host "已创建快捷方式：$shortcutPath"


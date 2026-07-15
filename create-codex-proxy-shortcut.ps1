[CmdletBinding()]
param(
    [string]$ShortcutName = "ChatGPT Codex via Clash Proxy",
    [ValidateSet("Desktop", "CLI", "Auto")]
    [string]$LaunchMode = "Desktop",
    [string]$CodexPath,
    [switch]$NoRestartCodex
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
if (-not $NoRestartCodex) {
    $arguments += "-RestartCodex"
}

$shortcut.Arguments = $arguments -join " "
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = "Start ChatGPT/Codex with Clash Verge proxy; restart existing app by default"
$shortcut.Save()

Write-Host "已创建快捷方式：$shortcutPath"
Write-Host "启动模式：$LaunchMode"
if ($CodexPath) {
    Write-Host "Codex 路径：$CodexPath"
}
if ($NoRestartCodex) {
    Write-Host "快捷方式不会自动重启已有 ChatGPT/Codex。"
}
else {
    Write-Host "快捷方式已启用 -RestartCodex：若 ChatGPT/Codex 已在运行，会先关闭再重新启动。"
}

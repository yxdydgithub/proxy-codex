[CmdletBinding()]
param(
    [string]$ShortcutName = "Codex via Clash Proxy"
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
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = "Start Codex with Clash Verge proxy only for Codex"
$shortcut.Save()

Write-Host "已创建快捷方式：$shortcutPath"


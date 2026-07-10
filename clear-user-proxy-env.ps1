[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

$names = @(
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "NO_PROXY",
    "http_proxy",
    "https_proxy",
    "all_proxy",
    "no_proxy"
)

foreach ($name in $names) {
    $output = & reg.exe delete "HKCU\Environment" /v $name /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "已删除用户级环境变量：$name"
    }
}

Write-Host "完成。若 Codex 或其它终端已启动，请重启它们以清除已继承的旧环境变量。"


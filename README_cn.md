# Proxy Codex with Clash Verge

## 中文说明

让 ChatGPT 桌面应用中的 Codex、旧 Codex 桌面应用或 Codex CLI 在 Windows 上单独使用 Clash Verge / Mihomo 的本地代理 `127.0.0.1:7890`。
本方案不需要开启 Clash Verge 系统代理，不需要 TUN，不需要管理员 PowerShell，也不会影响其它应用。

### 当前版本适配依据

OpenAI 当前说明中，新的 ChatGPT 桌面应用已经整合 Chat、Work 和 Codex；旧 Codex 应用更新后会成为新的 ChatGPT 桌面应用。Windows 上 Codex 可通过 ChatGPT 桌面应用、CLI 或 IDE 扩展使用。因此脚本现在同时支持：

- 新版 ChatGPT 桌面应用：优先自动查找 `ChatGPT.exe`。
- 旧版 Codex 桌面应用：兼容查找 `Codex.exe`。
- Codex CLI：使用 `-LaunchMode CLI` 调用 `codex.exe` 或 `codex` 命令。

官方信息源：

- OpenAI Help Center: <https://help.openai.com/en/articles/20001276-moving-to-the-new-chatgpt-desktop-app>
- ChatGPT desktop app docs: <https://developers.openai.com/codex/app>
- Codex on Windows docs: <https://developers.openai.com/codex/windows>
- Codex CLI docs: <https://developers.openai.com/codex/cli>

### 适用场景

适用于以下目标：

- Clash Verge 只作为本地代理服务运行。
- Codex 单独走 `127.0.0.1:7890`。
- 其它应用不受影响。
- 不写入 Windows 用户级 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`。
- 不设置 WinHTTP 全局代理。
- 不开启 Clash Verge 系统代理。
- 不开启 Clash Verge TUN 模式。

### 工作原理

`start-codex-with-clash-proxy.ps1` 启动 ChatGPT/Codex 时会按目标类型分流。

桌面应用模式会做两件事：

1. 只给 Codex 子进程注入临时代理环境变量：

```text
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
ALL_PROXY=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,::1
```

2. 给 ChatGPT/Codex 桌面程序传入 Chromium / Electron 代理参数：

```text
--proxy-server=http://127.0.0.1:7890
--proxy-bypass-list=localhost;127.0.0.1;::1
```

CLI 模式不会传入 Chromium / Electron 参数，而是在当前 PowerShell 进程中临时设置上述代理环境变量后运行 `codex`。退出 CLI 后，脚本会恢复本进程原来的代理环境变量。

脚本使用 `.NET ProcessStartInfo` 直接给桌面应用子进程注入环境变量，不会修改当前 PowerShell、系统代理、WinHTTP 代理或用户级环境变量。

### Clash Verge 前置要求

在 Clash Verge 中确认：

- Clash Verge 正在运行。
- Mixed Port / 混合端口为 `7890`。
- 系统代理关闭。
- TUN 模式关闭。

### 文件说明

| 文件 | 作用 |
| --- | --- |
| `start-codex-with-clash-proxy.ps1` | 启动 ChatGPT/Codex，并仅对本次进程注入代理配置。 |
| `clear-user-proxy-env.ps1` | 清理旧方案写入的用户级代理环境变量。 |
| `create-codex-proxy-shortcut.ps1` | 创建桌面快捷方式，方便一键启动。 |
| `README.md` | 使用说明。 |

### 快速开始

先关闭已经打开的 ChatGPT/Codex，然后在普通 PowerShell 中运行。默认会启动桌面应用模式，并优先匹配新版 `ChatGPT.exe`：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\start-codex-with-clash-proxy.ps1
```

如果 ChatGPT/Codex 已经在运行，桌面程序可能复用旧进程并忽略新的代理参数。需要自动重启时：

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

只检查配置，不启动 Codex：

```powershell
.\start-codex-with-clash-proxy.ps1 -VerifyOnly
```

启动 Codex CLI：

```powershell
.\start-codex-with-clash-proxy.ps1 -LaunchMode CLI
```

自动检测桌面应用，找不到桌面应用时回退到 CLI：

```powershell
.\start-codex-with-clash-proxy.ps1 -LaunchMode Auto
```

创建桌面快捷方式：

```powershell
.\create-codex-proxy-shortcut.ps1
```

### 脚本参数

#### `start-codex-with-clash-proxy.ps1`

```powershell
.\start-codex-with-clash-proxy.ps1 `
  -HostName 127.0.0.1 `
  -Port 7890 `
  -LaunchMode Desktop `
  -CodexPath "C:\Path\To\ChatGPT.exe" `
  -CodexArguments "--some-extra-argument" `
  -RestartCodex `
  -VerifyOnly
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-HostName` | `127.0.0.1` | Clash Verge 本地代理地址。 |
| `-Port` | `7890` | Clash Verge mixed-port。 |
| `-LaunchMode` | `Desktop` | `Desktop` 启动 ChatGPT/Codex 桌面应用；`CLI` 在当前终端运行 Codex CLI；`Auto` 先找桌面应用，找不到再找 CLI。 |
| `-CodexPath` | 自动检测 | 手动指定 `ChatGPT.exe`、`Codex.exe` 或 `codex.exe` 路径。 |
| `-CodexArguments` | 空 | 追加传给目标程序的参数。桌面模式会追加在代理参数后；CLI 模式会直接传给 `codex`。 |
| `-RestartCodex` | 关闭 | 自动关闭已有 ChatGPT/Codex 进程后再启动。 |
| `-VerifyOnly` | 关闭 | 只检查配置和可启动目标，不启动 ChatGPT/Codex。 |

#### `clear-user-proxy-env.ps1`

如果以前写入过用户级代理环境变量，运行：

```powershell
.\clear-user-proxy-env.ps1
```

它会删除：

```text
HTTP_PROXY
HTTPS_PROXY
ALL_PROXY
NO_PROXY
http_proxy
https_proxy
all_proxy
no_proxy
```

清理后请重启已经打开的 PowerShell 或 Codex，确保旧环境变量不再被继承。

#### `create-codex-proxy-shortcut.ps1`

创建桌面快捷方式：

```powershell
.\create-codex-proxy-shortcut.ps1
```

默认创建的快捷方式会带上 `-RestartCodex`。通过快捷方式启动时，如果检测到 ChatGPT/Codex 已在后台运行，会先关闭旧进程，再重新用代理参数启动。

自定义快捷方式名称：

```powershell
.\create-codex-proxy-shortcut.ps1 -ShortcutName "Codex via Clash"
```

创建 CLI 模式快捷方式：

```powershell
.\create-codex-proxy-shortcut.ps1 -ShortcutName "Codex CLI via Clash" -LaunchMode CLI
```

如果不希望快捷方式自动重启已有 Codex：

```powershell
.\create-codex-proxy-shortcut.ps1 -NoRestartCodex
```

### 系统代理检测

脚本会同时检查 Windows WinINET 和 Clash Verge 配置，避免只看一个字段导致误判。

Windows WinINET 检查：

- `ProxyEnable`
- `ProxyServer`
- `AutoConfigURL`
- `AutoDetect`

Clash Verge 配置检查：

- `enable_system_proxy`
- `proxy_auto_config`
- `verge_mixed_port`
- `enable_tun_mode`
- 生成配置中的 `tun.enable`

判断规则：

- `ProxyEnable=1` 且 `ProxyServer` 非空：系统手动代理开启。
- `AutoConfigURL` 非空：系统 PAC 代理开启。
- `enable_system_proxy: true`：Clash Verge 侧系统代理开启。
- 仅 `AutoDetect=1` 不等同于 Clash Verge 系统代理开启，但脚本会显示该状态。

### 常见问题

#### `127.0.0.1:7890` 未监听

启动 Clash Verge，并确认 Mixed Port 为 `7890`。

#### 脚本提示系统代理开启

在 Clash Verge 里关闭“系统代理”，并确认 Windows 代理设置没有手动代理或 PAC 地址。

#### 脚本提示 TUN 开启

在 Clash Verge 里关闭 TUN 模式。

#### ChatGPT/Codex 已经运行

关闭 Codex 后重新运行脚本，或使用：

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

ChatGPT/Codex 桌面程序可能复用已有进程，导致新的代理启动参数不生效。

#### 找不到桌面应用

运行：

```powershell
.\start-codex-with-clash-proxy.ps1 -LaunchMode CLI
```

或者手动指定路径：

```powershell
.\start-codex-with-clash-proxy.ps1 -CodexPath "C:\Program Files\WindowsApps\...\app\ChatGPT.exe"
```

#### 代理请求失败

检查 Clash Verge 当前节点是否可用，并确认安全软件没有拦截 `verge-mihomo.exe`。

[返回首页](README.md)

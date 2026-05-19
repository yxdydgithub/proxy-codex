<h1 align="center">Proxy Codex with Clash Verge</h1>

<p align="center">
  Launch Codex through <code>127.0.0.1:7890</code> without enabling system proxy, TUN, or admin mode.
</p>

<p align="center">
  <a href="#中文说明">
    <img alt="中文说明" src="https://img.shields.io/badge/语言-中文-blue?style=for-the-badge">
  </a>
  <a href="#english">
    <img alt="English" src="https://img.shields.io/badge/Language-English-green?style=for-the-badge">
  </a>
</p>

<p align="center">
  <code>Windows</code> · <code>PowerShell</code> · <code>Clash Verge</code> · <code>Codex</code>
</p>

---

## 中文说明

让 Codex 在 Windows 上单独使用 Clash Verge / Mihomo 的本地代理 `127.0.0.1:7890`。  
本方案不需要开启 Clash Verge 系统代理，不需要 TUN，不需要管理员 PowerShell，也不会影响其它应用。

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

`start-codex-with-clash-proxy.ps1` 启动 Codex 时会做两件事：

1. 只给 Codex 子进程注入临时代理环境变量：

```text
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
ALL_PROXY=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,::1
```

2. 给 Codex 桌面程序传入 Chromium / Electron 代理参数：

```text
--proxy-server=http://127.0.0.1:7890
--proxy-bypass-list=localhost;127.0.0.1;::1
```

脚本使用 `.NET ProcessStartInfo` 直接给 Codex 子进程注入环境变量，不会修改当前 PowerShell、系统代理、WinHTTP 代理或用户级环境变量。

### Clash Verge 前置要求

在 Clash Verge 中确认：

- Clash Verge 正在运行。
- Mixed Port / 混合端口为 `7890`。
- 系统代理关闭。
- TUN 模式关闭。

### 文件说明

| 文件 | 作用 |
| --- | --- |
| `start-codex-with-clash-proxy.ps1` | 启动 Codex，并仅对 Codex 注入代理配置。 |
| `clear-user-proxy-env.ps1` | 清理旧方案写入的用户级代理环境变量。 |
| `create-codex-proxy-shortcut.ps1` | 创建桌面快捷方式，方便一键启动。 |
| `README.md` | 使用说明。 |

### 快速开始

先关闭已经打开的 Codex，然后在普通 PowerShell 中运行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\start-codex-with-clash-proxy.ps1
```

如果 Codex 已经在运行，桌面程序可能复用旧进程并忽略新的代理参数。需要自动重启 Codex 时：

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

只检查配置，不启动 Codex：

```powershell
.\start-codex-with-clash-proxy.ps1 -VerifyOnly
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
  -CodexPath "C:\Path\To\Codex.exe" `
  -RestartCodex `
  -VerifyOnly
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-HostName` | `127.0.0.1` | Clash Verge 本地代理地址。 |
| `-Port` | `7890` | Clash Verge mixed-port。 |
| `-CodexPath` | 自动检测 | 手动指定 Codex 可执行文件路径。 |
| `-RestartCodex` | 关闭 | 自动关闭已有 Codex 进程后再启动。 |
| `-VerifyOnly` | 关闭 | 只检查配置，不启动 Codex。 |

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

自定义快捷方式名称：

```powershell
.\create-codex-proxy-shortcut.ps1 -ShortcutName "Codex via Clash"
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

#### Codex 已经运行

关闭 Codex 后重新运行脚本，或使用：

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

Codex 桌面程序可能复用已有进程，导致新的代理启动参数不生效。

#### 代理请求失败

检查 Clash Verge 当前节点是否可用，并确认安全软件没有拦截 `verge-mihomo.exe`。

[Back to top](#proxy-codex-with-clash-verge)

---

## English

This repository lets Codex use a local Clash Verge / Mihomo proxy at `127.0.0.1:7890` on Windows.  
It does not require Clash Verge system proxy, TUN mode, administrator PowerShell, or any global proxy configuration.

### Use Case

Use this when:

- Clash Verge should only listen as a local proxy service.
- Codex should use `127.0.0.1:7890`.
- Other applications should not be affected.
- Windows user-level `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` should not be written.
- WinHTTP global proxy should not be changed.
- Clash Verge system proxy should remain disabled.
- Clash Verge TUN mode should remain disabled.

### How It Works

`start-codex-with-clash-proxy.ps1` does two things when launching Codex:

1. Injects temporary proxy environment variables only into the Codex child process:

```text
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
ALL_PROXY=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,::1
```

2. Passes Chromium / Electron proxy arguments to the Codex desktop app:

```text
--proxy-server=http://127.0.0.1:7890
--proxy-bypass-list=localhost;127.0.0.1;::1
```

The script uses `.NET ProcessStartInfo` to inject proxy variables directly into the Codex child process. It does not modify the current PowerShell process, Windows system proxy, WinHTTP proxy, or user-level environment variables.

### Clash Verge Requirements

In Clash Verge, make sure:

- Clash Verge is running.
- Mixed Port is `7890`.
- System Proxy is disabled.
- TUN Mode is disabled.

### Files

| File | Purpose |
| --- | --- |
| `start-codex-with-clash-proxy.ps1` | Starts Codex with proxy settings applied only to Codex. |
| `clear-user-proxy-env.ps1` | Removes user-level proxy environment variables left by older approaches. |
| `create-codex-proxy-shortcut.ps1` | Creates a desktop shortcut for launching Codex through the script. |
| `README.md` | Documentation. |

### Quick Start

Close any running Codex window first, then run this in a normal non-admin PowerShell window:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\start-codex-with-clash-proxy.ps1
```

If Codex is already running, the desktop app may reuse the old process and ignore new proxy startup arguments. To restart Codex automatically:

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

Check configuration without launching Codex:

```powershell
.\start-codex-with-clash-proxy.ps1 -VerifyOnly
```

Create a desktop shortcut:

```powershell
.\create-codex-proxy-shortcut.ps1
```

### Script Parameters

#### `start-codex-with-clash-proxy.ps1`

```powershell
.\start-codex-with-clash-proxy.ps1 `
  -HostName 127.0.0.1 `
  -Port 7890 `
  -CodexPath "C:\Path\To\Codex.exe" `
  -RestartCodex `
  -VerifyOnly
```

| Parameter | Default | Description |
| --- | --- | --- |
| `-HostName` | `127.0.0.1` | Local Clash Verge proxy host. |
| `-Port` | `7890` | Clash Verge mixed port. |
| `-CodexPath` | auto-detect | Manually specify the Codex executable path. |
| `-RestartCodex` | off | Stop existing Codex processes before launching. |
| `-VerifyOnly` | off | Check configuration only; do not start Codex. |

#### `clear-user-proxy-env.ps1`

If you previously wrote user-level proxy environment variables, run:

```powershell
.\clear-user-proxy-env.ps1
```

It removes:

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

After cleanup, restart any already-open PowerShell or Codex windows so they no longer inherit old environment variables.

#### `create-codex-proxy-shortcut.ps1`

Create a desktop shortcut:

```powershell
.\create-codex-proxy-shortcut.ps1
```

Customize the shortcut name:

```powershell
.\create-codex-proxy-shortcut.ps1 -ShortcutName "Codex via Clash"
```

### System Proxy Detection

The script checks both Windows WinINET and Clash Verge configuration to avoid false readings.

Windows WinINET checks:

- `ProxyEnable`
- `ProxyServer`
- `AutoConfigURL`
- `AutoDetect`

Clash Verge config checks:

- `enable_system_proxy`
- `proxy_auto_config`
- `verge_mixed_port`
- `enable_tun_mode`
- generated `tun.enable`

Rules:

- `ProxyEnable=1` with a non-empty `ProxyServer` means manual system proxy is enabled.
- A non-empty `AutoConfigURL` means PAC system proxy is enabled.
- `enable_system_proxy: true` means Clash Verge system proxy is enabled.
- `AutoDetect=1` alone is shown but not treated as Clash Verge system proxy.

### Troubleshooting

#### `127.0.0.1:7890` is not listening

Start Clash Verge and make sure Mixed Port is `7890`.

#### System proxy is enabled

Disable System Proxy in Clash Verge and make sure Windows proxy settings do not contain a manual proxy or PAC URL.

#### TUN is enabled

Disable TUN Mode in Clash Verge.

#### Codex is already running

Close Codex and run the script again, or use:

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

The Codex desktop app may reuse an existing process and ignore new proxy startup parameters.

#### Proxy request failed

Check that your Clash Verge node works and that security software is not blocking `verge-mihomo.exe`.

[Back to top](#proxy-codex-with-clash-verge)


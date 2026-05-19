# Proxy Codex with Clash Verge

让 Codex 在 Windows 上单独使用 Clash Verge / Mihomo 的本地代理 `127.0.0.1:7890`，不需要开启系统代理，不需要 TUN，不需要管理员权限。

This repository lets Codex use a local Clash Verge / Mihomo proxy at `127.0.0.1:7890` on Windows, without enabling system proxy, TUN mode, or administrator privileges.

## 适用场景 / Use Case

适用于以下目标：

- Clash Verge 只作为本地代理服务运行。
- Codex 单独走 `127.0.0.1:7890`。
- 其它应用不受影响。
- 不写入 Windows 用户级 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`。
- 不设置 WinHTTP 全局代理。
- 不开启 Clash Verge 系统代理。
- 不开启 Clash Verge TUN 模式。

Use this when:

- Clash Verge should only listen as a local proxy service.
- Codex should use `127.0.0.1:7890`.
- Other applications should not be affected.
- Windows user-level proxy environment variables should not be written.
- WinHTTP global proxy should not be changed.
- Clash Verge system proxy should remain disabled.
- Clash Verge TUN mode should remain disabled.

## 工作原理 / How It Works

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

The script uses `.NET ProcessStartInfo` to inject proxy variables only into the Codex child process. It does not modify the current PowerShell process, Windows system proxy, WinHTTP proxy, or user-level environment variables.

## Clash Verge 前置要求 / Clash Verge Requirements

在 Clash Verge 中确认：

- Clash Verge 正在运行。
- Mixed Port / 混合端口为 `7890`。
- 系统代理关闭。
- TUN 模式关闭。

In Clash Verge, make sure:

- Clash Verge is running.
- Mixed Port is `7890`.
- System Proxy is disabled.
- TUN Mode is disabled.

## 文件说明 / Files

| File | Purpose |
| --- | --- |
| `start-codex-with-clash-proxy.ps1` | 启动 Codex，并仅对 Codex 注入代理配置。 Starts Codex with proxy settings applied only to Codex. |
| `clear-user-proxy-env.ps1` | 清理旧方案写入的用户级代理环境变量。 Removes user-level proxy environment variables left by older approaches. |
| `create-codex-proxy-shortcut.ps1` | 创建桌面快捷方式，方便一键启动。 Creates a desktop shortcut for launching Codex through the script. |
| `README.md` | 使用说明。 Documentation. |

## 快速开始 / Quick Start

1. 关闭已经打开的 Codex。
2. 确认 Clash Verge 已启动，`127.0.0.1:7890` 可用。
3. 在普通 PowerShell 中运行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\start-codex-with-clash-proxy.ps1
```

If Codex is already running, close it first. Then run the command above in a normal, non-admin PowerShell window.

## 推荐启动方式 / Recommended Launch Command

如果希望脚本自动关闭旧的 Codex 进程并重新启动：

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

Use `-RestartCodex` when an existing Codex process may reuse old startup settings.

## 只检查不启动 / Verify Only

```powershell
.\start-codex-with-clash-proxy.ps1 -VerifyOnly
```

该模式会检查：

- 当前是否为普通用户 PowerShell。
- 是否存在用户级代理环境变量。
- `127.0.0.1:7890` 是否正在监听。
- Windows WinINET 系统代理是否开启。
- Clash Verge 配置中的系统代理和 TUN 状态。
- 显式使用 `127.0.0.1:7890` 的代理请求是否成功。

This mode validates the local proxy and proxy-related system state without starting Codex.

## 参数说明 / Script Parameters

### `start-codex-with-clash-proxy.ps1`

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
| `-HostName` | `127.0.0.1` | Clash Verge 本地代理地址。 Local proxy host. |
| `-Port` | `7890` | Clash Verge mixed-port。 Clash Verge mixed port. |
| `-CodexPath` | auto-detect | 手动指定 Codex 可执行文件路径。 Manually specify Codex executable path. |
| `-RestartCodex` | off | 自动关闭已有 Codex 进程后再启动。 Stop existing Codex processes before launching. |
| `-VerifyOnly` | off | 只检查配置，不启动 Codex。 Check only; do not start Codex. |

### `clear-user-proxy-env.ps1`

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

After cleanup, restart any already-open PowerShell or Codex windows so they no longer inherit old environment variables.

### `create-codex-proxy-shortcut.ps1`

创建桌面快捷方式：

```powershell
.\create-codex-proxy-shortcut.ps1
```

自定义快捷方式名称：

```powershell
.\create-codex-proxy-shortcut.ps1 -ShortcutName "Codex via Clash"
```

Create a desktop shortcut that launches Codex through `start-codex-with-clash-proxy.ps1`.

## 系统代理检测 / System Proxy Detection

脚本会同时检查 Windows WinINET 和 Clash Verge 配置，避免只看一个字段导致误判。

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

判断规则：

- `ProxyEnable=1` 且 `ProxyServer` 非空：系统手动代理开启。
- `AutoConfigURL` 非空：系统 PAC 代理开启。
- `enable_system_proxy: true`：Clash Verge 侧系统代理开启。
- 仅 `AutoDetect=1` 不等同于 Clash Verge 系统代理开启，但脚本会显示该状态。

Rules:

- `ProxyEnable=1` with a non-empty `ProxyServer` means manual system proxy is enabled.
- A non-empty `AutoConfigURL` means PAC system proxy is enabled.
- `enable_system_proxy: true` means Clash Verge system proxy is enabled.
- `AutoDetect=1` alone is shown but not treated as Clash Verge system proxy.

## 常见问题 / Troubleshooting

### `127.0.0.1:7890` 未监听 / Port is not listening

启动 Clash Verge，并确认 Mixed Port 为 `7890`。

Start Clash Verge and make sure Mixed Port is `7890`.

### 脚本提示系统代理开启 / System proxy is enabled

在 Clash Verge 里关闭“系统代理”，并确认 Windows 代理设置没有手动代理或 PAC 地址。

Disable System Proxy in Clash Verge and make sure Windows proxy settings do not contain a manual proxy or PAC URL.

### 脚本提示 TUN 开启 / TUN is enabled

在 Clash Verge 里关闭 TUN 模式。

Disable TUN Mode in Clash Verge.

### Codex 已经运行 / Codex is already running

关闭 Codex 后重新运行脚本，或使用：

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

Codex desktop app may reuse an existing process and ignore new proxy startup parameters.

### 代理请求失败 / Proxy request failed

检查 Clash Verge 当前节点是否可用，并确认安全软件没有拦截 `verge-mihomo.exe`。

Check that your Clash Verge node works and that security software is not blocking `verge-mihomo.exe`.


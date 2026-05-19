# Proxy Codex with Clash Verge

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

[Back to home](README.md)

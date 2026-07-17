# Proxy Codex with Clash Verge

## English

This repository lets Codex in the ChatGPT desktop app, the legacy Codex desktop app, or Codex CLI use a local Clash Verge / Mihomo proxy at `127.0.0.1:7890` on Windows.
It does not require Clash Verge system proxy, TUN mode, administrator PowerShell, or any global proxy configuration.

### Current Version Basis

OpenAI currently documents the new ChatGPT desktop app as combining Chat, Work, and Codex. The legacy Codex app becomes the new ChatGPT desktop app after updating. On Windows, Codex is available through the ChatGPT desktop app, the CLI, or the IDE extension. This repository now supports:

- New ChatGPT desktop app: auto-detects `ChatGPT.exe` first.
- Legacy Codex desktop app: keeps compatibility with `Codex.exe`.
- Codex CLI: use `-LaunchMode CLI` to run `codex.exe` or the `codex` command.

Official sources:

- OpenAI Help Center: <https://help.openai.com/en/articles/20001276-moving-to-the-new-chatgpt-desktop-app>
- ChatGPT desktop app docs: <https://developers.openai.com/codex/app>
- Codex on Windows docs: <https://developers.openai.com/codex/windows>
- Codex CLI docs: <https://developers.openai.com/codex/cli>

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

`start-codex-with-clash-proxy.ps1` branches by target type when launching ChatGPT/Codex.

Desktop mode does two things:

1. Injects temporary proxy environment variables only into the Codex child process:

```text
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
ALL_PROXY=http://127.0.0.1:7890
NO_PROXY=localhost,127.0.0.1,::1
```

2. Passes Chromium / Electron proxy arguments to the ChatGPT/Codex desktop app:

```text
--proxy-server=http://127.0.0.1:7890
--proxy-bypass-list=localhost;127.0.0.1;::1
```

CLI mode does not pass Chromium / Electron arguments. Instead, it temporarily sets the proxy environment variables in the current PowerShell process, runs `codex`, and restores the previous process environment after the CLI exits.

The script uses `.NET ProcessStartInfo` to inject proxy variables directly into the desktop app child process. It does not modify the current PowerShell process, Windows system proxy, WinHTTP proxy, or user-level environment variables.

### Clash Verge Requirements

In Clash Verge, make sure:

- Clash Verge is running.
- Mixed Port is `7890`.
- System Proxy is disabled.
- TUN Mode is disabled.

### Files

| File | Purpose |
| --- | --- |
| `start-codex-with-clash-proxy.ps1` | Starts ChatGPT/Codex with proxy settings applied only to this process. |
| `clear-user-proxy-env.ps1` | Removes user-level proxy environment variables left by older approaches. |
| `create-codex-proxy-shortcut.ps1` | Creates a desktop shortcut for launching Codex through the script. |
| `README.md` | Documentation. |

### Quick Start

Close any running ChatGPT/Codex window first, then run this in a normal non-admin PowerShell window. The default is desktop mode, preferring the new `ChatGPT.exe` entry:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\start-codex-with-clash-proxy.ps1
```

If ChatGPT/Codex is already running, the desktop app may reuse the old process and ignore new proxy startup arguments. To restart automatically:

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

Check configuration without launching ChatGPT/Codex:

```powershell
.\start-codex-with-clash-proxy.ps1 -VerifyOnly
```

Start Codex CLI:

```powershell
.\start-codex-with-clash-proxy.ps1 -LaunchMode CLI
```

Auto-detect the desktop app first and fall back to CLI if needed:

```powershell
.\start-codex-with-clash-proxy.ps1 -LaunchMode Auto
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
  -LaunchMode Desktop `
  -CodexPath "C:\Path\To\ChatGPT.exe" `
  -CodexArguments "--some-extra-argument" `
  -RestartCodex `
  -VerifyOnly
```

| Parameter | Default | Description |
| --- | --- | --- |
| `-HostName` | `127.0.0.1` | Local Clash Verge proxy host. |
| `-Port` | `7890` | Clash Verge mixed port. |
| `-LaunchMode` | `Desktop` | `Desktop` starts the ChatGPT/Codex desktop app; `CLI` runs Codex CLI in the current terminal; `Auto` tries desktop first and falls back to CLI. |
| `-CodexPath` | auto-detect | Manually specify `ChatGPT.exe`, `Codex.exe`, or `codex.exe`. |
| `-CodexArguments` | empty | Extra arguments passed to the target. Desktop mode appends them after proxy arguments; CLI mode passes them directly to `codex`. |
| `-RestartCodex` | off | Stop existing ChatGPT/Codex processes before launching. |
| `-VerifyOnly` | off | Check configuration and the launch target only; do not start ChatGPT/Codex. |

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

The shortcut includes `-RestartCodex` by default. When launched, it closes any existing ChatGPT/Codex process first, then starts it again with the proxy arguments.

Customize the shortcut name:

```powershell
.\create-codex-proxy-shortcut.ps1 -ShortcutName "Codex via Clash"
```

Create a CLI-mode shortcut:

```powershell
.\create-codex-proxy-shortcut.ps1 -ShortcutName "Codex CLI via Clash" -LaunchMode CLI
```

If you do not want the shortcut to restart an existing Codex process:

```powershell
.\create-codex-proxy-shortcut.ps1 -NoRestartCodex
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

#### ChatGPT/Codex is already running

Close Codex and run the script again, or use:

```powershell
.\start-codex-with-clash-proxy.ps1 -RestartCodex
```

The ChatGPT/Codex desktop app may reuse an existing process and ignore new proxy startup parameters.

#### Desktop app cannot be found

Run:

```powershell
.\start-codex-with-clash-proxy.ps1 -LaunchMode CLI
```

Or manually specify the executable:

```powershell
.\start-codex-with-clash-proxy.ps1 -CodexPath "C:\Program Files\WindowsApps\...\app\ChatGPT.exe"
```

#### `ChatGPT.exe` under WindowsApps fails with `Access is denied`

Newer Codex/ChatGPT builds may be installed under `C:\Program Files\WindowsApps`. The MSIX package can reject direct execution of its packaged `ChatGPT.exe`, and ShellExecute may fail with the same `Access is denied` error.

The script now resolves the application activation ID from `AppxManifest.xml` and launches it through the Windows application activation API while passing `--proxy-server=http://127.0.0.1:7890`. This path does not require administrator rights, enable the system proxy, or write system/user environment variables. Direct process startup with temporary process environment variables is retained for non-MSIX desktop installations only.

#### Proxy request failed

Check that your Clash Verge node works and that security software is not blocking `verge-mihomo.exe`.

[Back to home](README.md)

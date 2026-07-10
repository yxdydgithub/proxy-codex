<h1 align="center">Proxy Codex with Clash Verge</h1>

<p align="center">
  Launch ChatGPT/Codex through <code>127.0.0.1:7890</code> without enabling system proxy, TUN, or admin mode.
</p>

<p align="center">
  让 ChatGPT 桌面应用中的 Codex、旧 Codex 桌面应用或 Codex CLI 在 Windows 上单独使用 Clash Verge / Mihomo 的本地代理，不影响其它应用。
</p>

<p align="center">
  <a href="README_cn.md">
    <img alt="中文说明" src="https://img.shields.io/badge/语言-中文-blue?style=for-the-badge">
  </a>
  <a href="README_en.md">
    <img alt="English" src="https://img.shields.io/badge/Language-English-green?style=for-the-badge">
  </a>
</p>

<p align="center">
  <code>Windows</code> · <code>PowerShell</code> · <code>Clash Verge</code> · <code>ChatGPT Codex</code>
</p>

---

## Choose Your Language

| Language | Documentation |
| --- | --- |
| 中文 | [README_cn.md](README_cn.md) |
| English | [README_en.md](README_en.md) |

## Quick Preview

- Uses Clash Verge mixed-port `127.0.0.1:7890`.
- Does not enable Clash Verge system proxy.
- Does not enable TUN mode.
- Does not write user-level proxy environment variables.
- Supports the current ChatGPT desktop app, the legacy Codex desktop app, and Codex CLI.
- Applies proxy settings only to the ChatGPT/Codex process launched by the script.

## Main Script

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\start-codex-with-clash-proxy.ps1
```

CLI mode:

```powershell
.\start-codex-with-clash-proxy.ps1 -LaunchMode CLI
```

For full usage, choose a language above.


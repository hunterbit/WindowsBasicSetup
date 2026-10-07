# WindowsBasicSetup
 Windows Auto Setup Script

An automation script (`setup.cmd` + `setup.ps1` + `config.json`) for quick Windows configuration after a fresh install. Run it once — it handles everything from registry tweaks and software installation to Windows Update, rebooting and resuming automatically until the system is fully up to date.

---

## Features

- 🎨 **Wallpaper & Lock Screen** — sets a custom image for both desktop and lock screen, disabling Windows Spotlight
- 🌑 **Dark Theme** — enables dark mode for apps and system UI
- 🖱️ **Classic Context Menu** — restores the full right-click menu on Windows 11
- 📂 **File Extensions** — makes file extensions visible in Explorer
- 🔒 **UAC Disabled** — removes User Account Control prompts
- ⚡ **Power Plan** — disables standby, monitor timeout and disk timeout; sets boot timeout to 3 seconds
- 🔍 **Search** — disables Cortana and Bing integration in Windows Search
- 🛡️ **Security Health** — restores the Security Health icon in the system tray
- 📋 **Context Menu** — adds CopyTo and MoveTo entries to the right-click menu
- ☑️ **App selection menu** — at startup the script lists the programs from `config.json` in the terminal and lets you tick which ones to install
- 🍫 **Chocolatey** — installed automatically (only if at least one package is selected) and used to deploy the selected programs. Default catalog:
  - Google Chrome, Firefox
  - VLC, K-Lite Codec Pack Mega
  - 7-Zip, Everything, TeraCopy
  - Adobe Reader, HWiNFO, Java Runtime
  - Notepad++, RustDesk
- 📦 **Office 2024** — optional; downloads and runs the official Microsoft installer (Italian, x64 by default). A valid license is required to activate it
- 🔄 **Windows Update Loop** — installs all available updates, reboots if needed, and resumes automatically via Scheduled Task until no updates remain

---

## Requirements

- Windows 10 or Windows 11 (Home and Pro supported)
- Internet connection
- Administrator privileges (the script self-elevates automatically)

---

## Usage

1. Download `setup.cmd`, `setup.ps1` and `config.json` and place them in the **same folder**
2. Double-click `setup.cmd`
3. Accept the UAC prompt
4. Pick the programs to install in the menu and press Enter
5. Wait — the script will handle the rest, including reboots

> After each reboot, Windows Update will resume automatically. No need to re-run anything manually.

### Choosing the programs

| Key | Action |
|-----|--------|
| Up / Down | Move |
| Space | Tick / untick the highlighted program |
| `A` / `N` | Select all / none |
| Enter | Confirm and start |
| Esc | Install no programs (tweaks and Windows Update still run) |

If the console window is too small for the list, the script falls back to a numbered prompt: type the numbers to toggle, Enter to confirm, `0` to install nothing.

### config.json

`config.json` is the program catalog shown in the menu:

```json
{
  "interactive": true,
  "apps": [
    { "id": "googlechrome", "name": "Google Chrome", "selected": true }
  ],
  "office": {
    "name": "Microsoft Office 2024 ProPlus",
    "selected": true,
    "productId": "ProPlus2024Retail",
    "language": "it-it",
    "platform": "x64"
  }
}
```

- `apps[].id` — Chocolatey package name (required); `name` — label shown in the menu; `selected` — pre-ticked or not (default `true`)
- `office` — remove the whole block to drop Office from the menu
- `interactive` — set to `false` to skip the menu and install everything with `"selected": true`. Same effect as running `setup.ps1 -Unattended`

---

## File Overview

| File | Role |
|------|------|
| `setup.cmd` | Launcher — applies registry tweaks, then calls `setup.ps1` |
| `setup.ps1` | Main script — program selection, wallpaper, software, Office, Windows Update loop |
| `config.json` | Program catalog and default selection |
| `Stop-WindowsUpdateLoop.ps1` | Stops the update/reboot loop and cleans up the Scheduled Task |

---

## Notes

- The Office 2024 installer is downloaded directly from Microsoft's servers (`c2rsetup.officeapps.live.com`) — no third-party source involved
- The Windows Update Scheduled Task (`SetupWindowsUpdate`) is automatically removed once all updates are installed
- The `SETUP_UPDATE_MODE` environment variable is used internally to skip the first-run block on post-reboot cycles — it is also cleaned up automatically

---

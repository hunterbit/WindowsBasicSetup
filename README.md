# WindowsBasicSetup
 Windows Auto Setup Script

An automation script (`setup.cmd` + `setup.ps1` + `config.json`) for quick Windows configuration after a fresh install. Run it once — it handles everything from registry tweaks and software installation to Windows Update, rebooting and resuming automatically until the system is fully up to date.

---

## Features

- ☑️ **Selection menus** — at startup the script lists the programs and the optimizations from `config.json` in the terminal and lets you tick which ones to apply

Optimizations (all selectable from the menu, nothing is applied before you confirm):

- 📋 **Copy To / Move To** — adds the CopyTo and MoveTo entries to the right-click menu
- 📂 **File Extensions** — makes file extensions visible in Explorer
- 🖱️ **Classic Context Menu** — restores the full right-click menu on Windows 11
- 🔍 **Search** — disables Cortana and Bing integration in Windows Search
- 🛡️ **Security Health** — restores the Security Health icon in the system tray
- 🌑 **Dark Theme** — enables dark mode for apps and system UI
- 🎨 **Wallpaper & Lock Screen** — sets a custom image for both desktop and lock screen, disabling Windows Spotlight
- ⚡ **Power Plan** — disables standby, monitor timeout and disk timeout; sets boot timeout to 3 seconds
- 🏷️ **Registered Owner / Organization** — writes the owner and organization shown in `winver`. **Not ticked by default**; values come from `config.json`
- 🔒 **Disable UAC** — removes User Account Control prompts. **Not ticked by default**: it lowers the system's security
- 🔄 **Windows Update Loop** — installs all available updates, reboots if needed, and resumes automatically via Scheduled Task until no updates remain

Programs:

- 🍫 **Chocolatey** — installed automatically (only if at least one package is selected) and used to deploy the selected programs. Default catalog:
  - Google Chrome, Firefox
  - VLC, K-Lite Codec Pack Mega
  - 7-Zip, Everything, TeraCopy
  - Adobe Reader, HWiNFO, Java Runtime
  - Notepad++, RustDesk
- 📦 **Office 2024** — optional; downloads and runs the official Microsoft installer (Italian, x64 by default). A valid license is required to activate it

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
4. Pick the programs to install and press Enter, then pick the optimizations to apply and press Enter
5. Wait — the script will handle the rest, including reboots

> If Windows Update is selected, it resumes automatically after each reboot. No need to re-run anything manually.

### Using the menus

| Key | Action |
|-----|--------|
| Up / Down | Move |
| Space | Tick / untick the highlighted entry |
| `A` / `N` | Select all / none |
| Enter | Confirm |
| Esc | Select nothing in this menu |

If the console window is too small for the list, the script falls back to a numbered prompt: type the numbers to toggle, Enter to confirm, `0` to select nothing.

### config.json

`config.json` is the catalog shown in the menus:

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
  },
  "tweaks": [
    { "id": "wallpaper", "selected": true, "url": "https://example.com/my-wallpaper.jpg" },
    { "id": "disableUac", "selected": false }
  ]
}
```

- `apps[].id` — Chocolatey package name (required); `name` — label shown in the menu; `selected` — pre-ticked or not (default `true`)
- `office` — remove the whole block to drop Office from the menu
- `tweaks[].id` — one of `copyMoveTo`, `showFileExtensions`, `classicContextMenu`, `disableWebSearch`, `securityHealthTray`, `darkTheme`, `wallpaper`, `powerPlan`, `registeredOwner`, `disableUac`, `windowsUpdate`; `name` and `selected` work as for `apps`. `wallpaper` also accepts `url` (image used for desktop and lock screen); `registeredOwner` accepts `owner` and `organization`. An optimization missing from the list is not shown and not applied
- `interactive` — set to `false` to skip the menus and apply everything with `"selected": true`. Same effect as running `setup.ps1 -Unattended`

---

## File Overview

| File | Role |
|------|------|
| `setup.cmd` | Launcher — asks for administrator rights and starts `setup.ps1` |
| `setup.ps1` | Main script — selection menus, optimizations, software, Office, Windows Update loop |
| `config.json` | Catalog of programs and optimizations with their default selection |
| `Stop-WindowsUpdateLoop.ps1` | Stops the update/reboot loop and cleans up the Scheduled Task |

---

## Notes

- The Office 2024 installer is downloaded directly from Microsoft's servers (`c2rsetup.officeapps.live.com`) — no third-party source involved
- The Windows Update Scheduled Task (`SetupWindowsUpdate`) is automatically removed once all updates are installed
- The `SETUP_UPDATE_MODE` environment variable is used internally to skip the first-run block on post-reboot cycles — it is also cleaned up automatically

---

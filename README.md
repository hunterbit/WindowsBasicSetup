# WindowsBasicSetup
 Windows Auto Setup Script

An automation script (`setup.cmd` + `setup.ps1` + `config.json`) for quick Windows configuration after a fresh install. At startup it lists the programs and the optimizations in the terminal: tick what you want, confirm, and it does the rest. It never reboots the PC on its own — if a reboot is needed, it tells you at the end.

---

## Features

- ☑️ **Selection menus** — programs and optimizations come from `config.json` and are ticked in the terminal; nothing is changed before you confirm
- 🔁 **No automatic reboots** — Windows Update runs once; a pending reboot is only reported

### Optimizations

Ticked by default:

- 🛟 **Restore point** — created before any other change, so the PC can be rolled back
- 🧹 **Remove preinstalled apps** — Solitaire, Xbox app, Clipchamp, News, Candy Crush, Spotify and others; the list is in `config.json`. Apps are removed for all users and from the image, so new users don't get them back
- 🕵️ **Telemetry** — telemetry set to the minimum allowed by the edition, advertising ID and tailored experiences off
- 🚫 **Suggestions** — no suggested apps, silent app installs or ads in Start and Settings
- 📋 **Copy To / Move To** — adds the CopyTo and MoveTo entries to the right-click menu
- 📂 **File Extensions** — makes file extensions visible in Explorer
- 🖱️ **Classic Context Menu** — restores the full right-click menu on Windows 11
- 🔍 **Search** — disables Cortana and Bing integration in Windows Search
- 🛡️ **Security Health** — restores the Security Health icon in the system tray
- ⚡ **Power Plan** — on mains power: no standby, monitor or disk timeout; boot menu timeout 3 seconds. Battery settings are left alone
- 🚀 **Disable Fast Startup** — shutdown really ends the session (avoids endless uptime and half-applied updates)
- 🔄 **Windows Update** — installs all available updates in a single pass and never reboots: if a reboot is needed the script only says so. Version upgrades (e.g. Windows 10 → 11) are excluded

Available but not ticked by default:

- 🤖 **Disable Copilot and Recall**
- 📌 **Windows 11 taskbar** — aligned left, no Widgets, Task View or Chat buttons
- 🌑 **Dark Theme**
- 🎨 **Wallpaper & Lock Screen** — image URL in `config.json`
- 💤 **Disable hibernation** — removes `hiberfil.sys`
- 🖥️ **Remote Desktop** — enables RDP with Network Level Authentication and its firewall rules (skipped on Home editions)
- 🏷️ **Rename PC** — name from `config.json`, or asked in the terminal right after the menus
- 🏢 **Registered Owner / Organization** — shown in `winver`; values from `config.json`
- 🧩 **.NET Framework 3.5** — needed by some older business and medical software
- 🔒 **Disable UAC** — lowers the system's security; use only if you know why you need it

### Programs

- 🍫 **Chocolatey** — installed only if at least one package is selected, then used to deploy the selected programs. Failed packages are listed at the end
  - Ticked by default: Google Chrome, Firefox, VLC, K-Lite Codec Pack Mega, HWiNFO, 7-Zip, Everything, TeraCopy, Adobe Reader, Notepad++, RustDesk
  - Available: Java 8 JRE (Eclipse Temurin), Java 8 JRE (Oracle — Oracle's license applies to commercial use), LibreOffice, Thunderbird, SumatraPDF, Greenshot, KeePassXC, AnyDesk, MikroTik WinBox, PuTTY, WinSCP, Advanced IP Scanner, Wireshark, Sysinternals Suite, PowerShell 7, CrystalDiskInfo, TreeSize Free, PowerToys, VS Code, Git
- 📦 **Office 2024** — downloads and runs the official Microsoft installer (Italian, x64 by default). A valid license is required to activate it

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
5. If "Rename PC" is ticked and no name is set in `config.json`, type the new name
6. Wait — at the end the script tells you whether a reboot is needed

### Using the menus

| Key | Action |
|-----|--------|
| Up / Down | Move |
| Page Up / Page Down, Home / End | Scroll long lists |
| Space | Tick / untick the highlighted entry |
| `A` / `N` | Select all / none |
| Enter | Confirm |
| Esc | Select nothing in this menu |

Lists longer than the window scroll. If the window is very small (under 9 lines) or input is redirected, the script falls back to a numbered prompt: type the numbers to toggle, Enter to confirm, `0` to select nothing.

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
    { "id": "removeBloatware", "selected": true, "packages": ["Microsoft.BingNews", "king.com.*"] },
    { "id": "renameComputer", "selected": false, "computerName": "" },
    { "id": "wallpaper", "selected": false, "url": "https://example.com/my-wallpaper.jpg" },
    { "id": "disableUac", "selected": false }
  ]
}
```

- `apps[].id` — Chocolatey package name (required; search it on https://community.chocolatey.org/packages); `name` — label shown in the menu; `selected` — pre-ticked or not (default `true`)
- `office` — remove the whole block to drop Office from the menu
- `tweaks[].id` — one of `restorePoint`, `removeBloatware`, `disableTelemetry`, `disableSuggestions`, `disableCopilot`, `copyMoveTo`, `showFileExtensions`, `classicContextMenu`, `disableWebSearch`, `securityHealthTray`, `taskbarWin11`, `darkTheme`, `wallpaper`, `powerPlan`, `disableFastStartup`, `disableHibernation`, `enableRdp`, `renameComputer`, `registeredOwner`, `enableNetFx3`, `disableUac`, `windowsUpdate`. The menu shows them in the order of the file; an optimization missing from the list is not shown and not applied
- Extra fields: `removeBloatware` → `packages` (Store package names, `*` wildcards allowed); `renameComputer` → `computerName` (empty = ask in the terminal); `wallpaper` → `url`; `registeredOwner` → `owner`, `organization`
- `interactive` — set to `false` to skip the menus and apply everything with `"selected": true`. Same effect as running `setup.ps1 -Unattended`

---

## File Overview

| File | Role |
|------|------|
| `setup.cmd` | Launcher — asks for administrator rights and starts `setup.ps1` |
| `setup.ps1` | Main script — selection menus, optimizations, software, Office, Windows Update |
| `config.json` | Catalog of programs and optimizations with their default selection |
| `Stop-WindowsUpdateLoop.ps1` | Only for PCs set up with older versions of this script, which rebooted in a loop: stops the loop and removes its Scheduled Task |

---

## Notes

- The Office 2024 installer is downloaded directly from Microsoft's servers (`c2rsetup.officeapps.live.com`) — no third-party source involved
- Some optimizations apply to the user running the script (HKCU): run it from the account that will use the PC
- Older versions of this script rebooted in a loop through the `SetupWindowsUpdate` Scheduled Task and the `SETUP_UPDATE_MODE` variable; the current version removes both when it starts

---

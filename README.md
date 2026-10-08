# WindowsBasicSetup
 Windows Auto Setup Script

An automation script (`setup.cmd` + `setup.ps1` + `config.json`) for quick Windows configuration after a fresh install. At startup it lists the programs and the optimizations in the terminal: tick what you want, confirm, and it does the rest. It never reboots the PC on its own — if a reboot is needed, it tells you at the end.

---

## Features

- ☑️ **Selection menus** — programs and optimizations come from `config.json` and are ticked in the terminal; nothing is changed before you confirm
- 🔁 **No automatic reboots** — Windows Update runs once; a pending reboot is only reported
- 🔎 **Detects what is already applied** — when the script starts it checks Windows for every optimization that can be detected. Those already active are ticked and shown in green with "(gia' attiva)"; untick one and the script puts it back to the Windows default

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
  - Available: Java 8 JRE (Eclipse Temurin), Java 8 JRE (Oracle — Oracle's license applies to commercial use), LibreOffice, Thunderbird, SumatraPDF, Greenshot, KeePassXC, AnyDesk, Supremo (official portable executable, saved on the Public Desktop), MikroTik WinBox, PuTTY, WinSCP, Advanced IP Scanner, Wireshark, Sysinternals Suite, PowerShell 7, CrystalDiskInfo, TreeSize Free, PowerToys, VS Code, Git
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

### Running it again

On every start the script reads the real state of the PC:

| On the PC | You leave it… | Result |
|---|---|---|
| already active | ticked | left as it is |
| already active | **unticked** | **restored to the Windows default** |
| not active | ticked | applied |
| not active | unticked | nothing |

- On the first run on a PC, optimizations that are not active start ticked or not as set in `config.json`. At the end the script writes `HKLM\SOFTWARE\WindowsBasicSetup`; from then on non-active optimizations start unticked, so the menu shows exactly how the PC is
- Detected and restorable: Copy To/Move To, file extensions, classic context menu, Cortana/Bing, dark theme, wallpaper & lock screen, power plan, Fast Startup, hibernation, Remote Desktop, UAC, telemetry, suggestions, Copilot/Recall, Windows 11 taskbar, .NET 3.5. Restoring the power plan resets all power plans to factory settings; restoring Copilot does not reinstall the Copilot app
- Actions that have no state (restore point, removing preinstalled apps, rename, Windows Update, Security Health icon, registered owner) always start as set in `config.json`; removed apps are not reinstalled
- Programs: installed ones are not detected
- With `-Unattended` or `"interactive": false` nothing is ever restored: the script only applies

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
- Programs that are not on Chocolatey: add `url` (official `https://` download link) to the entry. The file is saved on the Public Desktop, named after the URL or after `fileName` if given; `id` is then just a unique name. Example: `{ "id": "supremo", "name": "Supremo", "selected": false, "url": "https://www.nanosystems.it/public/download/Supremo.exe" }`
- `office` — remove the whole block to drop Office from the menu
- `tweaks[].id` — one of `restorePoint`, `removeBloatware`, `disableTelemetry`, `disableSuggestions`, `disableCopilot`, `copyMoveTo`, `showFileExtensions`, `classicContextMenu`, `disableWebSearch`, `securityHealthTray`, `taskbarWin11`, `darkTheme`, `wallpaper`, `powerPlan`, `disableFastStartup`, `disableHibernation`, `enableRdp`, `renameComputer`, `registeredOwner`, `enableNetFx3`, `disableUac`, `windowsUpdate`. An optimization missing from the list is not shown and not applied
- Extra fields: `removeBloatware` → `packages` (Store package names, `*` wildcards allowed); `renameComputer` → `computerName` (empty = ask in the terminal); `wallpaper` → `url`; `registeredOwner` → `owner`, `organization`
- Menu order — in both menus the entries ticked by default come first, then the others; each group keeps the order of `config.json`
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

# WindowsBasicSetup
 Windows Auto Setup Script

An automation script (`setup.cmd` + `setup.ps1` + `config.json`) for quick Windows configuration after a fresh install. At startup it opens a window with the programs and the optimizations grouped by category: tick what you want, confirm, and it does the rest while showing progress and a log. It never reboots the PC on its own — if a reboot is needed, it tells you at the end.

---

## Features

- 🪟 **Graphical window** — two tabs (Programs, Optimizations), entries grouped by category, search box, Select all / none, progress bar and full log while the setup runs. The terminal menus are still available with `-Console`, and are used automatically if the window cannot open
- ☑️ **Nothing changes before you confirm** — programs and optimizations come from `config.json`; the window asks for confirmation and lists what will be restored
- 🔁 **No automatic reboots** — Windows Update runs once; a pending reboot is only reported
- 🔎 **Detects what is already applied** — when the script starts it checks Windows for every optimization that can be detected. Those already active are ticked and shown in green with "(gia' attiva)"; untick one and the script puts it back to the Windows default

### Optimizations

Ticked by default:

- 🛟 **Restore point** — created before any other change, so the PC can be rolled back
- 🧹 **Remove preinstalled apps** — Solitaire, Xbox app, Clipchamp, News, Candy Crush, Spotify and others; the list is in `config.json`. Apps are removed for all users and from the image, so new users don't get them back
- 🕵️ **Telemetry** — telemetry set to the minimum allowed by the edition, advertising ID and tailored experiences off
- 🚫 **Suggestions** — no suggested apps, silent app installs or ads in Start and Settings
- 📊 **Office telemetry** — Microsoft Office sends no diagnostic data (Office policies)
- 🗓️ **Telemetry scheduled tasks** — Compatibility Appraiser, CEIP and feedback tasks disabled
- 🔕 **"Let's finish setting up your device"** — no setup reminder screens after updates and no suggestion notifications
- 🌐 **Quiet Edge** — no first-run wizard, no startup boost, no background running (Edge shows "managed by your organization")
- 📋 **Copy To / Move To** — adds the CopyTo and MoveTo entries to the right-click menu
- 📂 **File Extensions** — makes file extensions visible in Explorer
- 🖱️ **Classic Context Menu** — restores the full right-click menu on Windows 11
- ⛔ **End task in the taskbar** — "End task" in the taskbar right-click menu (Windows 11 23H2 or later)
- 🔍 **Search** — disables Cortana and Bing integration in Windows Search
- 🛡️ **Security Health** — restores the Security Health icon in the system tray
- ⌨️ **Sticky Keys shortcut** — pressing Shift five times no longer turns on Sticky Keys (same for Toggle Keys and Filter Keys shortcuts)
- ⚡ **Power Plan** — on mains power: no standby, monitor or disk timeout; boot menu timeout 3 seconds. Battery settings are left alone
- 🚀 **Disable Fast Startup** — shutdown really ends the session (avoids endless uptime and half-applied updates)
- 🔄 **Windows Update** — installs all available updates in a single pass and never reboots: if a reboot is needed the script only says so. Version upgrades (e.g. Windows 10 → 11) are excluded
- 🧽 **Cleanup** — at the end, empties temporary folders and the Windows Update download cache and reports the space freed

Available but not ticked by default:

- 🤖 **Disable Copilot and Recall**
- 📍 **Disable location** — turns off location services for the whole PC (weather and maps lose your position)
- 📌 **Windows 11 taskbar** — aligned left, no Widgets, Task View or Chat buttons
- 🌑 **Dark Theme**
- 🎨 **Wallpaper & Lock Screen** — image URL in `config.json`
- 💤 **Disable hibernation** — removes `hiberfil.sys`
- 🏎️ **Ultimate Performance** — creates and activates the Ultimate Performance power plan; for desktops that must run at full speed
- 🖲️ **Mouse acceleration off** — 1:1 pointer movement (from the next sign-in)
- 🖥️ **Remote Desktop** — enables RDP with Network Level Authentication and its firewall rules (skipped on Home editions)
- 🏷️ **Rename PC** — name from `config.json`, or asked in the terminal right after the menus
- 🏢 **Registered Owner / Organization** — shown in `winver`; values from `config.json`
- 🧩 **.NET Framework 3.5** — needed by some older business and medical software
- ☁️ **Remove OneDrive** — not reversible; not recommended where Microsoft 365 is used
- 🔒 **Disable UAC** — lowers the system's security; use only if you know why you need it

### Programs

- 🍫 **Chocolatey** — installed only if at least one package is selected, then used to deploy the selected programs. Package checksums are always verified (see `ignoreChecksums` below). Failed packages are listed at the end
  - Ticked by default: Google Chrome, Firefox, VLC, K-Lite Codec Pack Mega, HWiNFO, 7-Zip, Everything, TeraCopy, Adobe Reader, Notepad++, RustDesk, Visual C++ Redistributable (all versions)
  - Available: Java 8 JRE (Eclipse Temurin), Java 8 JRE (Oracle — Oracle's license applies to commercial use), Java 21 JRE and Java 17 JRE (Eclipse Temurin), LibreOffice, Thunderbird, SumatraPDF, Greenshot, KeePassXC, AnyDesk, Supremo (official portable executable, saved on the Public Desktop), MikroTik WinBox, PuTTY, WinSCP, WireGuard, Advanced IP Scanner, Angry IP Scanner, Wireshark, Sysinternals Suite, PowerShell 7, CrystalDiskInfo, CrystalDiskMark, CPU-Z, GPU-Z, HWMonitor, OCCT, Snappy Driver Installer Origin, TreeSize Free, PowerToys, VS Code, Git
- 📦 **Office 2024** — downloads and runs the official Microsoft installer (Italian, x64 by default). A valid license is required to activate it

---

## Requirements

- Windows 10 or Windows 11 (Home and Pro supported)
- Internet connection
- Administrator privileges (the script self-elevates automatically)

---

## Usage

1. Download the whole folder (`setup.cmd`, `setup.ps1`, `config.json` and the `lib` folder) and keep the files together
2. Double-click `setup.cmd`
3. Accept the UAC prompt
4. In the window, tick the programs and the optimizations (use **Cerca** to filter, **Tutti / Nessuno** act on the visible entries). New PC name, registered owner and wallpaper URL are in **Opzioni** at the bottom of the Optimizations tab
5. Press **Avvia** and confirm
6. Wait — the window shows progress and the log; at the end it tells you which programs failed and whether a reboot is needed. It cannot be closed while the setup runs

Command-line switches for `setup.ps1`:

| Switch | Effect |
|---|---|
| (none) | Graphical window; falls back to the terminal menus if it cannot open |
| `-Console` | Terminal menus instead of the window |
| `-Unattended` | No questions: applies everything with `"selected": true`, never restores |
| `-ConfigPath <file>` | Use another catalog instead of `config.json` |

### Using the terminal menus (`-Console`)

Pick the programs and press Enter, then the optimizations and press Enter. If "Rename PC" is ticked and no name is set in `config.json`, type the new name.

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
- Detected and restorable: Copy To/Move To, file extensions, classic context menu, Cortana/Bing, dark theme, wallpaper & lock screen, power plan, Fast Startup, hibernation, Remote Desktop, UAC, telemetry, suggestions, Copilot/Recall, Windows 11 taskbar, .NET 3.5, Office telemetry, telemetry tasks, location, setup reminders, Edge, End task, Sticky Keys shortcut, mouse acceleration, Ultimate Performance. Restoring the power plan resets all power plans to factory settings; restoring Copilot does not reinstall the Copilot app
- Actions that have no state (restore point, removing preinstalled apps and OneDrive, rename, Windows Update, cleanup, Security Health icon, registered owner) always start as set in `config.json`; removed apps are not reinstalled
- Programs: installed ones are not detected
- With `-Unattended` or `"interactive": false` nothing is ever restored: the script only applies

### config.json

`config.json` is the catalog shown in the menus:

```json
{
  "interactive": true,
  "apps": [
    { "id": "googlechrome", "category": "Browser", "name": "Google Chrome", "selected": true }
  ],
  "office": {
    "name": "Microsoft Office 2024 ProPlus",
    "category": "Ufficio e PDF",
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
- `category` (apps, `office`, tweaks) — group shown in the window; entries without it go under "Altro". Categories appear in the order of their first entry in the file. The terminal menus ignore it
- `ignoreChecksums: true` — only for a Chocolatey package whose checksum is known to be out of date: installs it without verifying the downloaded file. Leave it out otherwise
- Programs that are not on Chocolatey: add `url` (official `https://` download link) to the entry. The file is saved on the Public Desktop, named after the URL or after `fileName` if given; `id` is then just a unique name. Example: `{ "id": "supremo", "name": "Supremo", "selected": false, "url": "https://www.nanosystems.it/public/download/Supremo.exe" }`
- `office` — remove the whole block to drop Office from the menu
- `tweaks[].id` — one of `restorePoint`, `removeBloatware`, `disableTelemetry`, `disableSuggestions`, `disableCopilot`, `disableOfficeTelemetry`, `disableTelemetryTasks`, `disableLocation`, `disableScoobe`, `edgeQuiet`, `taskbarEndTask`, `disableStickyKeys`, `disableMouseAccel`, `ultimatePerformance`, `cleanupTemp`, `removeOneDrive`, `copyMoveTo`, `showFileExtensions`, `classicContextMenu`, `disableWebSearch`, `securityHealthTray`, `taskbarWin11`, `darkTheme`, `wallpaper`, `powerPlan`, `disableFastStartup`, `disableHibernation`, `enableRdp`, `renameComputer`, `registeredOwner`, `enableNetFx3`, `disableUac`, `windowsUpdate`. An optimization missing from the list is not shown and not applied
- Extra fields: `removeBloatware` → `packages` (Store package names, `*` wildcards allowed); `renameComputer` → `computerName` (empty = type it in Opzioni in the window, or at the prompt in the terminal); `wallpaper` → `url`; `registeredOwner` → `owner`, `organization`
- Order — in the window entries keep the order of `config.json` inside their category; in the terminal menus the entries ticked by default come first, then the others
- `interactive` — set to `false` to skip the menus and apply everything with `"selected": true`. Same effect as running `setup.ps1 -Unattended`

---

## File Overview

| File | Role |
|------|------|
| `setup.cmd` | Launcher — asks for administrator rights and starts `setup.ps1` with its console hidden, so only the window shows (the console appears only for errors or the terminal menus) |
| `setup.ps1` | Main script — loads `lib/`, opens the window (or the terminal menus) and runs the setup |
| `lib/Engine.ps1` | Catalog, detection of active optimizations, optimizations, software, Office, Windows Update |
| `lib/Gui.ps1`, `lib/Gui.xaml` | Graphical window (WPF) |
| `lib/Console.ps1` | Selection menus in the terminal |
| `config.json` | Catalog of programs and optimizations with their default selection |
| `tests/` | Pester tests for the engine and a smoke test of the window (`tests/gui`); none of them change the system |

---

## Notes

- The Office 2024 installer is downloaded directly from Microsoft's servers (`c2rsetup.officeapps.live.com`) — no third-party source involved
- Some optimizations apply to the user running the script (HKCU): run it from the account that will use the PC
- Older versions of this script rebooted in a loop through the `SetupWindowsUpdate` Scheduled Task and the `SETUP_UPDATE_MODE` variable; the current version removes both when it starts

---

## Credits

- Based on [momo1098r/WindowsBasicSetup](https://github.com/momo1098r/WindowsBasicSetup)
- Some optimizations (Office telemetry, telemetry tasks, setup reminders, Edge, End task, Sticky Keys, mouse acceleration, Ultimate Performance, OneDrive removal, cleanup) were inspired by [GTweak](https://github.com/Greedeks/GTweak) (BSD-3-Clause); the PowerShell code here is written from scratch

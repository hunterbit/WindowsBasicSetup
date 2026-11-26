# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Post-install Windows 10/11 setup tool: `setup.cmd` (elevating launcher) → `setup.ps1` (all logic) driven by `config.json` (catalog of programs and optimizations). User-facing strings and code comments are in Italian; README is in English. Targets **Windows PowerShell 5.1** (no PS7-only syntax: no `??`, `?.`, ternary, `&&`). Git remote `origin` = github.com/hunterbit/WindowsBasicSetup (public fork of momo1098r/WindowsBasicSetup), branch `main`. No build, no test suite.

## Commands

- Run (elevates itself): `setup.cmd`, or `powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 [-Unattended] [-ConfigPath <file>]`
- Running it **changes the real system** (registry, apps, power plans, Windows Update). Don't run it to "test" a change unless the user asks.
- Syntax check without executing:
  ```powershell
  $e=$null; [System.Management.Automation.Language.Parser]::ParseFile("$PWD\setup.ps1",[ref]$null,[ref]$e); $e
  ```
- Validate config: `Get-Content config.json -Raw | ConvertFrom-Json | Out-Null`

## Architecture of setup.ps1

Top-down script, roughly in this order:

1. **Bootstrap** — self-elevation (re-launch with same args), cleanup of legacy `SetupWindowsUpdate` scheduled task / `SETUP_UPDATE_MODE` env var, TLS 1.2.
2. **Catalog** — `$KnownTweaks` (ordered id → default Italian label) is the whitelist; `Get-SetupCatalog` parses `config.json` into uniform items `{Kind (choco|download|office|tweak), Id, Label, Selected, Active, Order, Options}`. Unknown tweak ids throw. Per-tweak extra fields (`packages`, `url`, `computerName`, `owner`/`organization`) go into `Options`.
3. **State detection** — `$TweakState` hashtable: for each *reversible* tweak a `Test` scriptblock (is it active on this PC?) and a `Revert` scriptblock (restore Windows default). `Update-TweakState` sets `Active`/`Selected`; marker key `HKLM:\SOFTWARE\WindowsBasicSetup` (`$SetupMarkerKey`, written at the end) means "already configured" → non-active tweaks start unticked.
4. **Menus** — `Select-SetupItems` (interactive arrow-key menu, numbered fallback via `Read-AppSelection` when window < 9 lines or input redirected). `Select-SelectedFirst` orders ticked items first, then by `Order`.
5. **Plan** — `Get-TweakPlan` → `Apply` (selected & not active), `Keep` (selected & active), `Revert` (unselected & active; only when menus were shown — `-Unattended`/`"interactive": false` never reverts).
6. **Execution** — restore point first, then reverts, then one `if ($tweakIds -contains "<id>") { ... }` block per tweak, Chocolatey/download/Office installs, Windows Update (PSWindowsUpdate, `-IgnoreReboot`, no Upgrades), cleanup last.

Conventions:
- **Never reboot.** Set `$rebootNeeded = $true` and it is reported at the end. Explorer restarts once at the end via `$restartExplorer`.
- Each step catches its own errors and prints a yellow warning; the script keeps going.
- Registry writes go through `Set-RegValue` / `Get-RegValue` / `Remove-RegValue` helpers.

## Adding a new optimization (all places must be touched)

1. `$KnownTweaks` in `setup.ps1` (id + Italian label).
2. Execution block `if ($tweakIds -contains "<id>")` in the SETUP section.
3. If it has detectable state: `Test` + `Revert` entry in `$TweakState`. Actions without state (like restorePoint, removeBloatware) are left out.
4. Extra config fields → parse into `Options` in `Get-SetupCatalog`.
5. Entry in `config.json` `tweaks` (missing from config = not shown, not applied).
6. README: Optimizations list, the "Detected and restorable" list if reversible, and the `tweaks[].id` list.

Programs: Chocolatey package id in `config.json` `apps`; non-Chocolatey programs use `url` (must be `https://`) and are saved to the Public Desktop.

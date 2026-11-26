# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Post-install Windows 10/11 setup tool: `setup.cmd` (elevating launcher) → `setup.ps1` (console front-end) → `lib/Engine.ps1` (all logic), driven by `config.json` (catalog of programs and optimizations). User-facing strings and code comments are in Italian; README is in English. Targets **Windows PowerShell 5.1** (no PS7-only syntax: no `??`, `?.`, ternary, `&&`). Git remote `origin` = github.com/hunterbit/WindowsBasicSetup (public fork of momo1098r/WindowsBasicSetup), branch `main`.

A WPF GUI is being built in phases: see [docs/PIANO-GUI.md](docs/PIANO-GUI.md). Phase 1 (engine split + tests) is done.

## Commands

- Run (elevates itself): `setup.cmd`, or `powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 [-Unattended] [-ConfigPath <file>]`
- Running it **changes the real system** (registry, apps, power plans, Windows Update). Don't run it to "test" a change unless the user asks; real runs belong in a Windows VM.
- Tests (Pester 3.4, bundled with Windows; run under Windows PowerShell, not pwsh): `powershell -NoProfile -Command "Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester .\tests"`. Single test: add `-TestName "Get-TweakPlan"` (Describe name). Use Pester 3 syntax (`Should Be`, not `Should -Be`).
- Syntax check without executing:
  ```powershell
  foreach ($f in "setup.ps1","lib\Engine.ps1","lib\Console.ps1") { $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile("$PWD\$f",[ref]$null,[ref]$e); "$f $($e.Count)" }
  ```
- Validate config: `Get-Content config.json -Raw | ConvertFrom-Json | Out-Null`

## Architecture

- **`setup.ps1`** — self-elevation, cleanup of legacy `SetupWindowsUpdate` task / `SETUP_UPDATE_MODE` var, TLS 1.2, dot-sources `lib/`, then: catalog → state detection → menus → plan → `Invoke-SetupPlan` → final banner.
- **`lib/Engine.ps1`** — definitions only (dot-sourcing it changes nothing on the system):
  - **Catalog** — `$KnownTweaks` (ordered id → default Italian label) is the whitelist; `Get-SetupCatalog` parses `config.json` into items `{Kind (choco|download|office|tweak), Id, Label, Selected, Active, Order, Options}`. Unknown tweak ids throw. Extra fields (`packages`, `url`, `computerName`, `owner`/`organization`) go into `Options`.
  - **State** — `$TweakState`: for each *reversible* tweak `Test` (active on this PC?) and `Revert` (restore Windows default). `Update-TweakState` sets `Active`/`Selected`; marker key `HKLM:\SOFTWARE\WindowsBasicSetup` (`$SetupMarkerKey`, written by `Invoke-SetupPlan`) means "already configured" → non-active tweaks start unticked.
  - **Plan** — `Get-TweakPlan` → `Apply` (selected & not active), `Keep` (selected & active), `Revert` (unselected & active; only when menus were shown — `-Unattended`/`"interactive": false` never reverts).
  - **Execution** — `$TweakActions` (ordered id → `{ param($Item) ... }`, order = execution order). `Invoke-SetupPlan -Plan -Items` runs: restorePoint → reverts → other actions → Explorer restart → Chocolatey → vendor downloads → Office → `$LateTweaks` (.NET 3.5, Windows Update, cleanup) → marker. Returns `{RebootNeeded, FailedApps}`.
  - **Logging** — all output goes through `Write-SetupLog <Info|Ok|Warn|Error|Detail> <msg>`; it prints coloured to the console unless `$SetupLogHandler` (scriptblock `param($Level,$Message)`) is set — that is the hook for the GUI.
- **`lib/Console.ps1`** — terminal UI: `Select-SetupItems` (arrow-key menu, numbered fallback via `Read-AppSelection` when window < 9 lines or input redirected), `Get-NewComputerName` (asks the PC name). `Select-SelectedFirst` (engine) orders ticked items first, then by `Order`.

Conventions:
- **Never reboot.** Actions and `Revert` blocks set `$Run.RebootNeeded = $true` / `$Run.RestartExplorer = $true`; `$Run` is a local of `Invoke-SetupPlan` reached through PowerShell's dynamic scoping, so they only work when called from it.
- Each action catches its own errors (and `Invoke-TweakAction` catches the rest) with a `Warn`; the setup keeps going.
- In the engine use `Write-SetupLog`, never `Write-Host`. Registry writes go through `Set-RegValue` / `Get-RegValue` / `Remove-RegValue`.

## Adding a new optimization (all places must be touched)

1. `$KnownTweaks` in `lib/Engine.ps1` (id + Italian label).
2. Action in `$TweakActions`, at the position where it must run (add the id to `$LateTweaks` if it must run after the programs).
3. If it has detectable state: `Test` + `Revert` entry in `$TweakState`. Actions without state (like restorePoint, removeBloatware) are left out.
4. Extra config fields → parse into `Options` in `Get-SetupCatalog`.
5. Entry in `config.json` `tweaks` (missing from config = not shown, not applied).
6. README: Optimizations list, the "Detected and restorable" list if reversible, and the `tweaks[].id` list.

The test "ogni ottimizzazione ha un'azione e viceversa" fails if steps 1 and 2 don't match.

Programs: Chocolatey package id in `config.json` `apps`; non-Chocolatey programs use `url` (must be `https://`) and are saved to the Public Desktop.

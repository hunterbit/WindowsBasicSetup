# ============================================================
#  SETUP AUTOMATICO - setup.ps1
# ============================================================

#  -Unattended  : salta il menu e installa i programmi con "selected": true
#  -ConfigPath  : percorso del catalogo programmi (default: config.json accanto allo script)
param(
    [switch]$Unattended,
    [string]$ConfigPath
)

if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot "config.json" }

# Auto-elevazione admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`""
    if ($Unattended) { $elevArgs += " -Unattended" }
    Start-Process powershell -ArgumentList $elevArgs -Verb RunAs
    Exit
}

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force

# Legge il flag passato dal Scheduled Task per sapere se siamo in modalita post-riavvio
$UpdateMode = [System.Environment]::GetEnvironmentVariable("SETUP_UPDATE_MODE", "Machine")

# ============================================================
#  SELEZIONE PROGRAMMI - catalogo in config.json, scelta a terminale
# ============================================================

# Legge config.json e restituisce il flag "interactive" e l'elenco delle voci selezionabili
function Get-SetupCatalog {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "File di configurazione non trovato: $Path" }
    try {
        $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "File di configurazione non valido ($Path): $($_.Exception.Message)"
    }

    $items = @()
    if ($config.apps) {
        foreach ($app in @($config.apps)) {
            if (-not $app.id) { throw "config.json: ogni voce di 'apps' deve avere un 'id' (nome del pacchetto Chocolatey)." }
            $name = $app.id
            if ($app.name) { $name = $app.name }
            $selected = $true
            if ($null -ne $app.selected) { $selected = [bool]$app.selected }
            $items += [pscustomobject]@{ Kind = "choco"; Id = [string]$app.id; Label = [string]$name; Selected = $selected; Office = $null }
        }
    }

    if ($config.office) {
        $office = [pscustomobject]@{ ProductId = "ProPlus2024Retail"; Language = "it-it"; Platform = "x64" }
        if ($config.office.productId) { $office.ProductId = [string]$config.office.productId }
        if ($config.office.language)  { $office.Language  = [string]$config.office.language }
        if ($config.office.platform)  { $office.Platform  = [string]$config.office.platform }
        $name = "Microsoft Office"
        if ($config.office.name) { $name = $config.office.name }
        $selected = $true
        if ($null -ne $config.office.selected) { $selected = [bool]$config.office.selected }
        $label = "{0} ({1}, {2})" -f $name, $office.Language, $office.Platform
        $items += [pscustomobject]@{ Kind = "office"; Id = $office.ProductId; Label = $label; Selected = $selected; Office = $office }
    }

    $interactive = $true
    if ($null -ne $config.interactive) { $interactive = [bool]$config.interactive }

    return [pscustomobject]@{ Interactive = $interactive; Items = $items }
}

# Scrive una riga occupando tutta la larghezza, cosi' il ridisegno del menu non lascia residui
function Write-MenuLine {
    param([string]$Text, [int]$Width, [ConsoleColor]$Color = [ConsoleColor]::Gray)

    if ($Text.Length -gt $Width) { $Text = $Text.Substring(0, $Width) }
    Write-Host $Text.PadRight($Width) -ForegroundColor $Color
}

# Menu a caselle: frecce per spostarsi, spazio per selezionare. Modifica .Selected delle voci.
function Show-AppMenu {
    param([object[]]$Items)

    $pos   = 0
    $width = [Math]::Max(20, [Console]::WindowWidth - 1)
    Clear-Host
    $top = [Console]::CursorTop
    try { [Console]::CursorVisible = $false } catch {}

    try {
        while ($true) {
            [Console]::SetCursorPosition(0, $top)
            Write-MenuLine " Seleziona i programmi da installare" $width Cyan
            Write-MenuLine "" $width
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $mark = " "
                if ($Items[$i].Selected) { $mark = "x" }
                $pointer = " "
                $color   = [ConsoleColor]::Gray
                if ($i -eq $pos) { $pointer = ">"; $color = [ConsoleColor]::Yellow }
                Write-MenuLine (" {0} [{1}] {2}" -f $pointer, $mark, $Items[$i].Label) $width $color
            }
            Write-MenuLine "" $width
            Write-MenuLine " Su/Giu: sposta   Spazio: seleziona   A: tutti   N: nessuno" $width DarkGray
            Write-MenuLine " Invio: conferma   Esc: non installare nulla" $width DarkGray

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow"   { if ($pos -gt 0) { $pos-- } else { $pos = $Items.Count - 1 } }
                "DownArrow" { if ($pos -lt $Items.Count - 1) { $pos++ } else { $pos = 0 } }
                "Spacebar"  { $Items[$pos].Selected = -not $Items[$pos].Selected }
                "A"         { foreach ($item in $Items) { $item.Selected = $true } }
                "N"         { foreach ($item in $Items) { $item.Selected = $false } }
                "Enter"     { return }
                "Escape"    { foreach ($item in $Items) { $item.Selected = $false }; return }
            }
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch {}
        Clear-Host
    }
}

# Ripiego senza tasti freccia (finestra troppo piccola o input rediretto): si digitano i numeri
function Read-AppSelection {
    param([object[]]$Items)

    while ($true) {
        Write-Host ""
        Write-Host " Programmi da installare:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = " "
            if ($Items[$i].Selected) { $mark = "x" }
            Write-Host ("  {0,2}) [{1}] {2}" -f ($i + 1), $mark, $Items[$i].Label)
        }
        try {
            $answer = Read-Host " Numeri da invertire (es. 1,3 5) - INVIO conferma - 0 non installa nulla"
        } catch {
            return
        }
        if ($null -eq $answer) { return }
        $answer = $answer.Trim()
        if ($answer -eq "") { return }
        if ($answer -eq "0") {
            foreach ($item in $Items) { $item.Selected = $false }
            return
        }
        foreach ($token in ($answer -split "[,;\s]+")) {
            $n = 0
            if ([int]::TryParse($token, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) {
                $Items[$n - 1].Selected = -not $Items[$n - 1].Selected
            }
        }
    }
}

# Sceglie il tipo di menu adatto alla console
function Select-SetupItems {
    param([object[]]$Items)

    $useKeys = $false
    try {
        $useKeys = (-not [Console]::IsInputRedirected) -and ([Console]::WindowHeight -ge ($Items.Count + 6))
    } catch {}

    if ($useKeys) { Show-AppMenu -Items $Items } else { Read-AppSelection -Items $Items }
}

# Installa i pacchetti Chocolatey e restituisce l'elenco di quelli falliti
function Install-ChocoApps {
    param([object[]]$Apps)

    $failed = @()
    foreach ($app in $Apps) {
        Write-Host "Installazione $($app.Label)..." -ForegroundColor Cyan
        choco install $app.Id --ignore-checksums -y | Out-Host
        # 1641 e 3010 = installato, riavvio richiesto
        if (@(0, 1641, 3010) -notcontains $LASTEXITCODE) { $failed += $app }
    }
    return $failed
}

# ============================================================
#  BLOCCO PRIMO AVVIO - salta se siamo in post-riavvio update
# ============================================================
if ($UpdateMode -ne "1") {

    # ---- SCELTA PROGRAMMI (prima di tutto, cosi' il resto prosegue da solo) ----
    try {
        $catalog = Get-SetupCatalog -Path $ConfigPath
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Read-Host "Premi INVIO per chiudere"
        exit 1
    }
    $setupItems = @($catalog.Items)
    if ($setupItems.Count -gt 0 -and $catalog.Interactive -and -not $Unattended) {
        Select-SetupItems -Items $setupItems
    }
    $chocoApps  = @($setupItems | Where-Object { $_.Kind -eq "choco"  -and $_.Selected })
    $officeItem = $setupItems | Where-Object { $_.Kind -eq "office" -and $_.Selected } | Select-Object -First 1

    $chosen = @($setupItems | Where-Object { $_.Selected })
    if ($chosen.Count -gt 0) {
        Write-Host "Programmi da installare:" -ForegroundColor Cyan
        foreach ($item in $chosen) { Write-Host "  - $($item.Label)" }
    } else {
        Write-Host "Nessun programma da installare." -ForegroundColor Yellow
    }
    Write-Host ""

    # ---- WALLPAPER ----
    Write-Host "Impostazione sfondo..." -ForegroundColor Cyan
    $wpUrl  = "https://r4.wallpaperflare.com/wallpaper/58/631/685/windows-11-microsoft-hd-wallpaper-323833af44ece00a7ca43c56beaf0f2b.jpg"
    $wpPath = Join-Path $env:APPDATA "wallpaper.jpg"
    Invoke-WebRequest -Uri $wpUrl -OutFile $wpPath -UseBasicParsing

    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll")]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    [Wallpaper]::SystemParametersInfo(20, 0, $wpPath, 3) | Out-Null
    Write-Host "Sfondo impostato." -ForegroundColor Green

    # ---- LOCKSCREEN ----
    Write-Host "Impostazione lockscreen..." -ForegroundColor Cyan

    # Disabilita Spotlight
    $regSpotlight = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    New-ItemProperty -Path $regSpotlight -Name RotatingLockScreenEnabled        -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $regSpotlight -Name RotatingLockScreenOverlayEnabled -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $regSpotlight -Name SubscribedContent-338387Enabled  -Value 0 -PropertyType DWORD -Force | Out-Null

    # Percorso lockscreen accessibile anche da admin
    $lockDest = "C:\Windows\Web\Screen\lockscreen.jpg"
    Copy-Item -Path $wpPath -Destination $lockDest -Force

    # PersonalizationCSP: funziona su Home e Pro
    $cspPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
    if (-not (Test-Path $cspPath)) { New-Item -Path $cspPath -Force | Out-Null }
    New-ItemProperty -Path $cspPath -Name LockScreenImagePath   -Value $lockDest -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $cspPath -Name LockScreenImageUrl    -Value $lockDest -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $cspPath -Name LockScreenImageStatus -Value 1         -PropertyType DWORD  -Force | Out-Null
    Write-Host "Lockscreen impostata." -ForegroundColor Green

    # ---- MENU CONTESTUALE CLASSICO (Windows 11) ----
    Write-Host "Ripristino menu contestuale classico..." -ForegroundColor Cyan
    reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve
    taskkill /f /im explorer.exe
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Write-Host "Menu contestuale classico attivato." -ForegroundColor Green

    # ---- UAC ----
    Write-Host "Disabilitazione UAC..." -ForegroundColor Cyan
    $uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    New-ItemProperty -Path $uacPath -Name ConsentPromptBehaviorAdmin    -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $uacPath -Name ConsentPromptBehaviorUser     -Value 3 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $uacPath -Name EnableInstallerDetection      -Value 1 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $uacPath -Name EnableLUA                     -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $uacPath -Name EnableVirtualization          -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $uacPath -Name PromptOnSecureDesktop         -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $uacPath -Name ValidateAdminCodeSignatures   -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $uacPath -Name FilterAdministratorToken      -Value 0 -PropertyType DWORD -Force | Out-Null
    Write-Host "UAC disabilitato." -ForegroundColor Green

    # ---- TEMA SCURO ----
    Write-Host "Attivazione tema scuro..." -ForegroundColor Cyan
    $themePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    New-ItemProperty -Path $themePath -Name AppsUseLightTheme    -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $themePath -Name SystemUsesLightTheme -Value 0 -PropertyType DWORD -Force | Out-Null
    Write-Host "Tema scuro attivato." -ForegroundColor Green

    # ---- POWER / BOOT ----
    Write-Host "Configurazione power plan e boot..." -ForegroundColor Cyan
    powercfg -change -standby-timeout-ac 0
    powercfg -change -standby-timeout-dc 0
    powercfg -change -monitor-timeout-ac 0
    powercfg -change -monitor-timeout-dc 0
    powercfg -change -disk-timeout-ac 0
    powercfg -change -disk-timeout-dc 0
    bcdedit /timeout 3
    $numProcs = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors
    bcdedit /set '{current}' numproc $numProcs
    Write-Host "Power plan e boot configurati." -ForegroundColor Green

    if ($chocoApps.Count -gt 0) {
        # ---- CHOCOLATEY ----
        Write-Host "Installazione Chocolatey..." -ForegroundColor Cyan
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        Write-Host "Attesa completamento Chocolatey..." -ForegroundColor Cyan
        Start-Sleep -Seconds 20

        # ---- PROGRAMMI ----
        Write-Host "Installazione programmi..." -ForegroundColor Cyan
        $failedApps = @(Install-ChocoApps -Apps $chocoApps)
        if ($failedApps.Count -eq 0) {
            Write-Host "Programmi installati." -ForegroundColor Green
        } else {
            Write-Host "Programmi NON installati (errore Chocolatey):" -ForegroundColor Red
            foreach ($app in $failedApps) { Write-Host "  - $($app.Label) [$($app.Id)]" -ForegroundColor Red }
        }
    } else {
        Write-Host "Nessun pacchetto Chocolatey selezionato: Chocolatey non viene installato." -ForegroundColor Yellow
    }

    # ---- OFFICE ----
    if ($officeItem) {
        Write-Host "Download $($officeItem.Label)..." -ForegroundColor Cyan
        $office     = $officeItem.Office
        $officeUrl  = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=$($office.ProductId)&platform=$($office.Platform)&language=$($office.Language)&version=O16GA"
        $officeDest = Join-Path ([Environment]::GetFolderPath("Desktop")) "SetupOffice.exe"
        Invoke-WebRequest -Uri $officeUrl -OutFile $officeDest
        Write-Host "Avvio installazione Office..." -ForegroundColor Cyan
        Start-Process -FilePath $officeDest -Wait
        Remove-Item -Path $officeDest -Force
        Write-Host "Office installato." -ForegroundColor Green
    }

} # fine blocco primo avvio

# ============================================================
#  WINDOWS UPDATE CICLICO (gira sia al primo avvio che dopo riavvii)
# ============================================================
Write-Host "Preparazione modulo aggiornamenti..." -ForegroundColor Cyan
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue) -or `
    (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue).Version -lt "2.8.5.201") {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
}
Import-Module PSWindowsUpdate

while ($true) {
    Write-Host "Ricerca aggiornamenti Windows..." -ForegroundColor Cyan
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose
    $pending = Get-WindowsUpdate -MicrosoftUpdate | Where-Object { $_.Title -ne "" }

    if ($pending.Count -eq 0) {
        Write-Host "Tutti gli aggiornamenti installati!" -ForegroundColor Green
        # Pulizia: rimuovi task e variabile d'ambiente
        Unregister-ScheduledTask -TaskName "SetupWindowsUpdate" -Confirm:$false -ErrorAction SilentlyContinue
        [System.Environment]::SetEnvironmentVariable("SETUP_UPDATE_MODE", $null, "Machine")
        break
    }

    # Imposta flag persistente via variabile d'ambiente di sistema
    [System.Environment]::SetEnvironmentVariable("SETUP_UPDATE_MODE", "1", "Machine")

    # Registra Scheduled Task che riparte dopo il login post-riavvio
    $scriptPath = $PSCommandPath
    $action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                 -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger   = New-ScheduledTaskTrigger -AtLogOn
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "SetupWindowsUpdate" -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal -Force | Out-Null

    Write-Host "Riavvio necessario. Il PC si riavvia in 10 secondi..." -ForegroundColor Yellow
    shutdown /r /t 10
    exit
}

# ============================================================
Write-Host ""
Write-Host "==============================" -ForegroundColor Green
Write-Host " SETUP COMPLETATO!"            -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green
Read-Host "Premi INVIO per chiudere"

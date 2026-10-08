# ============================================================
#  SETUP AUTOMATICO - setup.ps1
# ============================================================

#  -Unattended  : salta i menu e usa le voci con "selected": true
#  -ConfigPath  : percorso del catalogo programmi/ottimizzazioni (default: config.json accanto allo script)
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

# Le versioni precedenti installavano gli aggiornamenti con un ciclo di riavvii automatici
# (attivita' pianificata "SetupWindowsUpdate" + variabile SETUP_UPDATE_MODE): eventuali residui vengono rimossi.
Unregister-ScheduledTask -TaskName "SetupWindowsUpdate" -Confirm:$false -ErrorAction SilentlyContinue
if ([System.Environment]::GetEnvironmentVariable("SETUP_UPDATE_MODE", "Machine")) {
    [System.Environment]::SetEnvironmentVariable("SETUP_UPDATE_MODE", $null, "Machine")
}
# Avviato da quella vecchia attivita' pianificata (account SYSTEM, senza utente davanti): solo pulizia
if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { exit }

# Diventa $true se una modifica richiede il riavvio: viene solo segnalato, mai eseguito
$rebootNeeded = $false

# ============================================================
#  SELEZIONE PROGRAMMI E OTTIMIZZAZIONI - catalogo in config.json, scelta a terminale
# ============================================================

# Ottimizzazioni gestite dallo script (id usati in config.json -> "tweaks")
$KnownTweaks = [ordered]@{
    restorePoint       = "Punto di ripristino prima delle modifiche"
    removeBloatware    = "Rimuovi app preinstallate inutili (elenco in config.json)"
    disableTelemetry   = "Riduci telemetria e disattiva ID pubblicitario"
    disableSuggestions = "Disattiva app suggerite e pubblicita' in Start"
    disableFastStartup = "Disattiva Avvio rapido"
    disableCopilot     = "Disattiva Copilot e Recall"
    taskbarWin11       = "Barra applicazioni Windows 11 a sinistra, senza widget"
    disableHibernation = "Disattiva ibernazione"
    enableRdp          = "Abilita Desktop remoto (solo Pro/Enterprise)"
    renameComputer     = "Rinomina il PC"
    enableNetFx3       = "Abilita .NET Framework 3.5"
    copyMoveTo         = "Voci 'Copia in' e 'Sposta in' nel menu contestuale"
    showFileExtensions = "Mostra le estensioni dei file"
    classicContextMenu = "Menu contestuale classico (Windows 11)"
    disableWebSearch   = "Disattiva Cortana e Bing nella ricerca"
    securityHealthTray = "Icona Sicurezza di Windows nella systray"
    darkTheme          = "Tema scuro"
    wallpaper          = "Sfondo e schermata di blocco"
    powerPlan          = "Power plan: niente standby/spegnimento schermo, boot 3 s"
    registeredOwner    = "Proprietario e organizzazione registrati"
    disableUac         = "Disattiva UAC (sconsigliato)"
    windowsUpdate      = "Windows Update (installa senza riavviare il PC)"
}
$DefaultWallpaperUrl = "https://r4.wallpaperflare.com/wallpaper/58/631/685/windows-11-microsoft-hd-wallpaper-323833af44ece00a7ca43c56beaf0f2b.jpg"

# Legge config.json e restituisce il flag "interactive", i programmi e le ottimizzazioni selezionabili
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
            $items += [pscustomobject]@{ Kind = "choco"; Id = [string]$app.id; Label = [string]$name; Selected = $selected; Options = $null }
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
        $items += [pscustomobject]@{ Kind = "office"; Id = $office.ProductId; Label = $label; Selected = $selected; Options = $office }
    }

    $tweaks = @()
    if ($config.tweaks) {
        foreach ($tweak in @($config.tweaks)) {
            $id = [string]$tweak.id
            $known = @($KnownTweaks.Keys | Where-Object { $_ -eq $id })
            if ($known.Count -eq 0) {
                throw "config.json: ottimizzazione '$id' sconosciuta. Valori ammessi: $($KnownTweaks.Keys -join ', ')"
            }
            $id = $known[0]
            $name = $KnownTweaks[$id]
            if ($tweak.name) { $name = $tweak.name }
            $selected = $true
            if ($null -ne $tweak.selected) { $selected = [bool]$tweak.selected }
            $options = $null
            if ($id -eq "wallpaper") {
                $url = $DefaultWallpaperUrl
                if ($tweak.url) { $url = [string]$tweak.url }
                $options = [pscustomobject]@{ Url = $url }
            }
            if ($id -eq "registeredOwner") {
                $options = [pscustomobject]@{ Owner = ""; Organization = "" }
                if ($null -ne $tweak.owner)        { $options.Owner        = [string]$tweak.owner }
                if ($null -ne $tweak.organization) { $options.Organization = [string]$tweak.organization }
            }
            if ($id -eq "removeBloatware") {
                $packages = @()
                if ($tweak.packages) { $packages = @($tweak.packages | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
                $options = [pscustomobject]@{ Packages = $packages }
            }
            if ($id -eq "renameComputer") {
                $newName = ""
                if ($tweak.computerName) { $newName = ([string]$tweak.computerName).Trim() }
                $options = [pscustomobject]@{ ComputerName = $newName }
            }
            $tweaks += [pscustomobject]@{ Kind = "tweak"; Id = $id; Label = [string]$name; Selected = $selected; Options = $options }
        }
    }

    $interactive = $true
    if ($null -ne $config.interactive) { $interactive = [bool]$config.interactive }

    # Nei menu le voci spuntate di default vengono prima, poi le altre; ogni gruppo mantiene
    # l'ordine di config.json (Where-Object conserva l'ordine, Sort-Object in PS 5.1 no)
    $items  = @($items  | Where-Object { $_.Selected }) + @($items  | Where-Object { -not $_.Selected })
    $tweaks = @($tweaks | Where-Object { $_.Selected }) + @($tweaks | Where-Object { -not $_.Selected })

    return [pscustomobject]@{ Interactive = $interactive; Items = $items; Tweaks = $tweaks }
}

# Nome PC valido: 1-15 caratteri tra lettere, cifre e trattino, non solo cifre
function Test-ComputerName {
    param([string]$Name)
    return ($Name -match '^[A-Za-z0-9-]{1,15}$') -and ($Name -notmatch '^[0-9]+$')
}

# Restituisce il nuovo nome del PC: quello di config.json o, se vuoto e $Ask, chiesto a terminale.
# Stringa vuota = non rinominare.
function Get-NewComputerName {
    param([string]$Configured, [switch]$Ask)

    if ($Configured) {
        if (Test-ComputerName $Configured) { return $Configured }
        Write-Host "Nome PC '$Configured' in config.json non valido." -ForegroundColor Yellow
    }
    if (-not $Ask) { return "" }
    while ($true) {
        try {
            $answer = Read-Host "Nuovo nome del PC (attuale: $env:COMPUTERNAME) - INVIO per non rinominare"
        } catch {
            return ""
        }
        if ($null -eq $answer) { return "" }
        $answer = $answer.Trim()
        if ($answer -eq "") { return "" }
        if (Test-ComputerName $answer) { return $answer }
        Write-Host "Nome non valido: massimo 15 caratteri tra lettere, cifre e trattino, non solo cifre." -ForegroundColor Yellow
    }
}

# Scrive un valore di registro creando la chiave se manca
# Se Windows nega la scrittura (alcune chiavi sono protette anche per l'amministratore)
# mostra un avviso, con il suggerimento $Hint se presente, e lo script prosegue.
function Set-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord",
        [string]$Hint = ""
    )
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  Impostazione non applicata ($Path\$Name): $($_.Exception.Message)" -ForegroundColor Yellow
        if ($Hint) { Write-Host "  $Hint" -ForegroundColor Yellow }
    }
}

# Rimuove un'app Store per tutti gli utenti e dall'immagine (non torna con i nuovi utenti).
# $Pattern accetta i caratteri jolly (es. king.com.*). Restituisce i nomi dei pacchetti rimossi.
function Remove-AppxByName {
    param([string]$Pattern)

    $removed = @()
    foreach ($pkg in @(Get-AppxPackage -AllUsers -Name $Pattern -ErrorAction SilentlyContinue)) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            $removed += $pkg.Name
        } catch {
            Write-Host "  Impossibile rimuovere $($pkg.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    foreach ($prov in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Pattern })) {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
        if ($removed -notcontains $prov.DisplayName) { $removed += $prov.DisplayName }
    }
    return $removed
}

# Scrive una riga occupando tutta la larghezza, cosi' il ridisegno del menu non lascia residui
function Write-MenuLine {
    param([string]$Text, [int]$Width, [ConsoleColor]$Color = [ConsoleColor]::Gray)

    if ($Text.Length -gt $Width) { $Text = $Text.Substring(0, $Width) }
    Write-Host $Text.PadRight($Width) -ForegroundColor $Color
}

# Menu a caselle: frecce per spostarsi, spazio per selezionare. Modifica .Selected delle voci.
function Show-AppMenu {
    param(
        [object[]]$Items,
        [string]$Title = "Seleziona i programmi da installare",
        [string]$NoneLabel = "non installare nulla"
    )

    $pos    = 0
    $offset = 0
    $width  = [Math]::Max(20, [Console]::WindowWidth - 1)
    # Righe disponibili per le voci: titolo, riga di stato, riga vuota, 2 righe di aiuto e 1 di margine
    $visible = [Math]::Max(3, [Math]::Min($Items.Count, [Console]::WindowHeight - 6))
    Clear-Host
    $top = [Console]::CursorTop
    try { [Console]::CursorVisible = $false } catch {}

    try {
        while ($true) {
            # Scorre la finestra visibile in modo che la voce corrente sia sempre a schermo
            if ($pos -lt $offset) { $offset = $pos }
            if ($pos -ge $offset + $visible) { $offset = $pos - $visible + 1 }

            [Console]::SetCursorPosition(0, $top)
            Write-MenuLine " $Title" $width Cyan
            $status = ""
            if ($Items.Count -gt $visible) {
                $status = "   (voci {0}-{1} di {2}, PagSu/PagGiu per scorrere)" -f ($offset + 1), ($offset + $visible), $Items.Count
            }
            Write-MenuLine $status $width DarkGray
            for ($i = $offset; $i -lt $offset + $visible; $i++) {
                $mark = " "
                if ($Items[$i].Selected) { $mark = "x" }
                $pointer = " "
                $color   = [ConsoleColor]::Gray
                if ($i -eq $pos) { $pointer = ">"; $color = [ConsoleColor]::Yellow }
                Write-MenuLine (" {0} [{1}] {2}" -f $pointer, $mark, $Items[$i].Label) $width $color
            }
            Write-MenuLine "" $width
            Write-MenuLine " Su/Giu: sposta   Spazio: seleziona   A: tutti   N: nessuno" $width DarkGray
            Write-MenuLine " Invio: conferma   Esc: $NoneLabel" $width DarkGray

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow"   { if ($pos -gt 0) { $pos-- } else { $pos = $Items.Count - 1 } }
                "DownArrow" { if ($pos -lt $Items.Count - 1) { $pos++ } else { $pos = 0 } }
                "PageUp"    { $pos = [Math]::Max(0, $pos - $visible) }
                "PageDown"  { $pos = [Math]::Min($Items.Count - 1, $pos + $visible) }
                "Home"      { $pos = 0 }
                "End"       { $pos = $Items.Count - 1 }
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
    param(
        [object[]]$Items,
        [string]$Title = "Seleziona i programmi da installare",
        [string]$NoneLabel = "non installare nulla"
    )

    while ($true) {
        Write-Host ""
        Write-Host " $($Title):" -ForegroundColor Cyan
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = " "
            if ($Items[$i].Selected) { $mark = "x" }
            Write-Host ("  {0,2}) [{1}] {2}" -f ($i + 1), $mark, $Items[$i].Label)
        }
        try {
            $answer = Read-Host " Numeri da invertire (es. 1,3 5) - INVIO conferma - 0 $NoneLabel"
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
    param(
        [object[]]$Items,
        [string]$Title = "Seleziona i programmi da installare",
        [string]$NoneLabel = "non installare nulla"
    )

    $useKeys = $false
    try {
        # Il menu a frecce scorre: basta una finestra con almeno 3 righe per le voci
        $useKeys = (-not [Console]::IsInputRedirected) -and ([Console]::WindowHeight -ge 9)
    } catch {}

    if ($useKeys) {
        Show-AppMenu -Items $Items -Title $Title -NoneLabel $NoneLabel
    } else {
        Read-AppSelection -Items $Items -Title $Title -NoneLabel $NoneLabel
    }
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
#  SETUP
# ============================================================

# ---- SCELTA PROGRAMMI E OTTIMIZZAZIONI (prima di tutto, cosi' il resto prosegue da solo) ----
try {
    $catalog = Get-SetupCatalog -Path $ConfigPath
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host "Premi INVIO per chiudere"
    exit 1
}
$setupItems  = @($catalog.Items)
$setupTweaks = @($catalog.Tweaks)
if ($catalog.Interactive -and -not $Unattended) {
    if ($setupItems.Count -gt 0) {
        Select-SetupItems -Items $setupItems
    }
    if ($setupTweaks.Count -gt 0) {
        Select-SetupItems -Items $setupTweaks -Title "Seleziona le ottimizzazioni da applicare" -NoneLabel "nessuna ottimizzazione"
    }
}
$chocoApps  = @($setupItems | Where-Object { $_.Kind -eq "choco"  -and $_.Selected })
$officeItem = $setupItems | Where-Object { $_.Kind -eq "office" -and $_.Selected } | Select-Object -First 1
$tweakIds   = @($setupTweaks | Where-Object { $_.Selected } | ForEach-Object { $_.Id })

# Nome del PC chiesto subito, cosi' il resto del setup prosegue senza altre domande
$newComputerName = ""
if ($tweakIds -contains "renameComputer") {
    $renameOptions = ($setupTweaks | Where-Object { $_.Id -eq "renameComputer" } | Select-Object -First 1).Options
    $newComputerName = Get-NewComputerName -Configured $renameOptions.ComputerName -Ask:($catalog.Interactive -and -not $Unattended)
    if (-not $newComputerName) { Write-Host "Il PC non verra' rinominato." -ForegroundColor Yellow }
}

$chosen = @($setupItems | Where-Object { $_.Selected })
if ($chosen.Count -gt 0) {
    Write-Host "Programmi da installare:" -ForegroundColor Cyan
    foreach ($item in $chosen) { Write-Host "  - $($item.Label)" }
} else {
    Write-Host "Nessun programma da installare." -ForegroundColor Yellow
}
$chosen = @($setupTweaks | Where-Object { $_.Selected })
if ($chosen.Count -gt 0) {
    Write-Host "Ottimizzazioni da applicare:" -ForegroundColor Cyan
    foreach ($item in $chosen) { Write-Host "  - $($item.Label)" }
} else {
    Write-Host "Nessuna ottimizzazione da applicare." -ForegroundColor Yellow
}
Write-Host ""

# Esplora risorse viene riavviato una sola volta, alla fine, se una modifica lo richiede
$restartExplorer = $false

if ($tweakIds -contains "restorePoint") {
    # ---- PUNTO DI RIPRISTINO (prima di qualsiasi modifica) ----
    Write-Host "Creazione punto di ripristino..." -ForegroundColor Cyan
    $srKey     = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $srOldFreq = (Get-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        # Windows crea al massimo un punto ogni 24 ore: il limite viene tolto solo per questa creazione
        Set-RegValue -Path $srKey -Name SystemRestorePointCreationFrequency -Value 0
        Checkpoint-Computer -Description "WindowsBasicSetup - prima delle modifiche" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Host "Punto di ripristino creato." -ForegroundColor Green
    } catch {
        Write-Host "Punto di ripristino NON creato: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        if ($null -eq $srOldFreq) {
            Remove-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
        } else {
            Set-RegValue -Path $srKey -Name SystemRestorePointCreationFrequency -Value $srOldFreq
        }
    }
}

if ($newComputerName) {
    # ---- RINOMINA PC (effettivo al prossimo riavvio) ----
    Write-Host "Rinomina del PC in '$newComputerName'..." -ForegroundColor Cyan
    try {
        Rename-Computer -NewName $newComputerName -Force -ErrorAction Stop -WarningAction SilentlyContinue
        Write-Host "PC rinominato in '$newComputerName' (attivo dopo il riavvio)." -ForegroundColor Green
        $rebootNeeded = $true
    } catch {
        Write-Host "Rinomina non riuscita: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($tweakIds -contains "removeBloatware") {
    # ---- RIMOZIONE APP PREINSTALLATE ----
    Write-Host "Rimozione app preinstallate..." -ForegroundColor Cyan
    $bloat   = ($setupTweaks | Where-Object { $_.Id -eq "removeBloatware" } | Select-Object -First 1).Options.Packages
    $removed = @()
    foreach ($pattern in $bloat) { $removed += @(Remove-AppxByName -Pattern $pattern) }
    if ($removed.Count -gt 0) {
        Write-Host "App rimosse: $(($removed | Sort-Object -Unique) -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "Nessuna delle app in elenco era presente." -ForegroundColor Green
    }
}

if ($tweakIds -contains "disableTelemetry") {
    # ---- TELEMETRIA / ID PUBBLICITARIO ----
    Write-Host "Riduzione telemetria..." -ForegroundColor Cyan
    # 0 = solo dati di sicurezza su Enterprise/Education; Home e Pro lo applicano come "dati obbligatori"
    Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name AllowTelemetry -Value 0
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name Enabled -Value 0
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name TailoredExperiencesWithDiagnosticDataEnabled -Value 0
    Write-Host "Telemetria ridotta e ID pubblicitario disattivato." -ForegroundColor Green
}

if ($tweakIds -contains "disableSuggestions") {
    # ---- APP SUGGERITE / PUBBLICITA' ----
    Write-Host "Disattivazione app suggerite e suggerimenti..." -ForegroundColor Cyan
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($name in @("SilentInstalledAppsEnabled", "SystemPaneSuggestionsEnabled", "SoftLandingEnabled",
                        "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled",
                        "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")) {
        Set-RegValue -Path $cdm -Name $name -Value 0
    }
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Start_IrisRecommendations -Value 0
    Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name DisableWindowsConsumerFeatures -Value 1
    Write-Host "App suggerite e suggerimenti disattivati." -ForegroundColor Green
}

if ($tweakIds -contains "disableCopilot") {
    # ---- COPILOT / RECALL ----
    Write-Host "Disattivazione Copilot e Recall..." -ForegroundColor Cyan
    Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name TurnOffWindowsCopilot -Value 1
    Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name TurnOffWindowsCopilot -Value 1
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowCopilotButton -Value 0
    Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name DisableAIDataAnalysis -Value 1
    Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name AllowRecallEnablement -Value 0
    # Sulle build recenti Copilot e' un'app dello Store
    $null = Remove-AppxByName -Pattern "Microsoft.Copilot"
    $restartExplorer = $true
    Write-Host "Copilot e Recall disattivati." -ForegroundColor Green
}

if ($tweakIds -contains "copyMoveTo") {
    # ---- COPIA IN / SPOSTA IN ----
    Write-Host "Aggiunta di 'Copia in' e 'Sposta in' al menu contestuale..." -ForegroundColor Cyan
    reg add "HKCR\AllFilesystemObjects\shellex\ContextMenuHandlers\CopyTo" /ve /d "{C2FBB630-2971-11D1-A18C-00C04FD75D13}" /f | Out-Null
    reg add "HKCR\AllFilesystemObjects\shellex\ContextMenuHandlers\MoveTo" /ve /d "{C2FBB631-2971-11D1-A18C-00C04FD75D13}" /f | Out-Null
    Write-Host "'Copia in' e 'Sposta in' aggiunti." -ForegroundColor Green
}

if ($tweakIds -contains "showFileExtensions") {
    # ---- ESTENSIONI FILE ----
    Write-Host "Attivazione estensioni dei file..." -ForegroundColor Cyan
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f | Out-Null
    $restartExplorer = $true
    Write-Host "Estensioni dei file visibili." -ForegroundColor Green
}

if ($tweakIds -contains "disableWebSearch") {
    # ---- CORTANA / BING ----
    Write-Host "Disattivazione Cortana e Bing nella ricerca..." -ForegroundColor Cyan
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v CortanaConsent /t REG_DWORD /d 0 /f | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f | Out-Null
    Write-Host "Cortana e Bing disattivati nella ricerca." -ForegroundColor Green
}

if ($tweakIds -contains "securityHealthTray") {
    # ---- SICUREZZA DI WINDOWS NELLA SYSTRAY ----
    Write-Host "Ripristino icona Sicurezza di Windows nella systray..." -ForegroundColor Cyan
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" /v HideSystray /t REG_DWORD /d 0 /f | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" /v SecurityHealth /t REG_BINARY /d 060000000000000000000000 /f | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v SecurityHealth /t REG_EXPAND_SZ /d "%windir%\system32\SecurityHealthSystray.exe" /f | Out-Null
    Write-Host "Icona Sicurezza di Windows ripristinata." -ForegroundColor Green
}

if ($tweakIds -contains "registeredOwner") {
    # ---- PROPRIETARIO / ORGANIZZAZIONE REGISTRATI ----
    Write-Host "Impostazione proprietario e organizzazione registrati..." -ForegroundColor Cyan
    $regInfo = ($setupTweaks | Where-Object { $_.Id -eq "registeredOwner" } | Select-Object -First 1).Options
    # Set-ItemProperty e non reg.exe: PowerShell 5.1 scarta gli argomenti vuoti passati agli eseguibili
    $ntPath  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    New-ItemProperty -Path $ntPath -Name RegisteredOwner        -Value $regInfo.Owner        -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $ntPath -Name RegisteredOrganization -Value $regInfo.Organization -PropertyType String -Force | Out-Null
    Write-Host "Proprietario e organizzazione impostati." -ForegroundColor Green
}

if ($tweakIds -contains "wallpaper") {
    # ---- WALLPAPER ----
    Write-Host "Impostazione sfondo..." -ForegroundColor Cyan
    $wpUrl  = ($setupTweaks | Where-Object { $_.Id -eq "wallpaper" } | Select-Object -First 1).Options.Url
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
}

if ($tweakIds -contains "classicContextMenu") {
    # ---- MENU CONTESTUALE CLASSICO (Windows 11) ----
    Write-Host "Ripristino menu contestuale classico..." -ForegroundColor Cyan
    reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve | Out-Null
    $restartExplorer = $true
    Write-Host "Menu contestuale classico attivato." -ForegroundColor Green
}

if ($tweakIds -contains "disableUac") {
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
}

if ($tweakIds -contains "darkTheme") {
    # ---- TEMA SCURO ----
    Write-Host "Attivazione tema scuro..." -ForegroundColor Cyan
    $themePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    New-ItemProperty -Path $themePath -Name AppsUseLightTheme    -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $themePath -Name SystemUsesLightTheme -Value 0 -PropertyType DWORD -Force | Out-Null
    Write-Host "Tema scuro attivato." -ForegroundColor Green
}

if ($tweakIds -contains "powerPlan") {
    # ---- POWER / BOOT ----
    Write-Host "Configurazione power plan e boot..." -ForegroundColor Cyan
    # Solo con alimentazione da rete: a batteria restano i valori di Windows, per non scaricare i portatili
    powercfg -change -standby-timeout-ac 0
    powercfg -change -monitor-timeout-ac 0
    powercfg -change -disk-timeout-ac 0
    bcdedit /timeout 3 | Out-Null
    Write-Host "Power plan e boot configurati." -ForegroundColor Green
}

if ($tweakIds -contains "taskbarWin11") {
    # ---- BARRA APPLICAZIONI WINDOWS 11 ----
    Write-Host "Configurazione barra applicazioni..." -ForegroundColor Cyan
    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-RegValue -Path $adv -Name TaskbarAl -Value 0            # allineata a sinistra
    Set-RegValue -Path $adv -Name ShowTaskViewButton -Value 0   # niente Visualizzazione attivita'
    Set-RegValue -Path $adv -Name TaskbarMn -Value 0            # niente Chat
    # Niente Widget: sulle build recenti di Windows 11 questa chiave e' protetta e la scrittura viene negata
    Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name AllowNewsAndInterests -Value 0 `
        -Hint "Windows protegge l'impostazione dei Widget su questa build: disattivali da Impostazioni > Personalizzazione > Barra delle applicazioni."
    $restartExplorer = $true
    Write-Host "Barra applicazioni configurata." -ForegroundColor Green
}

if ($tweakIds -contains "disableFastStartup") {
    # ---- AVVIO RAPIDO ----
    Write-Host "Disattivazione Avvio rapido..." -ForegroundColor Cyan
    Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -Value 0
    Write-Host "Avvio rapido disattivato: lo spegnimento ora chiude davvero la sessione." -ForegroundColor Green
}

if ($tweakIds -contains "disableHibernation") {
    # ---- IBERNAZIONE ----
    Write-Host "Disattivazione ibernazione..." -ForegroundColor Cyan
    powercfg /hibernate off
    Write-Host "Ibernazione disattivata (hiberfil.sys rimosso)." -ForegroundColor Green
}

if ($tweakIds -contains "enableRdp") {
    # ---- DESKTOP REMOTO ----
    $edition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).EditionID
    if ($edition -like "Core*") {
        Write-Host "Desktop remoto non disponibile su Windows Home ($edition): saltato." -ForegroundColor Yellow
    } else {
        Write-Host "Abilitazione Desktop remoto..." -ForegroundColor Cyan
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0
        # Autenticazione a livello di rete (NLA) obbligatoria
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1
        # Gruppo di regole "Desktop remoto" indicato per id: funziona con Windows in qualsiasi lingua
        Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28752" -ErrorAction SilentlyContinue
        Write-Host "Desktop remoto abilitato (con NLA) e regole firewall attivate." -ForegroundColor Green
    }
}

if ($restartExplorer) {
    Write-Host "Riavvio di Esplora risorse per applicare le modifiche..." -ForegroundColor Cyan
    taskkill /f /im explorer.exe | Out-Null
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
}

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
    $office     = $officeItem.Options
    $officeUrl  = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=$($office.ProductId)&platform=$($office.Platform)&language=$($office.Language)&version=O16GA"
    $officeDest = Join-Path ([Environment]::GetFolderPath("Desktop")) "SetupOffice.exe"
    Invoke-WebRequest -Uri $officeUrl -OutFile $officeDest
    Write-Host "Avvio installazione Office..." -ForegroundColor Cyan
    Start-Process -FilePath $officeDest -Wait
    Remove-Item -Path $officeDest -Force
    Write-Host "Office installato." -ForegroundColor Green
}

if ($tweakIds -contains "enableNetFx3") {
    # ---- .NET FRAMEWORK 3.5 (scaricato da Windows Update) ----
    Write-Host "Abilitazione .NET Framework 3.5 (puo' richiedere alcuni minuti)..." -ForegroundColor Cyan
    try {
        $nfx = Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction Stop
        if ($nfx.RestartNeeded) { $rebootNeeded = $true }
        Write-Host ".NET Framework 3.5 abilitato." -ForegroundColor Green
    } catch {
        Write-Host ".NET Framework 3.5 NON abilitato: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}


# ============================================================
#  WINDOWS UPDATE - un solo passaggio, nessun riavvio automatico
# ============================================================
if ($tweakIds -contains "windowsUpdate") {
    Write-Host "Preparazione modulo aggiornamenti..." -ForegroundColor Cyan
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue) -or `
        (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue).Version -lt "2.8.5.201") {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Install-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
    }
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Write-Host "Ricerca e installazione aggiornamenti Windows..." -ForegroundColor Cyan
        # -IgnoreReboot: non riavvia mai, il riavvio resta a cura dell'utente.
        # -NotCategory Upgrades: esclude i passaggi di versione (es. Windows 10 -> 11).
        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -NotCategory "Upgrades" -Verbose
        if (Get-WURebootStatus -Silent) { $rebootNeeded = $true }
        Write-Host "Aggiornamenti installati. Alcuni compaiono solo dopo il riavvio: in quel caso rilancia Windows Update." -ForegroundColor Green
    } catch {
        Write-Host "Windows Update non eseguito: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================
Write-Host ""
Write-Host "==============================" -ForegroundColor Green
Write-Host " SETUP COMPLETATO!"            -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green
if ($rebootNeeded) {
    Write-Host ""
    Write-Host "Riavvia il PC quando possibile per completare le modifiche." -ForegroundColor Yellow
}
Read-Host "Premi INVIO per chiudere"

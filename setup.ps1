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

# Windows PowerShell 5.1 non sempre usa TLS 1.2 per i download (sfondo, Office, programmi dal sito del produttore)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

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
    disableOfficeTelemetry = "Disattiva telemetria di Microsoft Office"
    disableTelemetryTasks  = "Disattiva attivita' pianificate di telemetria (CEIP, Compatibility Appraiser)"
    disableLocation    = "Disattiva posizione e geolocalizzazione"
    disableScoobe      = "Disattiva 'Completa la configurazione' e suggerimenti nelle notifiche"
    edgeQuiet          = "Edge senza invadenze (prima esecuzione, avvio rapido, background)"
    taskbarEndTask     = "'Termina attivita' nel tasto destro della barra (Windows 11)"
    disableStickyKeys  = "Disattiva la scorciatoia Tasti permanenti (5 volte Maiusc)"
    disableMouseAccel  = "Disattiva accelerazione del mouse"
    ultimatePerformance = "Piano energetico Prestazioni eccellenti"
    cleanupTemp        = "Pulizia file temporanei e cache di Windows Update (a fine setup)"
    removeOneDrive     = "Rimuovi OneDrive (non reversibile)"
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

    $order = 0
    $items = @()
    if ($config.apps) {
        foreach ($app in @($config.apps)) {
            if (-not $app.id) { throw "config.json: ogni voce di 'apps' deve avere un 'id' (nome del pacchetto Chocolatey)." }
            $name = $app.id
            if ($app.name) { $name = $app.name }
            $selected = $true
            if ($null -ne $app.selected) { $selected = [bool]$app.selected }
            if ($app.url) {
                # Programma non presente su Chocolatey: scaricato dal sito del produttore sul Desktop pubblico
                $url = [string]$app.url
                if ($url -notmatch '^https://') { throw "config.json: l'url di '$($app.id)' deve iniziare con https://" }
                $fileName = [System.IO.Path]::GetFileName(([uri]$url).AbsolutePath)
                if ($app.fileName) { $fileName = [string]$app.fileName }
                if (-not $fileName) { throw "config.json: per '$($app.id)' indica 'fileName' (nome del file da salvare)." }
                $options = [pscustomobject]@{ Url = $url; FileName = $fileName }
                $items += [pscustomobject]@{ Kind = "download"; Id = [string]$app.id; Label = [string]$name; Selected = $selected; Active = $null; Order = $order++; Options = $options }
            } else {
                $items += [pscustomobject]@{ Kind = "choco"; Id = [string]$app.id; Label = [string]$name; Selected = $selected; Active = $null; Order = $order++; Options = $null }
            }
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
        $items += [pscustomobject]@{ Kind = "office"; Id = $office.ProductId; Label = $label; Selected = $selected; Active = $null; Order = $order++; Options = $office }
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
            $tweaks += [pscustomobject]@{ Kind = "tweak"; Id = $id; Label = [string]$name; Selected = $selected; Active = $null; Order = $order++; Options = $options }
        }
    }

    $interactive = $true
    if ($null -ne $config.interactive) { $interactive = [bool]$config.interactive }

    # Nei menu le voci spuntate vengono prima, poi le altre; ogni gruppo nell'ordine di config.json
    $items  = Select-SelectedFirst -Items $items
    $tweaks = Select-SelectedFirst -Items $tweaks

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

# ============================================================
#  STATO DELLE OTTIMIZZAZIONI: rilevamento e ripristino ai valori di Windows
# ============================================================

# Legge un valore di registro; $null se la chiave o il valore non esistono
function Get-RegValue {
    param([string]$Path, [string]$Name)
    try {
        return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        return $null
    }
}

# Cancella un valore di registro (nessun errore se non esiste)
function Remove-RegValue {
    param([string]$Path, [string]$Name)
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
}

# Imposta l'immagine del desktop
function Set-DesktopWallpaper {
    param([string]$ImagePath)
    if (-not ("Wallpaper" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll")]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    }
    [Wallpaper]::SystemParametersInfo(20, 0, $ImagePath, 3) | Out-Null
}

$RegAdvanced = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$RegCdm      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
$RegUac      = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$LockScreenFile = "C:\Windows\Web\Screen\lockscreen.jpg"
$SetupMarkerKey = "HKLM:\SOFTWARE\WindowsBasicSetup"
$RegOffice      = "HKCU:\Software\Policies\Microsoft\office"
$RegEdgePolicy  = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

# Attivita' pianificate che raccolgono e inviano dati di utilizzo (percorso, nome)
$TelemetryTasks = @(
    @("\Microsoft\Windows\Application Experience\", "Microsoft Compatibility Appraiser"),
    @("\Microsoft\Windows\Application Experience\", "ProgramDataUpdater"),
    @("\Microsoft\Windows\Customer Experience Improvement Program\", "Consolidator"),
    @("\Microsoft\Windows\Customer Experience Improvement Program\", "UsbCeip"),
    @("\Microsoft\Windows\Autochk\", "Proxy"),
    @("\Microsoft\Windows\DiskDiagnostic\", "Microsoft-Windows-DiskDiagnosticDataCollector"),
    @("\Microsoft\Windows\Feedback\Siuf\", "DmClient"),
    @("\Microsoft\Windows\Feedback\Siuf\", "DmClientOnScenarioDownload")
)

# Le attivita' dell'elenco presenti su questo PC (variano tra versioni di Windows)
function Get-TelemetryTasks {
    foreach ($t in $TelemetryTasks) {
        Get-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue
    }
}

# Per ogni ottimizzazione reversibile: Test = e' gia' attiva sul sistema? Revert = torna al valore di Windows.
# Le voci che sono azioni (punto di ripristino, rimozione app e OneDrive, rinomina, Windows Update, pulizia,
# icona Sicurezza, proprietario registrato) non hanno uno stato da rilevare ne' da annullare e non compaiono qui.
$TweakState = @{
    copyMoveTo = @{
        Test   = { Test-Path -LiteralPath "Registry::HKEY_CLASSES_ROOT\AllFilesystemObjects\shellex\ContextMenuHandlers\CopyTo" }
        Revert = {
            foreach ($k in @("CopyTo", "MoveTo")) {
                Remove-Item -LiteralPath "Registry::HKEY_CLASSES_ROOT\AllFilesystemObjects\shellex\ContextMenuHandlers\$k" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    showFileExtensions = @{
        Test   = { (Get-RegValue $RegAdvanced "HideFileExt") -eq 0 }
        Revert = { Set-RegValue -Path $RegAdvanced -Name HideFileExt -Value 1; $script:restartExplorer = $true }
    }
    classicContextMenu = @{
        Test   = { Test-Path -LiteralPath "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" }
        Revert = {
            Remove-Item -LiteralPath "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
            $script:restartExplorer = $true
        }
    }
    disableWebSearch = @{
        Test   = { (Get-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled") -eq 0 }
        Revert = {
            Remove-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled"
            Remove-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent"
        }
    }
    darkTheme = @{
        Test   = {
            $p = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            ((Get-RegValue $p "AppsUseLightTheme") -eq 0) -and ((Get-RegValue $p "SystemUsesLightTheme") -eq 0)
        }
        Revert = {
            $p = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            Set-RegValue -Path $p -Name AppsUseLightTheme -Value 1
            Set-RegValue -Path $p -Name SystemUsesLightTheme -Value 1
        }
    }
    wallpaper = @{
        # Riconosciuto dalla schermata di blocco impostata da questo script
        Test   = { (Get-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" "LockScreenImagePath") -eq $LockScreenFile }
        Revert = {
            $csp = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
            foreach ($n in @("LockScreenImagePath", "LockScreenImageUrl", "LockScreenImageStatus")) { Remove-RegValue $csp $n }
            foreach ($n in @("RotatingLockScreenEnabled", "RotatingLockScreenOverlayEnabled", "SubscribedContent-338387Enabled")) {
                Set-RegValue -Path $RegCdm -Name $n -Value 1
            }
            $default = "$env:windir\Web\Wallpaper\Windows\img0.jpg"
            if (Test-Path -LiteralPath $default) { Set-DesktopWallpaper $default }
        }
    }
    powerPlan = @{
        # Timeout con alimentazione da rete (standby e schermo) del piano attivo
        Test   = {
            $schemes = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes"
            $active  = Get-RegValue $schemes "ActivePowerScheme"
            if (-not $active) { return $false }
            $standby = Get-RegValue "$schemes\$active\238c9fa8-0aad-41ed-83f4-97be242c8f20\29f6c1db-86da-48c5-9fdb-f2b67b1f44da" "ACSettingIndex"
            $monitor = Get-RegValue "$schemes\$active\7516b95f-f776-4464-8c53-06167f40cc99\3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" "ACSettingIndex"
            ($standby -eq 0) -and ($monitor -eq 0)
        }
        # Riporta tutte le combinazioni di risparmio energia ai valori di fabbrica
        Revert = { powercfg -restoredefaultschemes; bcdedit /timeout 30 | Out-Null }
    }
    disableFastStartup = @{
        Test   = { (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled") -eq 0 }
        Revert = { Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -Value 1 }
    }
    disableHibernation = @{
        Test   = { (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled") -eq 0 }
        Revert = { powercfg /hibernate on }
    }
    enableRdp = @{
        Test   = { (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections") -eq 0 }
        Revert = {
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 1
            Disable-NetFirewallRule -Group "@FirewallAPI.dll,-28752" -ErrorAction SilentlyContinue
        }
    }
    disableUac = @{
        Test   = { (Get-RegValue $RegUac "EnableLUA") -eq 0 }
        Revert = {
            # Valori predefiniti di Windows
            $defaults = [ordered]@{ EnableLUA = 1; ConsentPromptBehaviorAdmin = 5; ConsentPromptBehaviorUser = 3; PromptOnSecureDesktop = 1
                                    EnableInstallerDetection = 1; EnableVirtualization = 1; ValidateAdminCodeSignatures = 0; FilterAdministratorToken = 0 }
            foreach ($n in $defaults.Keys) { Set-RegValue -Path $RegUac -Name $n -Value $defaults[$n] }
            $script:rebootNeeded = $true
        }
    }
    disableTelemetry = @{
        Test   = { (Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry") -eq 0 }
        Revert = {
            Remove-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry"
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name Enabled -Value 1
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name TailoredExperiencesWithDiagnosticDataEnabled -Value 1
        }
    }
    disableSuggestions = @{
        Test   = { ((Get-RegValue $RegCdm "SilentInstalledAppsEnabled") -eq 0) -and ((Get-RegValue $RegCdm "SystemPaneSuggestionsEnabled") -eq 0) }
        Revert = {
            foreach ($n in @("SilentInstalledAppsEnabled", "SystemPaneSuggestionsEnabled", "SoftLandingEnabled",
                             "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled",
                             "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")) {
                Set-RegValue -Path $RegCdm -Name $n -Value 1
            }
            Remove-RegValue $RegAdvanced "Start_IrisRecommendations"
            Remove-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures"
        }
    }
    disableCopilot = @{
        Test   = { (Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot") -eq 1 }
        Revert = {
            Remove-RegValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot"
            Remove-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot"
            Remove-RegValue $RegAdvanced "ShowCopilotButton"
            Remove-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis"
            Remove-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "AllowRecallEnablement"
            $script:restartExplorer = $true
        }
    }
    taskbarWin11 = @{
        Test   = { (Get-RegValue $RegAdvanced "TaskbarAl") -eq 0 }
        Revert = {
            foreach ($n in @("TaskbarAl", "ShowTaskViewButton", "TaskbarMn")) { Remove-RegValue $RegAdvanced $n }
            Remove-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests"
            $script:restartExplorer = $true
        }
    }
    disableOfficeTelemetry = @{
        Test   = { (Get-RegValue "$RegOffice\common\clienttelemetry" "sendtelemetry") -eq 3 }
        Revert = {
            Remove-RegValue "$RegOffice\common\clienttelemetry" "sendtelemetry"
            Remove-RegValue "$RegOffice\16.0\common\clienttelemetry" "DisableTelemetry"
            Remove-RegValue "$RegOffice\16.0\common\clienttelemetry" "SendTelemetry"
            Remove-RegValue "$RegOffice\16.0\osm" "Enablelogging"
            Remove-RegValue "$RegOffice\16.0\osm" "EnableUpload"
        }
    }
    disableTelemetryTasks = @{
        Test   = {
            $tasks = @(Get-TelemetryTasks)
            ($tasks.Count -gt 0) -and (@($tasks | Where-Object { $_.State -ne "Disabled" }).Count -eq 0)
        }
        Revert = { Get-TelemetryTasks | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null }
    }
    disableLocation = @{
        Test   = { (Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation") -eq 1 }
        Revert = {
            Remove-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation"
            Set-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name Value -Value "Allow" -Type String
        }
    }
    disableScoobe = @{
        Test   = { (Get-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled") -eq 0 }
        Revert = {
            Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name ScoobeSystemSettingEnabled -Value 1
            Set-RegValue -Path $RegCdm -Name "SubscribedContent-310093Enabled" -Value 1
            Remove-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested" "Enabled"
        }
    }
    edgeQuiet = @{
        Test   = { (Get-RegValue $RegEdgePolicy "HideFirstRunExperience") -eq 1 }
        Revert = { foreach ($n in @("HideFirstRunExperience", "StartupBoostEnabled", "BackgroundModeEnabled")) { Remove-RegValue $RegEdgePolicy $n } }
    }
    taskbarEndTask = @{
        Test   = { (Get-RegValue "$RegAdvanced\TaskbarDeveloperSettings" "TaskbarEndTask") -eq 1 }
        Revert = { Remove-RegValue "$RegAdvanced\TaskbarDeveloperSettings" "TaskbarEndTask"; $script:restartExplorer = $true }
    }
    disableStickyKeys = @{
        Test   = { (Get-RegValue "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags") -eq "506" }
        Revert = {
            # Valori predefiniti di Windows (scorciatoie attive)
            Set-RegValue -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name Flags -Value "510" -Type String
            Set-RegValue -Path "HKCU:\Control Panel\Accessibility\ToggleKeys" -Name Flags -Value "62" -Type String
            Set-RegValue -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name Flags -Value "126" -Type String
        }
    }
    disableMouseAccel = @{
        Test   = { (Get-RegValue "HKCU:\Control Panel\Mouse" "MouseSpeed") -eq "0" }
        Revert = {
            Set-RegValue -Path "HKCU:\Control Panel\Mouse" -Name MouseSpeed -Value "1" -Type String
            Set-RegValue -Path "HKCU:\Control Panel\Mouse" -Name MouseThreshold1 -Value "6" -Type String
            Set-RegValue -Path "HKCU:\Control Panel\Mouse" -Name MouseThreshold2 -Value "10" -Type String
        }
    }
    ultimatePerformance = @{
        # Il piano creato dallo script e' attivo?
        Test   = {
            $guid = Get-RegValue $SetupMarkerKey "UltimatePlanGuid"
            $active = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes" "ActivePowerScheme"
            [bool]$guid -and ($guid -eq $active)
        }
        Revert = {
            $guid = Get-RegValue $SetupMarkerKey "UltimatePlanGuid"
            powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e   # Bilanciato
            if ($guid) { powercfg /delete $guid }
            Remove-RegValue $SetupMarkerKey "UltimatePlanGuid"
        }
    }
    enableNetFx3 = @{
        Test   = { (Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop).State -eq "Enabled" }
        Revert = {
            $r = Disable-WindowsOptionalFeature -Online -FeatureName NetFx3 -NoRestart -ErrorAction Stop
            if ($r.RestartNeeded) { $script:rebootNeeded = $true }
        }
    }
}

# Rileva lo stato reale di ogni ottimizzazione reversibile e decide la spunta iniziale:
#  - gia' attiva sul sistema           -> spuntata (e segnalata nel menu)
#  - non attiva, PC gia' configurato   -> non spuntata (conta lo stato reale)
#  - non attiva, primo avvio sul PC    -> default di config.json
# Le azioni (senza Test) restano sempre al default di config.json.
function Update-TweakState {
    param([object[]]$Tweaks, [hashtable]$StateTable, [bool]$AlreadyConfigured)

    foreach ($tw in $Tweaks) {
        if (-not $StateTable.ContainsKey($tw.Id)) { continue }
        $active = $null
        try { $active = [bool](& $StateTable[$tw.Id].Test) } catch { $active = $null }
        $tw.Active = $active
        if ($active -eq $true) {
            $tw.Selected = $true
        } elseif ($AlreadyConfigured -and $active -eq $false) {
            $tw.Selected = $false
        }
    }
}

# Dopo i menu: cosa applicare, cosa lasciare com'e' e cosa riportare ai valori di Windows.
# Senza menu (-Unattended / interactive false) non si ripristina mai nulla.
function Get-TweakPlan {
    param([object[]]$Tweaks, [bool]$MenuShown)

    $apply  = @($Tweaks | Where-Object { $_.Selected -and $_.Active -ne $true })
    $keep   = @($Tweaks | Where-Object { $_.Selected -and $_.Active -eq $true })
    $revert = @()
    if ($MenuShown) { $revert = @($Tweaks | Where-Object { -not $_.Selected -and $_.Active -eq $true }) }
    return [pscustomobject]@{ Apply = $apply; Keep = $keep; Revert = $revert }
}

# Riordina: voci spuntate prima, poi le altre; dentro ogni gruppo vale la posizione in config.json (Order)
function Select-SelectedFirst {
    param([object[]]$Items)
    $on  = @($Items | Where-Object { $_.Selected }       | Sort-Object -Property Order)
    $off = @($Items | Where-Object { -not $_.Selected }  | Sort-Object -Property Order)
    return @($on + $off)
}

# Etichetta mostrata nei menu: le ottimizzazioni gia' presenti sul sistema sono segnalate
function Get-MenuLabel {
    param($Item)
    if ($Item.Active -eq $true) { return "$($Item.Label)  (gia' attiva)" }
    return $Item.Label
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
                if ($Items[$i].Active -eq $true) { $color = [ConsoleColor]::Green }
                if ($i -eq $pos) { $pointer = ">"; $color = [ConsoleColor]::Yellow }
                Write-MenuLine (" {0} [{1}] {2}" -f $pointer, $mark, (Get-MenuLabel $Items[$i])) $width $color
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
            $color = [ConsoleColor]::Gray
            if ($Items[$i].Active -eq $true) { $color = [ConsoleColor]::Green }
            Write-Host ("  {0,2}) [{1}] {2}" -f ($i + 1), $mark, (Get-MenuLabel $Items[$i])) -ForegroundColor $color
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

# Stato reale delle ottimizzazioni: quelle gia' attive vengono spuntate e segnalate nel menu.
# Il segno in HKLM:\SOFTWARE\WindowsBasicSetup indica che lo script e' gia' stato eseguito su questo PC.
$alreadyConfigured = Test-Path -LiteralPath $SetupMarkerKey
Write-Host "Verifica delle impostazioni gia' attive sul sistema..." -ForegroundColor Cyan
Update-TweakState -Tweaks $setupTweaks -StateTable $TweakState -AlreadyConfigured $alreadyConfigured
$setupTweaks = Select-SelectedFirst -Items $setupTweaks

$menuShown = [bool]($catalog.Interactive -and -not $Unattended)
if ($menuShown) {
    if ($setupItems.Count -gt 0) {
        Select-SetupItems -Items $setupItems
    }
    if ($setupTweaks.Count -gt 0) {
        Select-SetupItems -Items $setupTweaks -Title "Seleziona le ottimizzazioni da applicare" -NoneLabel "nessuna ottimizzazione"
    }
}
$chocoApps  = @($setupItems | Where-Object { $_.Kind -eq "choco"  -and $_.Selected })
$officeItem = $setupItems | Where-Object { $_.Kind -eq "office" -and $_.Selected } | Select-Object -First 1
$tweakPlan  = Get-TweakPlan -Tweaks $setupTweaks -MenuShown $menuShown
# Si applicano solo le voci spuntate non ancora attive; quelle gia' attive restano come sono
$tweakIds   = @($tweakPlan.Apply | ForEach-Object { $_.Id })

# Nome del PC chiesto subito, cosi' il resto del setup prosegue senza altre domande
$newComputerName = ""
if ($tweakIds -contains "renameComputer") {
    $renameOptions = ($setupTweaks | Where-Object { $_.Id -eq "renameComputer" } | Select-Object -First 1).Options
    $newComputerName = Get-NewComputerName -Configured $renameOptions.ComputerName -Ask:$menuShown
    if (-not $newComputerName) { Write-Host "Il PC non verra' rinominato." -ForegroundColor Yellow }
}

$chosen = @($setupItems | Where-Object { $_.Selected })
if ($chosen.Count -gt 0) {
    Write-Host "Programmi da installare:" -ForegroundColor Cyan
    foreach ($item in $chosen) { Write-Host "  - $($item.Label)" }
} else {
    Write-Host "Nessun programma da installare." -ForegroundColor Yellow
}
if ($tweakPlan.Apply.Count -gt 0) {
    Write-Host "Ottimizzazioni da applicare:" -ForegroundColor Cyan
    foreach ($item in $tweakPlan.Apply) { Write-Host "  - $($item.Label)" }
} else {
    Write-Host "Nessuna nuova ottimizzazione da applicare." -ForegroundColor Yellow
}
if ($tweakPlan.Keep.Count -gt 0) {
    Write-Host "Gia' attive, lasciate come sono:" -ForegroundColor Green
    foreach ($item in $tweakPlan.Keep) { Write-Host "  - $($item.Label)" }
}
if ($tweakPlan.Revert.Count -gt 0) {
    Write-Host "Da riportare ai valori predefiniti di Windows:" -ForegroundColor Yellow
    foreach ($item in $tweakPlan.Revert) { Write-Host "  - $($item.Label)" }
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

# ---- RIPRISTINO AI VALORI DI WINDOWS (voci attive a cui e' stata tolta la spunta) ----
foreach ($tw in $tweakPlan.Revert) {
    Write-Host "Ripristino ai valori di Windows: $($tw.Label)..." -ForegroundColor Cyan
    try {
        & $TweakState[$tw.Id].Revert
        Write-Host "Ripristinato: $($tw.Label)." -ForegroundColor Green
    } catch {
        Write-Host "Ripristino non riuscito ($($tw.Label)): $($_.Exception.Message)" -ForegroundColor Yellow
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

if ($tweakIds -contains "removeOneDrive") {
    # ---- RIMOZIONE ONEDRIVE (non reversibile) ----
    Write-Host "Rimozione OneDrive..." -ForegroundColor Cyan
    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    # Il programma di disinstallazione e' indicato nel registro (installazione per utente o di sistema)
    $uninstallKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe"
    )
    $uninstall = $null
    foreach ($k in $uninstallKeys) {
        $v = Get-RegValue $k "UninstallString"
        if ($v) { $uninstall = $v; break }
    }
    if ($uninstall) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstall`"" -Wait -WindowStyle Hidden
    } else {
        foreach ($exe in @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe")) {
            if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -ArgumentList "/uninstall" -Wait; break }
        }
    }
    if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) {
        Write-Host "OneDrive sembra ancora in esecuzione: verifica a mano da App installate." -ForegroundColor Yellow
    } else {
        Write-Host "OneDrive rimosso." -ForegroundColor Green
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

if ($tweakIds -contains "disableOfficeTelemetry") {
    # ---- TELEMETRIA DI OFFICE ----
    Write-Host "Disattivazione telemetria di Office..." -ForegroundColor Cyan
    Set-RegValue -Path "$RegOffice\common\clienttelemetry" -Name sendtelemetry -Value 3        # 3 = nessun dato diagnostico
    Set-RegValue -Path "$RegOffice\16.0\common\clienttelemetry" -Name DisableTelemetry -Value 1
    Set-RegValue -Path "$RegOffice\16.0\common\clienttelemetry" -Name SendTelemetry -Value 3
    Set-RegValue -Path "$RegOffice\16.0\osm" -Name Enablelogging -Value 0
    Set-RegValue -Path "$RegOffice\16.0\osm" -Name EnableUpload -Value 0
    Write-Host "Telemetria di Office disattivata." -ForegroundColor Green
}

if ($tweakIds -contains "disableTelemetryTasks") {
    # ---- ATTIVITA' PIANIFICATE DI TELEMETRIA ----
    Write-Host "Disattivazione attivita' pianificate di telemetria..." -ForegroundColor Cyan
    $tasks = @(Get-TelemetryTasks)
    foreach ($t in $tasks) {
        try {
            Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "  Attivita' non disattivata ($($t.TaskName)): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Write-Host "Attivita' di telemetria disattivate: $($tasks.Count)." -ForegroundColor Green
}

if ($tweakIds -contains "disableLocation") {
    # ---- POSIZIONE ----
    Write-Host "Disattivazione posizione..." -ForegroundColor Cyan
    Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name DisableLocation -Value 1
    Set-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name Value -Value "Deny" -Type String
    Write-Host "Posizione disattivata." -ForegroundColor Green
}

if ($tweakIds -contains "disableScoobe") {
    # ---- "COMPLETA LA CONFIGURAZIONE DEL DISPOSITIVO" E SUGGERIMENTI ----
    Write-Host "Disattivazione schermate 'Completa la configurazione' e suggerimenti..." -ForegroundColor Cyan
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name ScoobeSystemSettingEnabled -Value 0
    Set-RegValue -Path $RegCdm -Name "SubscribedContent-310093Enabled" -Value 0      # benvenuto dopo gli aggiornamenti
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested" -Name Enabled -Value 0
    Write-Host "Schermate e suggerimenti disattivati." -ForegroundColor Green
}

if ($tweakIds -contains "edgeQuiet") {
    # ---- EDGE SENZA INVADENZE ----
    Write-Host "Configurazione di Edge..." -ForegroundColor Cyan
    Set-RegValue -Path $RegEdgePolicy -Name HideFirstRunExperience -Value 1
    Set-RegValue -Path $RegEdgePolicy -Name StartupBoostEnabled -Value 0
    Set-RegValue -Path $RegEdgePolicy -Name BackgroundModeEnabled -Value 0
    Write-Host "Edge: niente prima esecuzione, avvio rapido e lavoro in background." -ForegroundColor Green
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

    Set-DesktopWallpaper $wpPath
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

if ($tweakIds -contains "ultimatePerformance") {
    # ---- PIANO PRESTAZIONI ECCELLENTI ----
    Write-Host "Attivazione piano Prestazioni eccellenti..." -ForegroundColor Cyan
    $out  = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
    $guid = [regex]::Match($out, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}').Value
    if ($guid) {
        powercfg /setactive $guid
        Set-RegValue -Path $SetupMarkerKey -Name UltimatePlanGuid -Value $guid -Type String
        Write-Host "Piano Prestazioni eccellenti attivo." -ForegroundColor Green
    } else {
        Write-Host "Piano Prestazioni eccellenti non disponibile su questa edizione di Windows." -ForegroundColor Yellow
    }
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

if ($tweakIds -contains "taskbarEndTask") {
    # ---- "TERMINA ATTIVITA'" NELLA BARRA ----
    Write-Host "Aggiunta di 'Termina attivita' al tasto destro della barra..." -ForegroundColor Cyan
    Set-RegValue -Path "$RegAdvanced\TaskbarDeveloperSettings" -Name TaskbarEndTask -Value 1
    $restartExplorer = $true
    Write-Host "'Termina attivita' attivato (Windows 11 23H2 o successivo)." -ForegroundColor Green
}

if ($tweakIds -contains "disableStickyKeys") {
    # ---- SCORCIATOIE DI ACCESSIBILITA' ----
    Write-Host "Disattivazione scorciatoia Tasti permanenti..." -ForegroundColor Cyan
    Set-RegValue -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name Flags -Value "506" -Type String
    Set-RegValue -Path "HKCU:\Control Panel\Accessibility\ToggleKeys" -Name Flags -Value "58" -Type String
    Set-RegValue -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name Flags -Value "122" -Type String
    Write-Host "Scorciatoie Tasti permanenti, Tasti di commutazione e Filtro tasti disattivate." -ForegroundColor Green
}

if ($tweakIds -contains "disableMouseAccel") {
    # ---- ACCELERAZIONE MOUSE ----
    Write-Host "Disattivazione accelerazione del mouse..." -ForegroundColor Cyan
    Set-RegValue -Path "HKCU:\Control Panel\Mouse" -Name MouseSpeed -Value "0" -Type String
    Set-RegValue -Path "HKCU:\Control Panel\Mouse" -Name MouseThreshold1 -Value "0" -Type String
    Set-RegValue -Path "HKCU:\Control Panel\Mouse" -Name MouseThreshold2 -Value "0" -Type String
    Write-Host "Accelerazione del mouse disattivata (attiva dal prossimo accesso)." -ForegroundColor Green
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

# ---- PROGRAMMI SCARICATI DAL SITO DEL PRODUTTORE ----
foreach ($app in @($setupItems | Where-Object { $_.Kind -eq "download" -and $_.Selected })) {
    $dest = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) $app.Options.FileName
    Write-Host "Download $($app.Label)..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $app.Options.Url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Write-Host "$($app.Label) salvato sul Desktop pubblico: $dest" -ForegroundColor Green
    } catch {
        Write-Host "Download di $($app.Label) non riuscito: $($_.Exception.Message)" -ForegroundColor Yellow
    }
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

if ($tweakIds -contains "cleanupTemp") {
    # ---- PULIZIA FILE TEMPORANEI E CACHE DI WINDOWS UPDATE ----
    Write-Host "Pulizia file temporanei e cache di Windows Update..." -ForegroundColor Cyan
    $folders = @("$env:TEMP", "$env:SystemRoot\Temp", "$env:SystemRoot\SoftwareDistribution\Download")
    $sizeOf = {
        param($f)
        $sum = (Get-ChildItem -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($sum) { $sum } else { 0 }
    }
    $before = 0; foreach ($f in $folders) { $before += & $sizeOf $f }
    # Windows Update deve essere fermo per liberare la sua cache
    Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
    foreach ($f in $folders) {
        Get-ChildItem -LiteralPath $f -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Start-Service -Name bits, wuauserv -ErrorAction SilentlyContinue
    $after = 0; foreach ($f in $folders) { $after += & $sizeOf $f }
    Write-Host ("Pulizia completata: liberati {0:N0} MB (i file in uso restano)." -f (($before - $after) / 1MB)) -ForegroundColor Green
}

# Segno che il setup e' stato eseguito: ai prossimi avvii il menu riflette lo stato reale del PC
Set-RegValue -Path $SetupMarkerKey -Name LastRun -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Type String

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

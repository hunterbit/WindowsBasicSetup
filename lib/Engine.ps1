# ============================================================
#  WindowsBasicSetup - motore (nessuna interfaccia)
#  Catalogo, rilevamento dello stato, piano ed esecuzione. Usato da setup.ps1 (console)
#  e dalla GUI: i messaggi passano da Write-SetupLog, mai da Write-Host diretto.
#  Solo definizioni: caricarlo con il dot-sourcing (. .\lib\Engine.ps1) non modifica il sistema.
# ============================================================

# Messaggio del setup. In console lo colora per livello; la GUI imposta $SetupLogHandler
# (scriptblock con parametri Level, Message) per riceverlo al posto della console.
# Il livello Step segna l'inizio di una voce del piano: serve solo alla barra di avanzamento della GUI.
function Write-SetupLog {
    param([ValidateSet("Info", "Ok", "Warn", "Error", "Detail", "Step")][string]$Level, [string]$Message)
    if ($SetupLogHandler) { & $SetupLogHandler $Level $Message; return }
    if ($Level -eq "Step") { return }
    $colors = @{ Info = "Cyan"; Ok = "Green"; Warn = "Yellow"; Error = "Red"; Detail = "Gray" }
    Write-Host $Message -ForegroundColor $colors[$Level]
}

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
            $category = "Altro"
            if ($app.category) { $category = [string]$app.category }
            if ($app.url) {
                # Programma non presente su Chocolatey: scaricato dal sito del produttore sul Desktop pubblico
                $url = [string]$app.url
                if ($url -notmatch '^https://') { throw "config.json: l'url di '$($app.id)' deve iniziare con https://" }
                $fileName = [System.IO.Path]::GetFileName(([uri]$url).AbsolutePath)
                if ($app.fileName) { $fileName = [string]$app.fileName }
                if (-not $fileName) { throw "config.json: per '$($app.id)' indica 'fileName' (nome del file da salvare)." }
                $options = [pscustomobject]@{ Url = $url; FileName = $fileName }
                $items += [pscustomobject]@{ Kind = "download"; Id = [string]$app.id; Label = [string]$name; Category = $category; Selected = $selected; Active = $null; Order = $order++; Options = $options }
            } else {
                # Le impronte (checksum) dei pacchetti si verificano sempre, salvo eccezione esplicita per il singolo programma
                $options = [pscustomobject]@{ IgnoreChecksums = ($app.ignoreChecksums -eq $true) }
                $items += [pscustomobject]@{ Kind = "choco"; Id = [string]$app.id; Label = [string]$name; Category = $category; Selected = $selected; Active = $null; Order = $order++; Options = $options }
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
        $category = "Altro"
        if ($config.office.category) { $category = [string]$config.office.category }
        $items += [pscustomobject]@{ Kind = "office"; Id = $office.ProductId; Label = $label; Category = $category; Selected = $selected; Active = $null; Order = $order++; Options = $office }
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
            $category = "Altro"
            if ($tweak.category) { $category = [string]$tweak.category }
            $tweaks += [pscustomobject]@{ Kind = "tweak"; Id = $id; Label = [string]$name; Category = $category; Selected = $selected; Active = $null; Order = $order++; Options = $options }
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
        Write-SetupLog Warn "  Impostazione non applicata ($Path\$Name): $($_.Exception.Message)"
        if ($Hint) { Write-SetupLog Warn "  $Hint" }
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
            Write-SetupLog Warn "  Impossibile rimuovere $($pkg.Name): $($_.Exception.Message)"
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
        Revert = { Set-RegValue -Path $RegAdvanced -Name HideFileExt -Value 1; $Run.RestartExplorer = $true }
    }
    classicContextMenu = @{
        Test   = { Test-Path -LiteralPath "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" }
        Revert = {
            Remove-Item -LiteralPath "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
            $Run.RestartExplorer = $true
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
            $Run.RebootNeeded = $true
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
            $Run.RestartExplorer = $true
        }
    }
    taskbarWin11 = @{
        Test   = { (Get-RegValue $RegAdvanced "TaskbarAl") -eq 0 }
        Revert = {
            foreach ($n in @("TaskbarAl", "ShowTaskViewButton", "TaskbarMn")) { Remove-RegValue $RegAdvanced $n }
            Remove-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests"
            $Run.RestartExplorer = $true
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
        Revert = { Remove-RegValue "$RegAdvanced\TaskbarDeveloperSettings" "TaskbarEndTask"; $Run.RestartExplorer = $true }
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
            if ($r.RestartNeeded) { $Run.RebootNeeded = $true }
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


# Installa i pacchetti Chocolatey e restituisce l'elenco di quelli falliti
function Install-ChocoApps {
    param([object[]]$Apps)

    $failed = @()
    foreach ($app in $Apps) {
        Write-SetupLog Step $app.Label
        Write-SetupLog Info "Installazione $($app.Label)..."
        $chocoArgs = @("install", $app.Id, "-y")
        if ($app.Options -and $app.Options.IgnoreChecksums) {
            Write-SetupLog Warn "  Verifica dell'impronta disattivata per $($app.Label) (ignoreChecksums in config.json)."
            $chocoArgs += "--ignore-checksums"
        }
        choco @chocoArgs | ForEach-Object { Write-SetupLog Detail "$_" }
        # 1641 e 3010 = installato, riavvio richiesto
        if (@(0, 1641, 3010) -notcontains $LASTEXITCODE) { $failed += $app }
    }
    return $failed
}

# ============================================================
#  ESECUZIONE
# ============================================================

# Azione di ogni ottimizzazione, nell'ordine di esecuzione. Ricevono la voce ($Item, con .Options)
# e segnalano riavvio di Explorer / del PC in $Run, la tabella creata da Invoke-SetupPlan.
$TweakActions = [ordered]@{
    restorePoint = {
        param($Item)
        # ---- PUNTO DI RIPRISTINO (prima di qualsiasi modifica) ----
        Write-SetupLog Info "Creazione punto di ripristino..."
        $srKey     = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
        $srOldFreq = (Get-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
            # Windows crea al massimo un punto ogni 24 ore: il limite viene tolto solo per questa creazione
            Set-RegValue -Path $srKey -Name SystemRestorePointCreationFrequency -Value 0
            Checkpoint-Computer -Description "WindowsBasicSetup - prima delle modifiche" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Write-SetupLog Ok "Punto di ripristino creato."
        } catch {
            Write-SetupLog Warn "Punto di ripristino NON creato: $($_.Exception.Message)"
        } finally {
            if ($null -eq $srOldFreq) {
                Remove-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
            } else {
                Set-RegValue -Path $srKey -Name SystemRestorePointCreationFrequency -Value $srOldFreq
            }
        }
    }
    renameComputer = {
        param($Item)
        # ---- RINOMINA PC (effettivo al prossimo riavvio); nome scelto prima dell'esecuzione ----
        $newName = $Item.Options.ComputerName
        if (-not $newName) { return }
        Write-SetupLog Info "Rinomina del PC in '$newName'..."
        try {
            Rename-Computer -NewName $newName -Force -ErrorAction Stop -WarningAction SilentlyContinue
            Write-SetupLog Ok "PC rinominato in '$newName' (attivo dopo il riavvio)."
            $Run.RebootNeeded = $true
        } catch {
            Write-SetupLog Warn "Rinomina non riuscita: $($_.Exception.Message)"
        }
    }
    removeBloatware = {
        param($Item)
        # ---- RIMOZIONE APP PREINSTALLATE ----
        Write-SetupLog Info "Rimozione app preinstallate..."
        $bloat   = $Item.Options.Packages
        $removed = @()
        foreach ($pattern in $bloat) { $removed += @(Remove-AppxByName -Pattern $pattern) }
        if ($removed.Count -gt 0) {
            Write-SetupLog Ok "App rimosse: $(($removed | Sort-Object -Unique) -join ', ')"
        } else {
            Write-SetupLog Ok "Nessuna delle app in elenco era presente."
        }
    }
    removeOneDrive = {
        param($Item)
        # ---- RIMOZIONE ONEDRIVE (non reversibile) ----
        Write-SetupLog Info "Rimozione OneDrive..."
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
            Write-SetupLog Warn "OneDrive sembra ancora in esecuzione: verifica a mano da App installate."
        } else {
            Write-SetupLog Ok "OneDrive rimosso."
        }
    }
    disableTelemetry = {
        param($Item)
        # ---- TELEMETRIA / ID PUBBLICITARIO ----
        Write-SetupLog Info "Riduzione telemetria..."
        # 0 = solo dati di sicurezza su Enterprise/Education; Home e Pro lo applicano come "dati obbligatori"
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name AllowTelemetry -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name Enabled -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name TailoredExperiencesWithDiagnosticDataEnabled -Value 0
        Write-SetupLog Ok "Telemetria ridotta e ID pubblicitario disattivato."
    }
    disableSuggestions = {
        param($Item)
        # ---- APP SUGGERITE / PUBBLICITA' ----
        Write-SetupLog Info "Disattivazione app suggerite e suggerimenti..."
        $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        foreach ($name in @("SilentInstalledAppsEnabled", "SystemPaneSuggestionsEnabled", "SoftLandingEnabled",
                            "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled",
                            "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")) {
            Set-RegValue -Path $cdm -Name $name -Value 0
        }
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Start_IrisRecommendations -Value 0
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name DisableWindowsConsumerFeatures -Value 1
        Write-SetupLog Ok "App suggerite e suggerimenti disattivati."
    }
    disableCopilot = {
        param($Item)
        # ---- COPILOT / RECALL ----
        Write-SetupLog Info "Disattivazione Copilot e Recall..."
        Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name TurnOffWindowsCopilot -Value 1
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name TurnOffWindowsCopilot -Value 1
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowCopilotButton -Value 0
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name DisableAIDataAnalysis -Value 1
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name AllowRecallEnablement -Value 0
        # Sulle build recenti Copilot e' un'app dello Store
        $null = Remove-AppxByName -Pattern "Microsoft.Copilot"
        $Run.RestartExplorer = $true
        Write-SetupLog Ok "Copilot e Recall disattivati."
    }
    disableOfficeTelemetry = {
        param($Item)
        # ---- TELEMETRIA DI OFFICE ----
        Write-SetupLog Info "Disattivazione telemetria di Office..."
        Set-RegValue -Path "$RegOffice\common\clienttelemetry" -Name sendtelemetry -Value 3        # 3 = nessun dato diagnostico
        Set-RegValue -Path "$RegOffice\16.0\common\clienttelemetry" -Name DisableTelemetry -Value 1
        Set-RegValue -Path "$RegOffice\16.0\common\clienttelemetry" -Name SendTelemetry -Value 3
        Set-RegValue -Path "$RegOffice\16.0\osm" -Name Enablelogging -Value 0
        Set-RegValue -Path "$RegOffice\16.0\osm" -Name EnableUpload -Value 0
        Write-SetupLog Ok "Telemetria di Office disattivata."
    }
    disableTelemetryTasks = {
        param($Item)
        # ---- ATTIVITA' PIANIFICATE DI TELEMETRIA ----
        Write-SetupLog Info "Disattivazione attivita' pianificate di telemetria..."
        $tasks = @(Get-TelemetryTasks)
        foreach ($t in $tasks) {
            try {
                Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
            } catch {
                Write-SetupLog Warn "  Attivita' non disattivata ($($t.TaskName)): $($_.Exception.Message)"
            }
        }
        Write-SetupLog Ok "Attivita' di telemetria disattivate: $($tasks.Count)."
    }
    disableLocation = {
        param($Item)
        # ---- POSIZIONE ----
        Write-SetupLog Info "Disattivazione posizione..."
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name DisableLocation -Value 1
        Set-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name Value -Value "Deny" -Type String
        Write-SetupLog Ok "Posizione disattivata."
    }
    disableScoobe = {
        param($Item)
        # ---- "COMPLETA LA CONFIGURAZIONE DEL DISPOSITIVO" E SUGGERIMENTI ----
        Write-SetupLog Info "Disattivazione schermate 'Completa la configurazione' e suggerimenti..."
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name ScoobeSystemSettingEnabled -Value 0
        Set-RegValue -Path $RegCdm -Name "SubscribedContent-310093Enabled" -Value 0      # benvenuto dopo gli aggiornamenti
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested" -Name Enabled -Value 0
        Write-SetupLog Ok "Schermate e suggerimenti disattivati."
    }
    edgeQuiet = {
        param($Item)
        # ---- EDGE SENZA INVADENZE ----
        Write-SetupLog Info "Configurazione di Edge..."
        Set-RegValue -Path $RegEdgePolicy -Name HideFirstRunExperience -Value 1
        Set-RegValue -Path $RegEdgePolicy -Name StartupBoostEnabled -Value 0
        Set-RegValue -Path $RegEdgePolicy -Name BackgroundModeEnabled -Value 0
        Write-SetupLog Ok "Edge: niente prima esecuzione, avvio rapido e lavoro in background."
    }
    copyMoveTo = {
        param($Item)
        # ---- COPIA IN / SPOSTA IN ----
        Write-SetupLog Info "Aggiunta di 'Copia in' e 'Sposta in' al menu contestuale..."
        reg add "HKCR\AllFilesystemObjects\shellex\ContextMenuHandlers\CopyTo" /ve /d "{C2FBB630-2971-11D1-A18C-00C04FD75D13}" /f | Out-Null
        reg add "HKCR\AllFilesystemObjects\shellex\ContextMenuHandlers\MoveTo" /ve /d "{C2FBB631-2971-11D1-A18C-00C04FD75D13}" /f | Out-Null
        Write-SetupLog Ok "'Copia in' e 'Sposta in' aggiunti."
    }
    showFileExtensions = {
        param($Item)
        # ---- ESTENSIONI FILE ----
        Write-SetupLog Info "Attivazione estensioni dei file..."
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f | Out-Null
        $Run.RestartExplorer = $true
        Write-SetupLog Ok "Estensioni dei file visibili."
    }
    disableWebSearch = {
        param($Item)
        # ---- CORTANA / BING ----
        Write-SetupLog Info "Disattivazione Cortana e Bing nella ricerca..."
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v CortanaConsent /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f | Out-Null
        Write-SetupLog Ok "Cortana e Bing disattivati nella ricerca."
    }
    securityHealthTray = {
        param($Item)
        # ---- SICUREZZA DI WINDOWS NELLA SYSTRAY ----
        Write-SetupLog Info "Ripristino icona Sicurezza di Windows nella systray..."
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" /v HideSystray /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" /v SecurityHealth /t REG_BINARY /d 060000000000000000000000 /f | Out-Null
        reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v SecurityHealth /t REG_EXPAND_SZ /d "%windir%\system32\SecurityHealthSystray.exe" /f | Out-Null
        Write-SetupLog Ok "Icona Sicurezza di Windows ripristinata."
    }
    registeredOwner = {
        param($Item)
        # ---- PROPRIETARIO / ORGANIZZAZIONE REGISTRATI ----
        Write-SetupLog Info "Impostazione proprietario e organizzazione registrati..."
        $regInfo = $Item.Options
        # Set-ItemProperty e non reg.exe: PowerShell 5.1 scarta gli argomenti vuoti passati agli eseguibili
        $ntPath  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        New-ItemProperty -Path $ntPath -Name RegisteredOwner        -Value $regInfo.Owner        -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $ntPath -Name RegisteredOrganization -Value $regInfo.Organization -PropertyType String -Force | Out-Null
        Write-SetupLog Ok "Proprietario e organizzazione impostati."
    }
    wallpaper = {
        param($Item)
        # ---- WALLPAPER ----
        Write-SetupLog Info "Impostazione sfondo..."
        $wpUrl  = $Item.Options.Url
        $wpPath = Join-Path $env:APPDATA "wallpaper.jpg"
        Invoke-WebRequest -Uri $wpUrl -OutFile $wpPath -UseBasicParsing

        Set-DesktopWallpaper $wpPath
        Write-SetupLog Ok "Sfondo impostato."

        # ---- LOCKSCREEN ----
        Write-SetupLog Info "Impostazione lockscreen..."

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
        Write-SetupLog Ok "Lockscreen impostata."
    }
    classicContextMenu = {
        param($Item)
        # ---- MENU CONTESTUALE CLASSICO (Windows 11) ----
        Write-SetupLog Info "Ripristino menu contestuale classico..."
        reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve | Out-Null
        $Run.RestartExplorer = $true
        Write-SetupLog Ok "Menu contestuale classico attivato."
    }
    disableUac = {
        param($Item)
        # ---- UAC ----
        Write-SetupLog Info "Disabilitazione UAC..."
        $uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        New-ItemProperty -Path $uacPath -Name ConsentPromptBehaviorAdmin    -Value 0 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $uacPath -Name ConsentPromptBehaviorUser     -Value 3 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $uacPath -Name EnableInstallerDetection      -Value 1 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $uacPath -Name EnableLUA                     -Value 0 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $uacPath -Name EnableVirtualization          -Value 0 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $uacPath -Name PromptOnSecureDesktop         -Value 0 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $uacPath -Name ValidateAdminCodeSignatures   -Value 0 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $uacPath -Name FilterAdministratorToken      -Value 0 -PropertyType DWORD -Force | Out-Null
        Write-SetupLog Ok "UAC disabilitato."
    }
    darkTheme = {
        param($Item)
        # ---- TEMA SCURO ----
        Write-SetupLog Info "Attivazione tema scuro..."
        $themePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        New-ItemProperty -Path $themePath -Name AppsUseLightTheme    -Value 0 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $themePath -Name SystemUsesLightTheme -Value 0 -PropertyType DWORD -Force | Out-Null
        Write-SetupLog Ok "Tema scuro attivato."
    }
    ultimatePerformance = {
        param($Item)
        # ---- PIANO PRESTAZIONI ECCELLENTI ----
        Write-SetupLog Info "Attivazione piano Prestazioni eccellenti..."
        $out  = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
        $guid = [regex]::Match($out, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}').Value
        if ($guid) {
            powercfg /setactive $guid
            Set-RegValue -Path $SetupMarkerKey -Name UltimatePlanGuid -Value $guid -Type String
            Write-SetupLog Ok "Piano Prestazioni eccellenti attivo."
        } else {
            Write-SetupLog Warn "Piano Prestazioni eccellenti non disponibile su questa edizione di Windows."
        }
    }
    powerPlan = {
        param($Item)
        # ---- POWER / BOOT ----
        Write-SetupLog Info "Configurazione power plan e boot..."
        # Solo con alimentazione da rete: a batteria restano i valori di Windows, per non scaricare i portatili
        powercfg -change -standby-timeout-ac 0
        powercfg -change -monitor-timeout-ac 0
        powercfg -change -disk-timeout-ac 0
        bcdedit /timeout 3 | Out-Null
        Write-SetupLog Ok "Power plan e boot configurati."
    }
    taskbarWin11 = {
        param($Item)
        # ---- BARRA APPLICAZIONI WINDOWS 11 ----
        Write-SetupLog Info "Configurazione barra applicazioni..."
        $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-RegValue -Path $adv -Name TaskbarAl -Value 0            # allineata a sinistra
        Set-RegValue -Path $adv -Name ShowTaskViewButton -Value 0   # niente Visualizzazione attivita'
        Set-RegValue -Path $adv -Name TaskbarMn -Value 0            # niente Chat
        # Niente Widget: sulle build recenti di Windows 11 questa chiave e' protetta e la scrittura viene negata
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name AllowNewsAndInterests -Value 0 `
            -Hint "Windows protegge l'impostazione dei Widget su questa build: disattivali da Impostazioni > Personalizzazione > Barra delle applicazioni."
        $Run.RestartExplorer = $true
        Write-SetupLog Ok "Barra applicazioni configurata."
    }
    taskbarEndTask = {
        param($Item)
        # ---- "TERMINA ATTIVITA'" NELLA BARRA ----
        Write-SetupLog Info "Aggiunta di 'Termina attivita' al tasto destro della barra..."
        Set-RegValue -Path "$RegAdvanced\TaskbarDeveloperSettings" -Name TaskbarEndTask -Value 1
        $Run.RestartExplorer = $true
        Write-SetupLog Ok "'Termina attivita' attivato (Windows 11 23H2 o successivo)."
    }
    disableStickyKeys = {
        param($Item)
        # ---- SCORCIATOIE DI ACCESSIBILITA' ----
        Write-SetupLog Info "Disattivazione scorciatoia Tasti permanenti..."
        Set-RegValue -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name Flags -Value "506" -Type String
        Set-RegValue -Path "HKCU:\Control Panel\Accessibility\ToggleKeys" -Name Flags -Value "58" -Type String
        Set-RegValue -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name Flags -Value "122" -Type String
        Write-SetupLog Ok "Scorciatoie Tasti permanenti, Tasti di commutazione e Filtro tasti disattivate."
    }
    disableMouseAccel = {
        param($Item)
        # ---- ACCELERAZIONE MOUSE ----
        Write-SetupLog Info "Disattivazione accelerazione del mouse..."
        Set-RegValue -Path "HKCU:\Control Panel\Mouse" -Name MouseSpeed -Value "0" -Type String
        Set-RegValue -Path "HKCU:\Control Panel\Mouse" -Name MouseThreshold1 -Value "0" -Type String
        Set-RegValue -Path "HKCU:\Control Panel\Mouse" -Name MouseThreshold2 -Value "0" -Type String
        Write-SetupLog Ok "Accelerazione del mouse disattivata (attiva dal prossimo accesso)."
    }
    disableFastStartup = {
        param($Item)
        # ---- AVVIO RAPIDO ----
        Write-SetupLog Info "Disattivazione Avvio rapido..."
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -Value 0
        Write-SetupLog Ok "Avvio rapido disattivato: lo spegnimento ora chiude davvero la sessione."
    }
    disableHibernation = {
        param($Item)
        # ---- IBERNAZIONE ----
        Write-SetupLog Info "Disattivazione ibernazione..."
        powercfg /hibernate off
        Write-SetupLog Ok "Ibernazione disattivata (hiberfil.sys rimosso)."
    }
    enableRdp = {
        param($Item)
        # ---- DESKTOP REMOTO ----
        $edition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).EditionID
        if ($edition -like "Core*") {
            Write-SetupLog Warn "Desktop remoto non disponibile su Windows Home ($edition): saltato."
        } else {
            Write-SetupLog Info "Abilitazione Desktop remoto..."
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0
            # Autenticazione a livello di rete (NLA) obbligatoria
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1
            # Gruppo di regole "Desktop remoto" indicato per id: funziona con Windows in qualsiasi lingua
            Enable-NetFirewallRule -Group "@FirewallAPI.dll,-28752" -ErrorAction SilentlyContinue
            Write-SetupLog Ok "Desktop remoto abilitato (con NLA) e regole firewall attivate."
        }
    }
    enableNetFx3 = {
        param($Item)
        # ---- .NET FRAMEWORK 3.5 (scaricato da Windows Update) ----
        Write-SetupLog Info "Abilitazione .NET Framework 3.5 (puo' richiedere alcuni minuti)..."
        try {
            $nfx = Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction Stop
            if ($nfx.RestartNeeded) { $Run.RebootNeeded = $true }
            Write-SetupLog Ok ".NET Framework 3.5 abilitato."
        } catch {
            Write-SetupLog Warn ".NET Framework 3.5 NON abilitato: $($_.Exception.Message)"
        }
    }
    windowsUpdate = {
        param($Item)
        Write-SetupLog Info "Preparazione modulo aggiornamenti..."
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue) -or `
            (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue).Version -lt "2.8.5.201") {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        }
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Install-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
        }
        try {
            Import-Module PSWindowsUpdate -ErrorAction Stop
            Write-SetupLog Info "Ricerca e installazione aggiornamenti Windows..."
            # -IgnoreReboot: non riavvia mai, il riavvio resta a cura dell'utente.
            # -NotCategory Upgrades: esclude i passaggi di versione (es. Windows 10 -> 11).
            # 4>&1: i messaggi Verbose finiscono nel log (anche nella GUI, che non ha una console)
            Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -NotCategory "Upgrades" -Verbose 4>&1
            if (Get-WURebootStatus -Silent) { $Run.RebootNeeded = $true }
            Write-SetupLog Ok "Aggiornamenti installati. Alcuni compaiono solo dopo il riavvio: in quel caso rilancia Windows Update."
        } catch {
            Write-SetupLog Warn "Windows Update non eseguito: $($_.Exception.Message)"
        }
    }
    cleanupTemp = {
        param($Item)
        # ---- PULIZIA FILE TEMPORANEI E CACHE DI WINDOWS UPDATE ----
        Write-SetupLog Info "Pulizia file temporanei e cache di Windows Update..."
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
        Write-SetupLog Ok ("Pulizia completata: liberati {0:N0} MB (i file in uso restano)." -f (($before - $after) / 1MB))
    }
}

# Ottimizzazioni eseguite dopo l'installazione dei programmi (lente o da fare per ultime)
$LateTweaks = @("enableNetFx3", "windowsUpdate", "cleanupTemp")

# Inoltra al log l'output dei comandi (powercfg, Chocolatey, Windows Update...): senza, dentro
# Invoke-SetupPlan finirebbe nel valore restituito invece che a schermo
function Write-SetupOutput {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)
    process { $InputObject | Out-String -Stream | Where-Object { $_.Trim() } | ForEach-Object { Write-SetupLog Detail $_ } }
}

# Esegue l'azione di una ottimizzazione; un errore viene segnalato e il setup prosegue
function Invoke-TweakAction {
    param($Item)
    Write-SetupLog Step $Item.Label
    try {
        & $TweakActions[$Item.Id] $Item | Write-SetupOutput
    } catch {
        Write-SetupLog Warn "$($Item.Label): non completata ($($_.Exception.Message))"
    }
}

# Esegue il piano di Get-TweakPlan e installa i programmi selezionati in $Items.
# Ordine: punto di ripristino, ripristini, ottimizzazioni, Explorer, programmi, Office, $LateTweaks.
# Non riavvia mai il PC: restituisce RebootNeeded e i programmi Chocolatey non installati.
function Invoke-SetupPlan {
    param([object]$Plan, [object[]]$Items)

    # Letta e scritta dalle azioni e dai Revert tramite lo scope dinamico di PowerShell
    $Run = @{ RebootNeeded = $false; RestartExplorer = $false; FailedApps = @() }
    $apply = @{}
    foreach ($tw in $Plan.Apply) { $apply[$tw.Id] = $tw }

    # Il punto di ripristino precede qualsiasi modifica, ripristini compresi
    if ($apply.ContainsKey("restorePoint")) { Invoke-TweakAction $apply["restorePoint"] }

    # ---- RIPRISTINO AI VALORI DI WINDOWS (voci attive a cui e' stata tolta la spunta) ----
    foreach ($tw in $Plan.Revert) {
        Write-SetupLog Step $tw.Label
        Write-SetupLog Info "Ripristino ai valori di Windows: $($tw.Label)..."
        try {
            & $TweakState[$tw.Id].Revert | Write-SetupOutput
            Write-SetupLog Ok "Ripristinato: $($tw.Label)."
        } catch {
            Write-SetupLog Warn "Ripristino non riuscito ($($tw.Label)): $($_.Exception.Message)"
        }
    }

    foreach ($id in $TweakActions.Keys) {
        if ($id -eq "restorePoint" -or $LateTweaks -contains $id) { continue }
        if ($apply.ContainsKey($id)) { Invoke-TweakAction $apply[$id] }
    }

    if ($Run.RestartExplorer) {
        Write-SetupLog Info "Riavvio di Esplora risorse per applicare le modifiche..."
        taskkill /f /im explorer.exe | Out-Null
        Start-Sleep -Seconds 2
        Start-Process explorer.exe
    }

    $chocoApps = @($Items | Where-Object { $_.Kind -eq "choco" -and $_.Selected })
    if ($chocoApps.Count -gt 0) {
        # ---- CHOCOLATEY ----
        Write-SetupLog Info "Installazione Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')) | Write-SetupOutput
        Write-SetupLog Info "Attesa completamento Chocolatey..."
        Start-Sleep -Seconds 20

        # ---- PROGRAMMI ----
        Write-SetupLog Info "Installazione programmi..."
        $Run.FailedApps = @(Install-ChocoApps -Apps $chocoApps)
        if ($Run.FailedApps.Count -eq 0) {
            Write-SetupLog Ok "Programmi installati."
        } else {
            Write-SetupLog Error "Programmi NON installati (errore Chocolatey):"
            foreach ($app in $Run.FailedApps) { Write-SetupLog Error "  - $($app.Label) [$($app.Id)]" }
        }
    } else {
        Write-SetupLog Warn "Nessun pacchetto Chocolatey selezionato: Chocolatey non viene installato."
    }

    # ---- PROGRAMMI SCARICATI DAL SITO DEL PRODUTTORE ----
    foreach ($app in @($Items | Where-Object { $_.Kind -eq "download" -and $_.Selected })) {
        $dest = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) $app.Options.FileName
        Write-SetupLog Step $app.Label
        Write-SetupLog Info "Download $($app.Label)..."
        try {
            Invoke-WebRequest -Uri $app.Options.Url -OutFile $dest -UseBasicParsing -ErrorAction Stop
            Write-SetupLog Ok "$($app.Label) salvato sul Desktop pubblico: $dest"
        } catch {
            Write-SetupLog Warn "Download di $($app.Label) non riuscito: $($_.Exception.Message)"
        }
    }

    # ---- OFFICE ----
    $officeItem = $Items | Where-Object { $_.Kind -eq "office" -and $_.Selected } | Select-Object -First 1
    if ($officeItem) {
        Write-SetupLog Step $officeItem.Label
        Write-SetupLog Info "Download $($officeItem.Label)..."
        $office     = $officeItem.Options
        $officeUrl  = "https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=$($office.ProductId)&platform=$($office.Platform)&language=$($office.Language)&version=O16GA"
        $officeDest = Join-Path ([Environment]::GetFolderPath("Desktop")) "SetupOffice.exe"
        try {
            Invoke-WebRequest -Uri $officeUrl -OutFile $officeDest -UseBasicParsing -ErrorAction Stop
            Write-SetupLog Info "Avvio installazione Office..."
            Start-Process -FilePath $officeDest -Wait -ErrorAction Stop
            Write-SetupLog Ok "Office installato."
        } catch {
            Write-SetupLog Warn "Office NON installato: $($_.Exception.Message)"
        } finally {
            Remove-Item -LiteralPath $officeDest -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($id in $LateTweaks) {
        if ($apply.ContainsKey($id)) { Invoke-TweakAction $apply[$id] }
    }

    # Segno che il setup e' stato eseguito: ai prossimi avvii il menu riflette lo stato reale del PC
    Set-RegValue -Path $SetupMarkerKey -Name LastRun -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Type String

    return [pscustomobject]@{ RebootNeeded = $Run.RebootNeeded; FailedApps = @($Run.FailedApps) }
}

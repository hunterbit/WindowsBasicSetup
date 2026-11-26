# ============================================================
#  SETUP AUTOMATICO - setup.ps1
# ============================================================

#  (nessuno)    : finestra grafica; se non si apre, menu a terminale
#  -Console     : menu a terminale al posto della finestra
#  -Unattended  : salta i menu e usa le voci con "selected": true
#  -ConfigPath  : percorso del catalogo programmi/ottimizzazioni (default: config.json accanto allo script)
param(
    [switch]$Unattended,
    [switch]$Console,
    [string]$ConfigPath
)

if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot "config.json" }

# Auto-elevazione admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ConfigPath `"$ConfigPath`""
    if ($Unattended) { $elevArgs += " -Unattended" }
    if ($Console)    { $elevArgs += " -Console" }
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

# Windows PowerShell 5.1 non sempre usa TLS 1.2 per i download (sfondo, Office, programmi dal sito del produttore)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

# Motore (catalogo, stato, esecuzione) e menu a terminale
. (Join-Path $PSScriptRoot "lib\Engine.ps1")
. (Join-Path $PSScriptRoot "lib\Console.ps1")

# ============================================================
#  SETUP
# ============================================================

# ---- SCELTA PROGRAMMI E OTTIMIZZAZIONI (prima di tutto, cosi' il resto prosegue da solo) ----
try {
    $catalog = Get-SetupCatalog -Path $ConfigPath
} catch {
    [void](Set-ConsoleWindow $true)
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

# Finestra grafica: scelta, esecuzione e riepilogo avvengono li'. Se non si apre, si prosegue con il terminale.
if ($menuShown -and -not $Console) {
    . (Join-Path $PSScriptRoot "lib\Gui.ps1")
    if (Show-SetupGui -Items $setupItems -Tweaks $setupTweaks) { exit }
    Write-Host "Uso il menu a terminale." -ForegroundColor Yellow
}
# Da qui si lavora nel terminale (menu, -Unattended o finestra non disponibile): la console deve vedersi
[void](Set-ConsoleWindow $true)
if ($menuShown) {
    if ($setupItems.Count -gt 0) {
        Select-SetupItems -Items $setupItems
    }
    if ($setupTweaks.Count -gt 0) {
        Select-SetupItems -Items $setupTweaks -Title "Seleziona le ottimizzazioni da applicare" -NoneLabel "nessuna ottimizzazione"
    }
}
$tweakPlan  = Get-TweakPlan -Tweaks $setupTweaks -MenuShown $menuShown
# Si applicano solo le voci spuntate non ancora attive; quelle gia' attive restano come sono
$tweakIds   = @($tweakPlan.Apply | ForEach-Object { $_.Id })

# Nome del PC chiesto subito, cosi' il resto del setup prosegue senza altre domande.
# Il nome scelto (vuoto = non rinominare) e' quello che l'azione renameComputer usera'.
if ($tweakIds -contains "renameComputer") {
    $renameOptions = ($setupTweaks | Where-Object { $_.Id -eq "renameComputer" } | Select-Object -First 1).Options
    $renameOptions.ComputerName = Get-NewComputerName -Configured $renameOptions.ComputerName -Ask:$menuShown
    if (-not $renameOptions.ComputerName) { Write-Host "Il PC non verra' rinominato." -ForegroundColor Yellow }
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
$result = Invoke-SetupPlan -Plan $tweakPlan -Items $setupItems

# ============================================================
Write-Host ""
Write-Host "==============================" -ForegroundColor Green
Write-Host " SETUP COMPLETATO!"            -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green
if ($result.RebootNeeded) {
    Write-Host ""
    Write-Host "Riavvia il PC quando possibile per completare le modifiche." -ForegroundColor Yellow
}
Read-Host "Premi INVIO per chiudere"

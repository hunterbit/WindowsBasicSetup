# Motore finto per il banco di prova: stessi messaggi del vero, nessuna modifica al sistema
function Write-SetupLog {
    param([string]$Level, [string]$Message)
    if ($SetupLogHandler) { & $SetupLogHandler $Level $Message }
}
# Simula l'esecuzione: un passo per voce, con output e un programma fallito
function Invoke-SetupPlan {
    param($Plan, $Items)
    $all = @($Plan.Revert) + @($Plan.Apply) + @($Items | Where-Object { $_.Selected })
    foreach ($i in $all) {
        Write-SetupLog Step $i.Label
        Write-SetupLog Info "Esecuzione $($i.Label)..."
        Write-SetupLog Detail "output di prova"
        Write-SetupLog Ok "$($i.Label) fatto."
        Start-Sleep -Milliseconds 60
    }
    Write-SetupLog Warn "Avviso di prova"
    $failed = @($Items | Where-Object { $_.Selected } | Select-Object -First 1)
    return [pscustomobject]@{ RebootNeeded = $true; FailedApps = $failed }
}

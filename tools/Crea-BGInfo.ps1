# ============================================================
#  WindowsBasicSetup - crea o modifica bginfo.bgi
#  Scarica BGInfo (verificato), lo apre in modalita' configurazione e indica dove salvare il file.
#  Non serve essere amministratori. Istruzioni complete: docs\BGINFO.md
# ============================================================

$root   = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root "bginfo.bgi"
$dir    = Join-Path $env:TEMP "WindowsBasicSetup-BGInfo"
$exe    = Join-Path $dir "Bginfo64.exe"
if (-not [Environment]::Is64BitOperatingSystem) { $exe = Join-Path $dir "Bginfo.exe" }

# Scarica BGInfo dal sito ufficiale Sysinternals e lo usa solo se firmato da Microsoft
function Get-VerifiedBgInfo {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $name = Split-Path -Leaf $exe
    Write-Host "Download di $name da live.sysinternals.com..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://live.sysinternals.com/$name" -OutFile $exe -UseBasicParsing -ErrorAction Stop
    $sig = Get-AuthenticodeSignature -LiteralPath $exe
    if ($sig.Status -ne "Valid" -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
        throw "firma digitale non valida ($($sig.Status))"
    }
}

try {
    Get-VerifiedBgInfo
} catch {
    Write-Host "BGInfo non scaricato: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Premi INVIO per chiudere"
    exit 1
}

Write-Host ""
if (Test-Path -LiteralPath $target) {
    Write-Host "Apro la configurazione esistente: $target" -ForegroundColor Green
} else {
    Write-Host "Nessun bginfo.bgi: BGInfo parte con la configurazione predefinita." -ForegroundColor Yellow
}
Write-Host ""
Write-Host " 1. Appena si apre BGInfo, CLICCA SUBITO sulla finestra: ferma il conto alla rovescia" -ForegroundColor White
Write-Host "    (se arriva a zero BGInfo applica la configurazione a QUESTO PC)." -ForegroundColor White
Write-Host " 2. Componi le informazioni come descritto in docs\BGINFO.md." -ForegroundColor White
Write-Host " 3. File > Save As... e salva con questo nome (gia' copiato negli appunti):" -ForegroundColor White
Write-Host "      $target" -ForegroundColor Cyan
Write-Host " 4. Chiudi BGInfo con Cancel (Annulla) per non cambiare lo sfondo di questo PC." -ForegroundColor White
Write-Host ""
try { Set-Clipboard -Value $target } catch {}

$bgArgs = @()
if (Test-Path -LiteralPath $target) { $bgArgs += "`"$target`"" }
$bgArgs += "/nolicprompt"
$before = $null
if (Test-Path -LiteralPath $target) { $before = (Get-Item -LiteralPath $target).LastWriteTime }
Start-Process -FilePath $exe -ArgumentList $bgArgs -Wait

if (Test-Path -LiteralPath $target) {
    if ($before -and (Get-Item -LiteralPath $target).LastWriteTime -eq $before) {
        Write-Host "bginfo.bgi non modificato." -ForegroundColor Yellow
    } else {
        Write-Host "Salvato: $target" -ForegroundColor Green
        Write-Host "Al prossimo setup, spunta 'Info PC sul desktop (BGInfo)' per usarlo." -ForegroundColor Green
    }
} else {
    Write-Host "Il file non e' stato salvato in $target." -ForegroundColor Yellow
    Write-Host "Se l'hai salvato altrove, spostalo accanto a setup.cmd con il nome bginfo.bgi." -ForegroundColor Yellow
}
Read-Host "Premi INVIO per chiudere"

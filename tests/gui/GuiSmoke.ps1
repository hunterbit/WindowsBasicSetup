# Prova della finestra senza toccare il sistema: apre la GUI (fuori schermo) con il catalogo vero e il
# motore finto FakeEngine.ps1, simula ricerca, Tutti/Nessuno, cambio scheda, Avvia (AutoYes.ps1 conferma
# da un altro processo), salva le schermate PNG e scrive trace.txt nella cartella -Out.
# Uso: powershell -NoProfile -STA -ExecutionPolicy Bypass -File tests\gui\GuiSmoke.ps1 -Out <cartella>
param([string]$Out = (Join-Path $env:TEMP "wbs-gui-smoke"))
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
New-Item -ItemType Directory -Force -Path $Out | Out-Null
. (Join-Path $Repo "lib\Engine.ps1")
. (Join-Path $Repo "lib\Console.ps1")
. (Join-Path $Repo "lib\Gui.ps1")
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$catalog = Get-SetupCatalog -Path (Join-Path $Repo "config.json")
$items  = @($catalog.Items)
$tweaks = @($catalog.Tweaks)

$script:trace   = Join-Path $Out "trace.txt"
$script:autoYes = Join-Path $PSScriptRoot "AutoYes.ps1"
Remove-Item $script:trace -ErrorAction SilentlyContinue
# Riga con orario nel file di traccia
function Write-Trace($m) { Add-Content -LiteralPath $script:trace -Value ("{0:HH:mm:ss.fff} {1}" -f (Get-Date), $m) }

# Salva la finestra come PNG
function Save-Shot($w, $name) {
    $w.UpdateLayout()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$w.ActualWidth), ([int]$w.ActualHeight), 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($w)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $Out "$name.png")); $enc.Save($fs); $fs.Close()
    Write-Trace "shot $name"
}
# Controllo della finestra per nome
function Get-El($n) { $script:w.FindName($n) }
# Simula il clic su un pulsante
function Send-Click($n) { (Get-El $n).RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }

$script:step = 0
$handler = [System.Windows.RoutedEventHandler]{
    param($s, $e)
    $script:w = $s
    $script:w.Left = -4000; $script:w.Top = 0
    Save-Shot $script:w "0-caricamento"
    $script:t = New-Object System.Windows.Threading.DispatcherTimer
    $script:t.Interval = [TimeSpan]::FromMilliseconds(700)
    $script:t.Add_Tick({
        # Aspetta la fine della verifica iniziale dello stato
        if ((Get-El "LoadView").Visibility -eq "Visible") { Write-Trace "caricamento: $((Get-El 'LoadStep').Text) $((Get-El 'LoadProgress').Value)/$((Get-El 'LoadProgress').Maximum)"; return }
        Write-Trace "tick $($script:step) step='$((Get-El 'CurrentStep').Text)' summary='$((Get-El 'Summary').Text)'"
        try {
            switch ($script:step) {
                0 {
                    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $script:w).Handle
                    Write-Trace "finestra visibile: $([WbsConsoleWindow]::IsWindowVisible($hwnd))"
                    Save-Shot $script:w "1-programmi"
                }
                1 { (Get-El "AppSearch").Text = "java" }
                2 { Save-Shot $script:w "2-ricerca-java"; (Get-El "AppSearch").Text = "" }
                3 { Send-Click "AppNone"; Write-Trace "dopo Nessuno: $((Get-El 'Summary').Text)" }
                4 { Send-Click "AppAll"; Write-Trace "dopo Tutti: $((Get-El 'Summary').Text)"; (Get-El "SelectView").SelectedIndex = 1 }
                5 { Save-Shot $script:w "3-ottimizzazioni" }
                6 {
                    $script:t.Stop()
                    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($script:autoYes)`" -Trace `"$($script:trace)`"" -WindowStyle Hidden
                    Write-Trace "clic Avvia"
                    Send-Click "StartButton"
                    Write-Trace "ritorno da Avvia: RunView=$((Get-El 'RunView').Visibility)"
                    $script:t.Start()
                }
                8 { Save-Shot $script:w "4-esecuzione" }
                default {
                    if ($script:step -ge 9 -and (Get-El "CloseButton").Visibility -eq "Visible") {
                        Save-Shot $script:w "5-fine"
                        $script:t.Stop(); $script:w.Close()
                    } elseif ($script:step -gt 60) {
                        Write-Trace "TIMEOUT"; $script:t.Stop(); $script:w.Close()
                    }
                }
            }
        } catch { $x = $_.Exception; while ($x) { Write-Trace "ERRORE step $($script:step): [$($x.GetType().FullName)] $($x.Message)"; if ($x.ErrorRecord) { Write-Trace ("  at " + $x.ErrorRecord.ScriptStackTrace + " | " + $x.ErrorRecord.InvocationInfo.PositionMessage) }; $x = $x.InnerException }; $script:t.Start() }
        $script:step++
    })
    $script:t.Start()
}
[System.Windows.EventManager]::RegisterClassHandler([System.Windows.Window], [System.Windows.FrameworkElement]::LoadedEvent, $handler)

$r = Show-SetupGui -Items $items -Tweaks $tweaks -AlreadyConfigured $true -EnginePath (Join-Path $PSScriptRoot "FakeEngine.ps1")
Write-Trace "Show-SetupGui = $r"
Get-Content -LiteralPath $script:trace

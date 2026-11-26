# ============================================================
#  WindowsBasicSetup - interfaccia grafica (WPF, layout in Gui.xaml)
#  Scelta di programmi e ottimizzazioni per categoria, conferma, poi esecuzione del motore in un
#  runspace separato cosi' la finestra resta reattiva. Richiede lib\Engine.ps1 gia' caricato.
# ============================================================

# Riga degli elenchi. Classe C# perche' WPF non si collega alle proprieta' dei pscustomobject
# (la casella non mostra il valore e non lo riscrive); State e' il testo accanto alla casella.
# Index e' la posizione della voce nell'array del catalogo: un pscustomobject salvato in una
# proprieta' "object" non si puo' piu' modificare da PowerShell.
$WbsRowSource = @"
using System.ComponentModel;
public class WbsSetupRow : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    public int Index { get; set; }
    public string Label { get; set; }
    public string Category { get; set; }
    public bool IsActive { get; set; }
    private bool selected;
    public bool Selected {
        get { return selected; }
        set { if (selected != value) { selected = value; Notify("Selected"); Notify("State"); } }
    }
    public string State {
        get {
            if (!IsActive) return "";
            return selected ? "gi" + (char)224 + " attiva" : "verr" + (char)224 + " riportata ai valori di Windows";
        }
    }
    void Notify(string name) {
        PropertyChangedEventHandler h = PropertyChanged;
        if (h != null) h(this, new PropertyChangedEventArgs(name));
    }
}
"@

# Crea le righe dalle voci del catalogo nell'ordine di config.json: le categorie compaiono
# nell'ordine in cui la prima voce di ciascuna si trova nel file
function New-WbsRows {
    param([object[]]$Items)
    $rows = New-Object System.Collections.Generic.List[object]
    if ($Items.Count -eq 0) { return ,$rows }
    foreach ($i in @(0..($Items.Count - 1) | Sort-Object { $Items[$_].Order })) {
        $it = $Items[$i]
        $r = New-Object WbsSetupRow
        $r.Index    = $i
        $r.Label    = $it.Label
        $r.Category = $it.Category
        $r.IsActive = ($it.Active -eq $true)
        $r.Selected = [bool]$it.Selected
        $rows.Add($r)
    }
    return ,$rows
}

# Vista delle righe raggruppata per categoria e filtrata dal testo della casella di ricerca
function New-WbsView {
    param($Rows, $SearchBox)
    $view = New-Object System.Windows.Data.ListCollectionView -ArgumentList (,$Rows)
    $view.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription "Category"))
    # IndexOf e non -like: il testo digitato puo' contenere [ ] * che -like interpreta
    $view.Filter = [Predicate[object]]{
        param($r)
        $t = $SearchBox.Text.Trim()
        (-not $t) -or ($r.Label.IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or
            ("$($r.Category)".IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    }.GetNewClosure()
    return ,$view
}

# Avvia Invoke-SetupPlan in un runspace separato. I messaggi arrivano nella coda restituita come
# coppie (livello, testo); alla fine arriva ("Done", risultato) oppure ("Fatal", messaggio d'errore).
function Start-SetupRun {
    param([string]$EnginePath, $Plan, [object[]]$Items)

    $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($EnginePath, $Plan, $Items, $Queue)
        # Write-SetupLog del motore manda qui ogni messaggio invece che alla console
        $SetupLogHandler = { param($Level, $Message) $Queue.Enqueue(@($Level, $Message)) }
        try {
            . $EnginePath
            $result = Invoke-SetupPlan -Plan $Plan -Items $Items
            $Queue.Enqueue(@("Done", $result))
        } catch {
            $Queue.Enqueue(@("Fatal", $_.Exception.Message))
        }
    }.ToString())
    [void]$ps.AddArgument($EnginePath).AddArgument($Plan).AddArgument($Items).AddArgument($queue)
    $handle = $ps.BeginInvoke()
    return [pscustomobject]@{ PowerShell = $ps; Handle = $handle; Queue = $queue }
}

# Mostra la finestra: scelta per categoria, conferma, esecuzione con avanzamento e riepilogo.
# Restituisce $false se la finestra non si puo' aprire (il chiamante passa al menu a terminale).
# I gestori degli eventi usano le variabili locali: girano dentro ShowDialog, quindi le vedono.
function Show-SetupGui {
    param([object[]]$Items, [object[]]$Tweaks, [string]$EnginePath = (Join-Path $PSScriptRoot "Engine.ps1"))

    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
        if (-not ("WbsSetupRow" -as [type])) { Add-Type -TypeDefinition $WbsRowSource }
        $xaml   = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "Gui.xaml"), [Text.Encoding]::UTF8)
        $window = [Windows.Markup.XamlReader]::Parse($xaml)
    } catch {
        Write-Host "Interfaccia grafica non disponibile: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }

    $ui = @{}
    foreach ($n in @("SysInfo", "SelectView", "RunView", "AppList", "TweakList", "AppSearch", "TweakSearch",
                     "AppAll", "AppNone", "TweakAll", "TweakNone", "PcName", "WallpaperUrl", "Owner",
                     "Organization", "CurrentStep", "Progress", "LogBox", "StartButton", "CloseButton", "Summary")) {
        $ui[$n] = $window.FindName($n)
    }

    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    $osName = "$($cv.ProductName)"
    # ProductName dice "Windows 10" anche su Windows 11: conta la build
    if ([int]$cv.CurrentBuild -ge 22000) { $osName = $osName -replace "Windows 10", "Windows 11" }
    $ui.SysInfo.Text = "$osName $($cv.DisplayVersion) (build $($cv.CurrentBuild))  -  PC $env:COMPUTERNAME"

    $appRows   = New-WbsRows $Items
    $tweakRows = New-WbsRows $Tweaks
    $appView   = New-WbsView $appRows $ui.AppSearch
    $tweakView = New-WbsView $tweakRows $ui.TweakSearch
    $ui.AppList.ItemsSource   = $appView
    $ui.TweakList.ItemsSource = $tweakView

    # Opzioni: valori iniziali da config.json; campo disattivato se la voce non e' nel catalogo
    $opt = @{}
    foreach ($t in $Tweaks) { $opt[$t.Id] = $t }
    if ($opt.renameComputer)  { $ui.PcName.Text = $opt.renameComputer.Options.ComputerName } else { $ui.PcName.IsEnabled = $false }
    if ($opt.wallpaper)       { $ui.WallpaperUrl.Text = $opt.wallpaper.Options.Url } else { $ui.WallpaperUrl.IsEnabled = $false }
    if ($opt.registeredOwner) {
        $ui.Owner.Text        = $opt.registeredOwner.Options.Owner
        $ui.Organization.Text = $opt.registeredOwner.Options.Organization
    } else {
        $ui.Owner.IsEnabled = $false; $ui.Organization.IsEnabled = $false
    }

    # Riepilogo nella barra inferiore, aggiornato a ogni spunta
    $updateSummary = {
        $apps   = @($appRows   | Where-Object { $_.Selected }).Count
        $apply  = @($tweakRows | Where-Object { $_.Selected -and -not $_.IsActive }).Count
        $revert = @($tweakRows | Where-Object { -not $_.Selected -and $_.IsActive }).Count
        $text = "$apps programmi da installare  -  $apply ottimizzazioni da applicare"
        if ($revert -gt 0) { $text += "  -  $revert da riportare ai valori di Windows" }
        $ui.Summary.Text = $text
    }
    & $updateSummary
    $clickEvent = [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
    $ui.AppList.AddHandler($clickEvent, [System.Windows.RoutedEventHandler]{ & $updateSummary })
    $ui.TweakList.AddHandler($clickEvent, [System.Windows.RoutedEventHandler]{ & $updateSummary })

    $ui.AppSearch.Add_TextChanged({ $appView.Refresh() })
    $ui.TweakSearch.Add_TextChanged({ $tweakView.Refresh() })
    # Tutti / Nessuno agiscono sulle voci visibili (rispettano la ricerca)
    $ui.AppAll.Add_Click({ foreach ($r in $appView) { $r.Selected = $true }; & $updateSummary })
    $ui.AppNone.Add_Click({ foreach ($r in $appView) { $r.Selected = $false }; & $updateSummary })
    $ui.TweakAll.Add_Click({ foreach ($r in $tweakView) { $r.Selected = $true }; & $updateSummary })
    $ui.TweakNone.Add_Click({ foreach ($r in $tweakView) { $r.Selected = $false }; & $updateSummary })

    $state = @{ Running = $false; Run = $null; Steps = 0 }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)

    # Fine dell'esecuzione: chiude il runspace e mostra l'esito
    $finish = {
        param($Result, $Fatal)
        $timer.Stop()
        $state.Running = $false
        try { [void]$state.Run.PowerShell.EndInvoke($state.Run.Handle) } catch {}
        $state.Run.PowerShell.Runspace.Dispose()
        $state.Run.PowerShell.Dispose()
        $ui.Progress.Value = $ui.Progress.Maximum
        if ($Fatal) {
            $ui.CurrentStep.Text = "Setup interrotto da un errore."
            $ui.Summary.Text = $Fatal
            $ui.LogBox.AppendText("[ERRORE] $Fatal`r`n")
        } else {
            $ui.CurrentStep.Text = "Setup completato."
            $parts = @()
            $failed = @($Result.FailedApps)
            if ($failed.Count -gt 0) { $parts += "Programmi non installati: " + (($failed | ForEach-Object { $_.Label }) -join ", ") + "." }
            if ($Result.RebootNeeded) { $parts += "Riavvia il PC quando possibile per completare le modifiche." }
            if ($parts.Count -eq 0) { $parts += "Nessun riavvio necessario." }
            $ui.Summary.Text = $parts -join "  "
            $ui.LogBox.AppendText("`r`n" + ($parts -join "`r`n") + "`r`n")
        }
        $ui.LogBox.ScrollToEnd()
        $ui.StartButton.Visibility = "Collapsed"
        $ui.CloseButton.Visibility = "Visible"
    }

    # Legge i messaggi del runspace e aggiorna avanzamento e log
    $timer.Add_Tick({
        $msg = $null
        while ($state.Running -and $state.Run.Queue.TryDequeue([ref]$msg)) {
            $level = $msg[0]
            switch ($level) {
                "Step" {
                    $state.Steps++
                    $ui.Progress.Value = [Math]::Min($state.Steps, $ui.Progress.Maximum)
                    $ui.CurrentStep.Text = "($($state.Steps)/$($ui.Progress.Maximum))  $($msg[1])"
                }
                "Done"  { & $finish $msg[1] $null }
                "Fatal" { & $finish $null ([string]$msg[1]) }
                default {
                    $prefix = @{ Ok = "[OK] "; Warn = "[!] "; Error = "[ERRORE] "; Info = ""; Detail = "    " }[$level]
                    $ui.LogBox.AppendText("$prefix$($msg[1])`r`n")
                    $ui.LogBox.ScrollToEnd()
                }
            }
        }
    })

    # Avvia: controlla le opzioni, chiede conferma, poi passa alla schermata di esecuzione
    $ui.StartButton.Add_Click({
        $sel = @{}
        foreach ($r in $tweakRows) { $sel[$Tweaks[$r.Index].Id] = $r.Selected }
        if ($opt.renameComputer -and $sel.renameComputer) {
            $name = $ui.PcName.Text.Trim()
            if (-not (Test-ComputerName $name)) {
                [void][System.Windows.MessageBox]::Show($window, "Inserisci un nome PC valido in Opzioni (scheda Ottimizzazioni): massimo 15 caratteri tra lettere, cifre e trattino, non solo cifre.", "Nome PC", "OK", "Warning")
                return
            }
            $opt.renameComputer.Options.ComputerName = $name
        }
        if ($opt.wallpaper -and $sel.wallpaper) {
            $url = $ui.WallpaperUrl.Text.Trim()
            if ($url -notmatch '^https://') {
                [void][System.Windows.MessageBox]::Show($window, "L'URL dello sfondo deve iniziare con https://", "Sfondo", "OK", "Warning")
                return
            }
            $opt.wallpaper.Options.Url = $url
        }
        if ($opt.registeredOwner) {
            $opt.registeredOwner.Options.Owner        = $ui.Owner.Text.Trim()
            $opt.registeredOwner.Options.Organization = $ui.Organization.Text.Trim()
        }
        foreach ($r in $appRows)   { $Items[$r.Index].Selected  = $r.Selected }
        foreach ($r in $tweakRows) { $Tweaks[$r.Index].Selected = $r.Selected }

        $plan  = Get-TweakPlan -Tweaks $Tweaks -MenuShown $true
        $apps  = @($Items | Where-Object { $_.Selected })
        $total = $plan.Apply.Count + $plan.Revert.Count + $apps.Count
        if ($total -eq 0) {
            [void][System.Windows.MessageBox]::Show($window, "Nessun programma e nessuna ottimizzazione da applicare.", "WindowsBasicSetup", "OK", "Information")
            return
        }
        $lines = @("Programmi da installare: $($apps.Count)", "Ottimizzazioni da applicare: $($plan.Apply.Count)")
        if ($plan.Revert.Count -gt 0) {
            $lines += "Da riportare ai valori di Windows:"
            $lines += @($plan.Revert | ForEach-Object { "   - $($_.Label)" })
        }
        $risky = @($plan.Apply | Where-Object { @("removeOneDrive", "disableUac") -contains $_.Id })
        if ($risky.Count -gt 0) {
            $lines += "", "Attenzione:"
            $lines += @($risky | ForEach-Object { "   - $($_.Label)" })
        }
        $lines += "", "Il PC non verra' riavviato automaticamente. Procedere?"
        $answer = [System.Windows.MessageBox]::Show($window, ($lines -join "`n"), "Conferma", "YesNo", "Question")
        if ("$answer" -ne "Yes") { return }

        $ui.SelectView.Visibility = "Collapsed"
        $ui.RunView.Visibility    = "Visible"
        $ui.StartButton.IsEnabled = $false
        $ui.Progress.Maximum = $total
        $ui.Summary.Text = "Setup in corso: non spegnere il PC e non chiudere la finestra."
        $state.Steps   = 0
        $state.Run     = Start-SetupRun -EnginePath $EnginePath -Plan $plan -Items $Items
        $state.Running = $true
        $timer.Start()
    })

    $ui.CloseButton.Add_Click({ $window.Close() })
    # Durante l'esecuzione la finestra non si chiude: un'installazione interrotta a meta' lascia il PC in uno stato incerto
    $window.Add_Closing({
        param($s, $e)
        if ($state.Running) {
            $e.Cancel = $true
            [void][System.Windows.MessageBox]::Show($window, "Setup in corso: attendi la fine.", "WindowsBasicSetup", "OK", "Information")
        }
    })

    [void]$window.ShowDialog()
    return $true
}

# ============================================================
#  WindowsBasicSetup - menu a terminale
#  Scelta di programmi e ottimizzazioni nella console e richiesta del nome del PC.
# ============================================================

# Mostra o nasconde la console e restituisce se prima era visibile. setup.cmd avvia PowerShell
# nascosto per mostrare solo la finestra grafica: la console serve per i menu a terminale,
# -Unattended e i messaggi d'errore.
function Set-ConsoleWindow {
    param([bool]$Visible)
    if (-not ("WbsConsoleWindow" -as [type])) {
        Add-Type -Namespace "" -Name WbsConsoleWindow -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
"@
    }
    $h = [WbsConsoleWindow]::GetConsoleWindow()
    if ($h -eq [IntPtr]::Zero) { return $false }
    $wasVisible = [WbsConsoleWindow]::IsWindowVisible($h)
    $cmd = 0                       # SW_HIDE
    if ($Visible) { $cmd = 5 }     # SW_SHOW
    # Due volte: in un processo avviato nascosto Windows ignora la prima ShowWindow del processo
    # e applica lo stato di avvio (SW_HIDE). Vale per qualsiasi finestra, anche quella della GUI.
    [void][WbsConsoleWindow]::ShowWindow($h, $cmd)
    [void][WbsConsoleWindow]::ShowWindow($h, $cmd)
    return $wasVisible
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

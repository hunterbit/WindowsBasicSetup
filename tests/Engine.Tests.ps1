# Test del motore (Pester 3.4, incluso in Windows): Invoke-Pester .\tests
# Non modificano il sistema: le azioni di Invoke-SetupPlan vengono sostituite con azioni finte.

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root "lib\Engine.ps1")

# Scrive un config.json temporaneo con il contenuto indicato e ne restituisce il percorso
function New-TestConfig {
    param([string]$Json)
    $path = Join-Path ([IO.Path]::GetTempPath()) ("wbs-test-{0}.json" -f [guid]::NewGuid())
    [IO.File]::WriteAllText($path, $Json)
    return $path
}

Describe "Get-SetupCatalog" {
    It "legge il config.json del progetto" {
        $c = Get-SetupCatalog -Path (Join-Path $root "config.json")
        @($c.Items | Where-Object { $_.Kind -eq "choco" }).Count | Should BeGreaterThan 0
        @($c.Items | Where-Object { $_.Kind -eq "office" }).Count | Should Be 1
        @($c.Tweaks).Count | Should Be $KnownTweaks.Count
    }
    It "mette prima le voci spuntate, poi le altre nell'ordine del file" {
        $p = New-TestConfig '{ "apps": [ { "id": "a", "selected": false }, { "id": "b" }, { "id": "c", "selected": false } ] }'
        (@((Get-SetupCatalog -Path $p).Items) | ForEach-Object { $_.Id }) -join "," | Should Be "b,a,c"
    }
    It "rifiuta un'ottimizzazione sconosciuta" {
        $p = New-TestConfig '{ "tweaks": [ { "id": "nonEsiste" } ] }'
        { Get-SetupCatalog -Path $p } | Should Throw
    }
    It "legge la categoria, con 'Altro' se manca" {
        $p = New-TestConfig '{ "apps": [ { "id": "a", "category": "Browser" }, { "id": "b" } ], "tweaks": [ { "id": "darkTheme", "category": "Interfaccia" } ] }'
        $c = Get-SetupCatalog -Path $p
        ($c.Items | ForEach-Object { $_.Category }) -join "," | Should Be "Browser,Altro"
        $c.Tweaks[0].Category | Should Be "Interfaccia"
    }
    It "verifica le impronte dei pacchetti salvo ignoreChecksums esplicito" {
        $p = New-TestConfig '{ "apps": [ { "id": "a" }, { "id": "b", "ignoreChecksums": true } ] }'
        ($c = Get-SetupCatalog -Path $p).Items[0].Options.IgnoreChecksums | Should Be $false
        $c.Items[1].Options.IgnoreChecksums | Should Be $true
    }
    It "rifiuta un download non https" {
        $p = New-TestConfig '{ "apps": [ { "id": "x", "url": "http://example.com/x.exe" } ] }'
        { Get-SetupCatalog -Path $p } | Should Throw
    }
}

Describe "Coerenza delle tabelle" {
    It "ogni ottimizzazione ha un'azione e viceversa" {
        (@($KnownTweaks.Keys) | Sort-Object) -join "," | Should Be ((@($TweakActions.Keys) | Sort-Object) -join ",")
    }
    It "ogni voce reversibile e' un'ottimizzazione nota" {
        @($TweakState.Keys | Where-Object { -not $KnownTweaks.Contains($_) }).Count | Should Be 0
    }
}

Describe "Get-TweakPlan" {
    $t = @(
        [pscustomobject]@{ Id = "a"; Selected = $true;  Active = $false }
        [pscustomobject]@{ Id = "b"; Selected = $true;  Active = $true }
        [pscustomobject]@{ Id = "c"; Selected = $false; Active = $true }
        [pscustomobject]@{ Id = "d"; Selected = $false; Active = $false }
    )
    It "applica, mantiene e ripristina con il menu" {
        $p = Get-TweakPlan -Tweaks $t -MenuShown $true
        ($p.Apply  | ForEach-Object { $_.Id }) -join "," | Should Be "a"
        ($p.Keep   | ForEach-Object { $_.Id }) -join "," | Should Be "b"
        ($p.Revert | ForEach-Object { $_.Id }) -join "," | Should Be "c"
    }
    It "senza menu non ripristina mai" {
        @((Get-TweakPlan -Tweaks $t -MenuShown $false).Revert).Count | Should Be 0
    }
}

Describe "Test-ComputerName" {
    It "accetta nomi validi" {
        Test-ComputerName "PC-UFFICIO1" | Should Be $true
    }
    It "rifiuta nomi non validi" {
        Test-ComputerName "123"              | Should Be $false
        Test-ComputerName "NOME-TROPPO-LUNGO" | Should Be $false
        Test-ComputerName "pc ufficio"       | Should Be $false
    }
}

Describe "Install-ChocoApps" {
    $script:SetupLogHandler = { param($Level, $Message) }
    It "passa --ignore-checksums solo ai pacchetti che lo chiedono" {
        $script:chocoCalls = New-Object System.Collections.ArrayList
        function choco { [void]$script:chocoCalls.Add($args -join " "); $global:LASTEXITCODE = 0 }
        $apps = @(
            [pscustomobject]@{ Id = "a"; Label = "A"; Options = [pscustomobject]@{ IgnoreChecksums = $false } }
            [pscustomobject]@{ Id = "b"; Label = "B"; Options = [pscustomobject]@{ IgnoreChecksums = $true } }
        )
        $null = Install-ChocoApps -Apps $apps
        $script:chocoCalls -join "|" | Should Be "install a -y|install b -y --ignore-checksums"
    }
}

Describe "Invoke-SetupPlan" {
    Mock Set-RegValue {}

    It "esegue nell'ordine: ripristino, revert, ottimizzazioni, voci finali" {
        $calls = New-Object System.Collections.ArrayList
        $script:TweakActions = [ordered]@{
            restorePoint  = { param($Item) [void]$calls.Add("restorePoint") }
            darkTheme     = { param($Item) [void]$calls.Add("darkTheme"); $Run.RestartExplorer = $false }
            renameComputer = { param($Item) [void]$calls.Add("rename"); $Run.RebootNeeded = $true }
            windowsUpdate = { param($Item) [void]$calls.Add("windowsUpdate") }
        }
        $script:TweakState = @{ powerPlan = @{ Revert = { [void]$calls.Add("revert-powerPlan") } } }
        $script:SetupLogHandler = { param($Level, $Message) }

        $item = { param($id) [pscustomobject]@{ Id = $id; Label = $id; Options = $null } }
        $plan = [pscustomobject]@{
            Apply  = @((& $item "windowsUpdate"), (& $item "darkTheme"), (& $item "renameComputer"), (& $item "restorePoint"))
            Keep   = @()
            Revert = @(& $item "powerPlan")
        }
        $r = Invoke-SetupPlan -Plan $plan -Items @()

        $calls -join "," | Should Be "restorePoint,revert-powerPlan,darkTheme,rename,windowsUpdate"
        $r.RebootNeeded | Should Be $true
    }
    It "un'azione che fallisce non ferma le altre" {
        $calls = New-Object System.Collections.ArrayList
        $script:TweakActions = [ordered]@{
            darkTheme = { param($Item) throw "errore di prova" }
            powerPlan = { param($Item) [void]$calls.Add("powerPlan") }
        }
        $script:SetupLogHandler = { param($Level, $Message) }
        $plan = [pscustomobject]@{
            Apply  = @([pscustomobject]@{ Id = "darkTheme"; Label = "x" }, [pscustomobject]@{ Id = "powerPlan"; Label = "y" })
            Keep   = @(); Revert = @()
        }
        $null = Invoke-SetupPlan -Plan $plan -Items @()
        $calls -join "," | Should Be "powerPlan"
    }
    It "l'output dei comandi va nel log, non nel risultato" {
        $logged = New-Object System.Collections.ArrayList
        $script:TweakActions = [ordered]@{ darkTheme = { param($Item) "rumore"; Get-Date } }
        $script:SetupLogHandler = { param($Level, $Message) [void]$logged.Add("$Level $Message") }
        $plan = [pscustomobject]@{ Apply = @([pscustomobject]@{ Id = "darkTheme"; Label = "x" }); Keep = @(); Revert = @() }
        $r = Invoke-SetupPlan -Plan $plan -Items @()
        @($r).Count | Should Be 1
        $r.RebootNeeded | Should Be $false
        @($logged | Where-Object { $_ -eq "Detail rumore" }).Count | Should Be 1
        @($logged | Where-Object { $_ -eq "Step x" }).Count | Should Be 1
    }
}

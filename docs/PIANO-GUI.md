# Piano: interfaccia grafica per WindowsBasicSetup

## Obiettivo

Sostituire i menu a terminale con una finestra in cui:

- programmi e ottimizzazioni sono divisi per **categoria**, con ricerca e "seleziona tutto" per categoria;
- si vede subito lo stato del PC: ottimizzazioni già attive e, novità, **programmi già installati**;
- durante l'esecuzione si vedono avanzamento, log e l'esito di ogni voce;
- alla fine compare un riepilogo: voci fallite, voci ripristinate e se serve un riavvio.

Restano invariati: `config.json` come catalogo, la modalità `-Unattended`, il menu a terminale (come alternativa), nessun riavvio automatico e il ripristino ai valori di Windows delle voci attive a cui si toglie la spunta.

## Scelta tecnologica

| Opzione | Pro | Contro |
|---|---|---|
| **PowerShell 5.1 + WPF (XAML)** ✅ | Nessuna dipendenza né compilazione: gira su ogni Windows 10/11 appena installato. Riusa tutto il codice esistente. Si distribuisce come oggi (cartella + `setup.cmd`) | Serve un thread separato (runspace) perché la finestra non si blocchi; XAML scritto a mano |
| C# WPF / WinUI (.exe) | Interfaccia più ricca, un solo file eseguibile | Logica da riscrivere da zero, runtime .NET o eseguibile da circa 70 MB, avvisi SmartScreen senza firma digitale |
| PowerShell + WinForms | Semplice | Aspetto datato, layout rigido |

**Scelta: PowerShell 5.1 + WPF.** Il valore del progetto sta nella logica di rilevamento, applicazione e ripristino, che è già scritta e collaudata; la GUI è solo un nuovo modo di presentarla.

## Architettura

```
WindowsBasicSetup/
├─ setup.cmd              launcher (elevazione) -> setup.ps1
├─ setup.ps1              avvio: sceglie GUI, menu a terminale o unattended
├─ config.json            catalogo (+ campo "category")
├─ lib/
│  ├─ Engine.ps1          catalogo, stato, piano, esecuzione (nessun Write-Host diretto)
│  ├─ Tweaks.ps1          per ogni id: Apply / Test / Revert
│  ├─ Console.ps1         menu a terminale attuale
│  └─ Gui.ps1 + Gui.xaml  finestra WPF
└─ tests/Engine.Tests.ps1 test Pester (Pester 3.4 e' gia' incluso in Windows)
```

### 1. Il motore separato dall'interfaccia

Oggi la parte di esecuzione di `setup.ps1` (righe 785-1274) è una sequenza di blocchi `if ($tweakIds -contains "...")` con `Write-Host`. Va trasformata così:

- `$TweakState` diventa `$Tweaks`: per ogni id `@{ Apply = {...}; Test = {...}; Revert = {...} }`. `Test` e `Revert` restano facoltativi, come per le azioni di oggi;
- `Invoke-SetupPlan -Plan $plan -Report $callback` esegue le voci nell'ordine fisso di oggi: punto di ripristino, ripristini, rinomina, ottimizzazioni, riavvio di Explorer, programmi, Office, .NET 3.5, Windows Update, pulizia;
- ogni messaggio passa da `$callback` (`Info` / `Ok` / `Warn` / `Error` + id della voce). La console lo stampa con `Write-Host`, la GUI lo mostra nel log e nello stato della voce;
- `$rebootNeeded` e `$restartExplorer` diventano campi di un oggetto risultato, non più variabili globali.

Questa è la fase più delicata: il comportamento deve restare identico. Va fatta e verificata **prima** di toccare la GUI.

### 2. Le categorie in config.json

Si aggiunge un campo facoltativo `category`; le voci senza categoria finiscono in "Altro":

```json
{ "id": "googlechrome", "name": "Google Chrome", "category": "Browser", "selected": true }
```

Categorie proposte:

- **Programmi:** Browser · Ufficio e PDF · Multimedia · Utilità · Assistenza remota · Rete e sistemisti · Diagnostica · Runtime e librerie · Sviluppo
- **Ottimizzazioni:** Privacy e telemetria · Interfaccia · Energia e prestazioni · Sistema · Manutenzione

L'ordine delle categorie è quello in cui compaiono la prima volta in `config.json`. Il menu a terminale ignora il campo, quindi resta compatibile con i file `config.json` esistenti.

### 3. Rilevamento dei programmi installati

Nuova funzione `Get-InstalledApps`:

- `choco list --limit-output` per i pacchetti installati con Chocolatey;
- le chiavi Uninstall del registro (HKLM 32/64 bit e HKCU) per quelli installati in altro modo, confrontandole con un campo facoltativo `match` in `config.json` (es. `"match": "Google Chrome"`).

Nella GUI i programmi già installati compaiono con l'etichetta "installato" e non spuntati. Non si disinstalla mai niente: togliere la spunta vuol dire solo "non installare".

### 4. La finestra (WPF)

```
┌──────────────────────────────────────────────────────────────┐
│ WindowsBasicSetup            Windows 11 Pro 24H2 · PC-UFFICIO │
├──────────────┬───────────────────────────────────────────────┤
│ [Programmi]  │ 🔍 cerca...                    [Tutti][Nessuno]│
│ [Ottimizz.]  │ ▼ Browser                         ☑ tutti     │
│              │   ☑ Google Chrome                              │
│ Categorie    │   ☑ Mozilla Firefox          installato        │
│  Browser (2) │ ▼ Ufficio e PDF                               │
│  Ufficio (5) │   ☐ PDF24 Creator                              │
│  ...         │ ...                                           │
├──────────────┴───────────────────────────────────────────────┤
│ 12 programmi · 18 ottimizzazioni · 2 da ripristinare  [Avvia]│
└──────────────────────────────────────────────────────────────┘
```

- Due schede (Programmi / Ottimizzazioni), ognuna con un elenco raggruppato per categoria (gruppi richiudibili, casella "tutti" per gruppo).
- Ottimizzazioni: verde "già attiva", arancione "verrà ripristinata" quando si toglie la spunta a una voce attiva. Le voci non reversibili (OneDrive, UAC) chiedono una conferma.
- I campi extra si modificano nella finestra: nome del PC (con la stessa validazione di `Test-ComputerName`), proprietario e organizzazione, URL dello sfondo.
- **Avvia** apre un riepilogo delle azioni (cosa si installa, applica, ripristina) da confermare, poi passa alla schermata di avanzamento: una barra generale, l'elenco delle voci con l'icona di stato (in attesa / in corso / ok / errore) e il log completo, che si può copiare o salvare in un file.
- Fine: riepilogo con le voci fallite e l'avviso "Riavvia il PC" se serve. Il riavvio non parte mai da solo.

**Threading:** la finestra gira sul thread principale (STA: `powershell.exe` 5.1 lo è già). `Invoke-SetupPlan` gira in un runspace separato e comunica con la finestra tramite una hashtable sincronizzata + `Dispatcher.Invoke`. Il pulsante Chiudi resta disattivato durante l'esecuzione, per non interrompere un'installazione a metà.

### 5. Avvio

| Comando | Effetto |
|---|---|
| `setup.cmd` | GUI (predefinita) |
| `setup.ps1 -Console` | menu a terminale di oggi |
| `setup.ps1 -Unattended` | nessuna domanda, solo le voci `"selected": true`, nessun ripristino (come oggi) |

Se la GUI non si avvia (Server Core, sessione senza desktop) si passa automaticamente al menu a terminale.

## Fasi

| # | Fase | Risultato verificabile |
|---|---|---|
| 1 | Separare il motore (`lib/Engine.ps1`, `lib/Tweaks.ps1`) + menu a terminale in `lib/Console.ps1` | `setup.ps1` fa esattamente quello che fa oggi; test Pester su `Get-SetupCatalog`, `Get-TweakPlan`, `Test-ComputerName` |
| 2 | Campo `category` in `config.json` + nuovi programmi | Catalogo diviso per categorie; vecchi `config.json` ancora accettati |
| 3 | `Get-InstalledApps` | Elenco dei programmi installati corretto su un PC di prova |
| 4 | GUI: selezione (schede, categorie, ricerca, stati, campi extra) | La finestra produce lo stesso piano che produrrebbe il menu a terminale |
| 5 | GUI: esecuzione in runspace, avanzamento, log, riepilogo | Setup completo su una macchina virtuale pulita senza che la finestra si blocchi |
| 6 | README e CLAUDE.md aggiornati | Documentazione allineata |

Ogni fase si chiude con un commit; le fasi 1 e 5 si provano su una **macchina virtuale Windows 10 e Windows 11** (con checkpoint, così si torna allo stato pulito), mai sul PC di lavoro.

## Fuori dal perimetro (per ora)

- Eseguibile unico (`ps2exe`) o firma digitale del codice: si valutano dopo, se SmartScreen o gli antivirus danno problemi.
- winget al posto di o insieme a Chocolatey.
- Editor grafico di `config.json` (aggiungere o togliere programmi dalla finestra).
- Profili salvati (es. "Ufficio", "Studio medico", "Gaming").

## Rischi

- **Regressioni nella fase 1:** lo spostamento di 500 righe di blocchi `if` può introdurre errori. Si riduce spostando il codice senza riscriverlo e confrontando il registro di una macchina virtuale prima e dopo con lo stesso `config.json`.
- **Output dei programmi esterni:** l'output di `choco` e di `Install-WindowsUpdate -Verbose` va inoltrato al log riga per riga; altrimenti la GUI sembra bloccata durante le installazioni lunghe.
- **Antivirus:** gli script PowerShell con WPF e runspace che modificano il registro a volte vengono segnalati. Da verificare con Defender sulla macchina virtuale.

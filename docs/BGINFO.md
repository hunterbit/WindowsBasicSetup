# BGInfo: creare e personalizzare `bginfo.bgi`

L'ottimizzazione **Info PC sul desktop (BGInfo)** scrive sullo sfondo del cliente le informazioni del PC. *Quali* informazioni, *dove* e *con che aspetto* lo decide il file `bginfo.bgi` messo accanto a `setup.cmd`. Lo crei una volta e vale per tutti i PC che configuri. Senza il file, BGInfo usa il suo aspetto predefinito (molti campi, in alto a destra).

Il file `.bgi` è in un formato che crea solo BGInfo: non si scrive a mano, si compone nella finestra di BGInfo e si salva.

## Creare il file (circa 2 minuti)

1. Fai doppio clic su `tools\Crea-BGInfo.cmd`. Non servono i permessi di amministratore. Lo script scarica BGInfo dal sito ufficiale Microsoft Sysinternals, controlla la firma digitale e lo apre. Se `bginfo.bgi` esiste già, apre quello per modificarlo.
2. **Clicca subito sulla finestra di BGInfo**: in alto parte un conto alla rovescia di 10 secondi e, se arriva a zero, BGInfo cambia lo sfondo del *tuo* PC.
3. Componi il testo come nella [configurazione consigliata](#configurazione-consigliata) qui sotto.
4. **File > Save As…** e salva come `bginfo.bgi` nella cartella di `setup.cmd`. Lo script ha già copiato il percorso esatto negli appunti: basta incollarlo nel nome del file.
5. Chiudi BGInfo con **Cancel**. Con **OK** applicherebbe la configurazione al tuo PC.

Per modificarlo in seguito, rilancia `tools\Crea-BGInfo.cmd`: riapre il file esistente.

## Configurazione consigliata

### Testo

Nel riquadro grande a sinistra cancella tutto e scrivi le etichette. Per inserire un campo, selezionalo nell'elenco **Fields** a destra e premi **< Add**. Tra etichetta e campo usa il tasto **Tab**, così i valori restano allineati in colonna.

```
PC:	<Host Name>
Utente:	<User Name>
IP:	<IP Address>
Windows:	<OS Version>
Avviato il:	<Boot Time>
Spazio libero:	<Free Space>
Assistenza:	Tua Azienda - 0123 456789
```

- L'ultima riga è testo fisso: metti il nome della tua azienda e il numero di assistenza. Puoi aggiungere anche l'ID di RustDesk o Supremo, se lo comunichi ai clienti.
- Altri campi utili dall'elenco **Fields**: `Default Gateway`, `MAC Address`, `Memory`, `CPU`, `Domain`, `Logon Server`.
- Se un PC ha più schede di rete, `<IP Address>` le mostra tutte, una per riga.

### Carattere

Seleziona tutto il testo (Ctrl+A) e scegli dai menu sopra il riquadro:
- **Segoe UI**, dimensione **9** o **10**;
- **colore bianco** se lo sfondo è scuro, **grigio scuro** se è chiaro. BGInfo non aggiunge ombre: scegli un colore che si legga sullo sfondo che usi di solito;
- etichette normali e valori in **grassetto**, se preferisci: seleziona solo i campi e premi il pulsante B.

### Posizione (pulsante **Position…**)

- Scegli il riquadro **in basso a destra**, sopra l'orologio, dove non copre icone e finestre.
- Spunta **Compensate for Taskbar position**, così il testo non finisce sotto la barra delle applicazioni.

### Sfondo (pulsante **Background…**)

- Lascia **Copy user's wallpaper settings**: BGInfo scrive sopra lo sfondo già impostato, compreso quello messo dal setup con "Sfondo e schermata di blocco".

### Desktop (pulsante **Desktops…**)

- Lascia **User Desktops: Update this wallpaper**. Il setup avvia BGInfo a ogni accesso, quindi le informazioni si aggiornano per ogni utente.

Prima di salvare puoi controllare il risultato con **Preview**: cambia temporaneamente lo sfondo del tuo PC, che torna normale al prossimo accesso o quando reimposti lo sfondo.

## Come lo usa il setup

- Spunta **Info PC sul desktop (BGInfo)**, nella categoria Interfaccia della scheda Ottimizzazioni.
- Il setup installa BGInfo in `C:\Program Files\WindowsBasicSetup\BGInfo` (cartella scrivibile solo dagli amministratori), copia lì `bginfo.bgi` e lo fa partire a ogni accesso per tutti gli utenti.
- Il nome o la posizione del file si possono cambiare in `config.json`: `{ "id": "bgInfo", ..., "config": "bginfo.bgi" }` (percorso relativo alla cartella di `config.json`).
- Togliendo la spunta a un PC dove è attivo, BGInfo smette di partire e i suoi file vengono rimossi. Il testo già disegnato resta finché non cambi lo sfondo.

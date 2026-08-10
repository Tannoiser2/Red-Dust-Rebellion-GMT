# Red Dust Rebellion — Digital Edition

Edizione digitale (non ufficiale, amatoriale) di **Red Dust Rebellion**, il volume XII
della Serie COIN di GMT Games — la ribellione marziana del 2250.

Costruita riusando il **motore COIN generico** sviluppato per
[Cuba Libre](https://github.com/Tannoiser2/Cuba-Libre-GMT) e
[All Bridges Burning](https://github.com/Tannoiser2/All-Bridge-Burning): stessa
architettura `coin_engine/` + `games/<gioco>/`, così che il terzo titolo riusi
`GameRegistry`, `GameManifest`, `GameState`, `SpaceState` e la sequenza di gioco.

## Stato

🚧 **Fase 5 (in corso) — gli Eventi si giocano davvero.** Tutte e **93 le opzioni
delle 48 carte Evento** hanno effetti scritti a mano: niente più "risolvete voi al
tavolo". Ogni opzione dichiara le **scelte** che spettano ai giocatori (quali
spazi, quale Fazione, quale ramo di un "either/or") e la sequenza di effetti da
applicare una volta note; le scelte non fornite vengono riempite scorrendo i
candidati legali, così l'Evento è sempre risolvibile per intero. Le Operazioni
gratuite che gli Eventi concedono finiscono in una coda e le esegue il normale
motore delle Operazioni, a costo zero.

I mazzi Asset e Campaign ci sono: le 30 carte Asset dei Reclaimer e le 12
Campaign del Red Dust sono state lette dal modulo Vassal e sono in gioco — mano
da 6, pagamento delle Operazioni scartando carte (col valore maggiorato quando la
carta nomina quell'Operazione), scarti per anticipare il turno, Capability che
restano in gioco, rimescolamento al Dust Storm Round.

Fase 4 — Tutte e 11 le Operazioni e tutte e 12 le
Attività Speciali sono implementate e testate; in interfaccia sono utilizzabili
quelle che si pianificano scegliendo solo gli spazi (Train, Assault, Rally,
Attack, Campaign, Preach), mentre quelle di movimento (Secure, Recon, March,
Travel, Logistics) hanno le regole pronte ma aspettano il pianificatore di
movimento in UI.

Fase 3 — Oltre alla mappa renderizzata, il mazzo si
costruisce come da regolamento e le carte scorrono: ordine di Eligibility letto
dalla carta, Passo con i bonus di ciascuna Fazione, traccia Flashpoint, Flashpoint
Round e Dust Storm Round completi, tempeste tirate coi due dadi, check di vittoria
e fine partita al terzo Dust Storm. Manca ancora il cuore del gioco: Operazioni,
Attività Speciali ed effetti degli Eventi — quindi per ora l'unica azione
disponibile in UI è il Passo.

**1037 test del modulo + 158 controlli di smoke test della scena, 0 falliti.**

| Componente | Stato |
| --- | --- |
| Motore COIN multi-gioco (`GameRegistry` + `Manifest`) | ✅ riusato da ABB |
| Mappa di Mars (5175×3775 dal Vassal) + 24 poligoni | ✅ `regions.json` |
| 23 spazi + Wilderness + Aldrin Cycler/Orbit | ✅ tipo, Popolazione, Settore, dadi tempesta |
| Adiacenze (bordi neri/blu, Wilderness, Maglev) | ✅ verificate sui poligoni e sulla tavola stampata |
| 5 Fazioni (4 giocabili + EarthGov) e 11 tipi di pezzo | ✅ inventari verificati contro le Faction mat |
| 51 carte Evento (titolo, Flashpoint, ordine, testi) | ✅ estratte dal Playbook |
| Schieramento standard §3.1 | ✅ i 7 marcatori dell'Edge Track tornano esatti |
| Controllo di coalizione COIN §1.9 | ✅ |
| Traccia EG Confidence §1.2 (9 caselle, Controller) | ✅ |
| Vittoria §2.0 (4 metriche + soglia dinamica CR) | ✅ |
| Mappa renderizzata + 30 zone cliccabili | ✅ 24 su Mars + Aldrin Cycler/Orbita |
| Pezzi sulla mappa (67 su Mars + 18 fuori) | ✅ texture del Vassal, Nascosto/Attivo, lati potenziati |
| Marker Supporto/Opposizione e Controllo | ✅ sulle caselle 'Neutral' stampate (coordinate Vassal) |
| Tracciati: Edge Track, EG Confidence, Flashpoint | ✅ marcatori dentro le caselle stampate |
| Cilindri della Sequence of Play | ✅ nelle 9 caselle, si muovono durante la carta |
| Campaign e Capability in gioco, sui riquadri della plancia | ✅ fronti importati dal Vassal |
| Carte Evento in vista (corrente + prossima) | ✅ anteprime cliccabili, ingrandimento a schermo intero |
| Spostamenti a trascinamento sulla mappa | ✅ con le frecce di anteprima |
| Zoom e scorrimento (rotellina, pinch, +/−/0, trascinamento) | ✅ fino a 5× |
| Riga di istruzioni sopra la mappa | ✅ dice sempre di chi è il turno e cosa fare |
| Annulla l'ultima azione | ✅ 25 passi, col nome di ciò che si disfa |
| Salvataggio e ripresa | ✅ stato + carta in corso (`user://partita.json`) |
| Tema unico dei comandi | ✅ `RDRTheme` |
| Anteprima di costo ed effetti prima di eseguire | ✅ simulata su una copia dello stato |
| Schermata iniziale | ✅ `MainMenu.tscn` (nuova partita, seme, ruoli, riprendi) |
| Partita in solitario dall'app | ✅ si sceglie chi è Giocatore e chi Non-Player |
| Salvataggio automatico a ogni cambio carta | ✅ `user://autosave.json` |
| Tooltip di regole sulle Operazioni | ✅ una riga per Operazione, col paragrafo |
| Lampeggio degli spazi toccati da un'azione | ✅ |
| Pannello di stato + dettaglio spazio | ✅ |
| Mazzo §3.3 (3 pile da 12, Dust Storm in fondo) | ✅ 39 carte |
| Event Round §4.1 (ordine, 1ª/2ª, Passo, LimOp) | ✅ incluse le deviazioni RDR |
| Scarto Asset dei Reclaimer per anticipare il turno | ✅ |
| Traccia Flashpoint e Haboob | ✅ |
| Flashpoint Round §4.2 (8 fasi) | ✅ |
| Dust Storm Round §4.3 (5 fasi) + fine partita | ✅ |
| Tempeste §3.2 (tabella d6 bianco/nero, max 6) | ✅ |
| Operazioni §5.0 (tutte e 11) | ✅ regole complete e testate |
| Attività Speciali §6.0 (tutte e 12) | ✅ regole complete e testate |
| House / Repair / Pacify / Agitate §1.7 | ✅ |
| Movimento: adiacenza, Maglev, Spaceport, tempeste | ✅ |
| UI: tutte e 11 le Operazioni | ✅ con pianificatore di movimento per Secure/Recon/March/Travel |
| UI: tutte e 11 le Attività Speciali | ✅ Transport e Ambush comprese |
| 30 carte Asset + 12 Campaign (dati) | ✅ lette dal Vassal |
| Mano, pagamento, Capability, rimescolamento §1.5 | ✅ i Reclaimer pagano davvero |
| Partita riproducibile con un seme | ✅ `new_game(scenario, seed)` |
| Eventi §7.0: effetti delle carte | ✅ 93 opzioni su 93, scritte a mano |
| Eventi: scelte dei giocatori (spazi, Fazioni, rami) | ✅ dichiarate dalla carta e raccolte in UI |
| Eventi: Operazioni gratuite concesse | ✅ in coda, eseguite a costo zero |
| Eventi: «Ineligible» / «remains Eligible» | ✅ applicati alla chiusura della carta |
| Effetti continuativi delle 12 Campaign card | ✅ tutte attive sulle regole |
| Capability delle Asset card (10) | ✅ agganciate a Operazioni e Attività Speciali |
| Eventi delle Asset card (10) | ✅ stessa libreria degli Eventi §7.0 |
| Mano dei Reclaimer giocabile in UI | ✅ Capability ed Eventi dal pannello |
| Non-Player *Curiosity*: motore (§8.2/§8.4/§8.5) | ✅ contatori, Eligibility CR, Activation Number, selettore di spazi |
| Non-Player: Space Selection Priorities | ✅ tutte e 4 le tabelle |
| Non-Player: Piece Priorities §8.5.8 | ✅ tabella e selettore dei pezzi |
| Non-Player: Move Priorities §8.5.7 | ✅ Keep/Get e scelta dell'origine |
| Non-Player: Eligibility Table §8.5.2 | ✅ decide Evento / Op+SA / Limitata / Passo |
| Non-Player: turno completo (Eligibility → carta → Operazione) | ✅ `GameController.np_take_turn()` |
| Non-Player: Rally, Attack, Campaign, Preach | ✅ uno spazio alla volta |
| Non-Player: Secure, Recon, March, Travel | ✅ ciclo A/B/C con Keep e Get |
| Non-Player: Train, Logistics e Assault | ✅ tutte e 11 le Operazioni agiscono |
| Non-Player: Attività Speciali | ✅ 9 su 12 (restano Ambush e Transport) |
| Non-Player: Effective Events §8.5.5 | ✅ calcolati dagli effetti scomposti |
| Non-Player: simboli ★/⊘ sulle carte Evento | ✅ estratti dalle immagini e verificati a vista |
| Non-Player: gioca gli Eventi | ✅ sceglie l'opzione che gli giova |
| Non-Player: Event Instructions §8.5.5 | ✅ 25 carte + 6 Asset, con le condizioni |
| Non-Player: 24 carte *Curiosity* | ✅ tutte e 48 le facce, con l'interprete |
| Interazione di gioco (scelta azioni) | ⬜ dopo Operazioni e round |

## Struttura

```
sources/          Materiali sorgente
  rules/          PDF ufficiali (regolamento, playbook, non-player, FAQ, player aid)
                  + estrai_carte_rdr.py  (carte Evento dal Playbook)
                  + estrai_effetti_eventi.py (superato: gli effetti degli Eventi
                    ora sono scritti a mano in data/event_effects.json)
  vassal/         Modulo Vassal 1.0 scompattato (buildFile.xml + images/)
                  + estrai_zone_rdr.py   (poligoni e tracciati dalla tavola)
godot/            Progetto Godot 4
  coin_engine/    Motore COIN generico (condiviso con Cuba Libre e ABB)
  games/red_dust_rebellion/
    RDRModule.gd  Regole specifiche (Controllo, Popolazione, EG Confidence, Vittoria)
    Manifest.gd   Factory dei sottosistemi
    data/         spaces, factions, cards, setup, regions, board_layout (JSON)
    assets/       mappa, pezzi, marker, 51 carte Evento
  tests/          Test headless
docs/
  RULES_DIGEST.md Sintesi operativa del regolamento (il riferimento per implementare)
```

## Riprendere il lavoro

Chi subentra parta da [docs/HANDOFF.md](docs/HANDOFF.md): impianto, cosa
funziona, cosa manca e le trappole già pagate.

## Provarla nel browser

Non serve installare niente: **<https://tannoiser2.github.io/Red-Dust-Rebellion-GMT/>**

Sono ~65 MB da scaricare al primo accesso, poi resta in cache. L'export è senza
thread perché GitHub Pages non invia gli header COOP/COEP di
`SharedArrayBuffer`; la versione desktop resta più fluida.

## Primo avvio dopo il clone

La cache di import di Godot non è nel repository: va ricostruita una volta, o le
texture non si caricano e i test non partono.

```bash
godot --headless --path godot --editor --quit
```

## Eseguire i test

```bash
godot --headless --path godot -s res://tests/test_runner.gd
```

```bash
godot --headless --path godot -s res://tests/scene_smoke.gd
```

Lo smoke test monta davvero la scena. Con un renderer vero (cioè senza
`--headless`) salva anche uno screenshot:

```bash
godot --path godot -s res://tests/scene_smoke.gd -- --shot=/tmp/rdr.png
```

Alla prima esecuzione su una macchina nuova serve una passata di import per
generare la cache delle `class_name`:

```bash
godot --headless --path godot --editor --quit
```

## Costruire l'app macOS

Servono i template di esportazione della stessa versione di Godot (4.7).
L'esportazione produce un bundle universale (Intel + Apple Silicon) in
`dist/macos/`:

```bash
godot --headless --path godot --export-release "macOS" "../dist/macos/Red Dust Rebellion — Digital.app"
```

La firma va fatta **fuori dalla cartella sincronizzata**: se il repo sta in
`~/Documents` gestita da iCloud Drive, gli attributi estesi (`com.apple.macl`,
`com.apple.fileprovider.*`) rispuntano appena rimossi e `codesign` si rifiuta
("resource fork, Finder information, or similar detritus not allowed"). Si copia
quindi il bundle in una cartella non sincronizzata, lo si firma ad-hoc (senza
certificato di sviluppatore) e lo si installa:

```bash
ditto --norsrc --noextattr --noacl "dist/macos/Red Dust Rebellion — Digital.app" "/tmp/rdr/Red Dust Rebellion — Digital.app"
```

```bash
xattr -cr "/tmp/rdr/Red Dust Rebellion — Digital.app" && codesign --force --deep --sign - "/tmp/rdr/Red Dust Rebellion — Digital.app" && codesign --verify --deep --strict "/tmp/rdr/Red Dust Rebellion — Digital.app"
```

```bash
ditto --norsrc --noextattr --noacl "/tmp/rdr/Red Dust Rebellion — Digital.app" "/Applications/Red Dust Rebellion — Digital.app"
```

Essendo firmata solo ad-hoc, alla prima apertura macOS può chiedere conferma
(Ctrl-clic → Apri).

## Perché i dati sono affidabili

Popolazione, adiacenze, forze iniziali e regole di Controllo non sono state inserite
"a occhio": il test di setup ricalcola i sette marcatori che il regolamento stampa
sull'Edge Track a inizio partita — Supporto+EG 12, Opposizione+Basi 14, CR
Controllo+Basi 7, Basi nemiche 10, Profits 0, Risorse RD 14, Risorse MG 18 — e in
più verifica che per ogni tipo di pezzo `in gioco + disponibili` sia uguale
all'inventario stampato sulla Faction mat. Se uno di quei numeri fosse sbagliato, i
totali non tornerebbero.

## Note legali

**Red Dust Rebellion © 2024 GMT Games, LLC.** Progetto amatoriale e non
ufficiale, a scopo personale ed educativo, senza alcuna affiliazione con GMT
Games né scopo di lucro.

Il repository contiene due cose che vanno tenute distinte:

* **Il codice** (`godot/`, `docs/` e gli script di estrazione) è opera
  dell'autore di questo progetto.
* **Il materiale del gioco** — regolamento e Playbook in `sources/rules/`,
  immagini della mappa, delle carte e delle pedine in `godot/…/assets/`,
  estratte dal modulo Vassal — è **proprietà di GMT Games, LLC e dei rispettivi
  autori**, incluso qui come riferimento per la trascrizione delle regole. Non
  è concesso in licenza e non se ne autorizza il riuso.

Questa implementazione **non sostituisce il gioco**: non contiene le componenti
fisiche e non è pensata per chi non lo possiede. Se il gioco vi interessa,
compratelo da [GMT Games](https://www.gmtgames.com/). Su richiesta dei titolari
dei diritti il materiale sarà rimosso.

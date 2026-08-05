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

**674 test del modulo + 45 controlli di smoke test della scena, 0 falliti.**

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
| Tracciati: Edge Track, EG Confidence, Flashpoint, SoP | ✅ |
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
| UI: 9 Attività Speciali su 12 | ✅ Transport e Ambush restano da collegare |
| 30 carte Asset + 12 Campaign (dati) | ✅ lette dal Vassal |
| Mano, pagamento, Capability, rimescolamento §1.5 | ✅ i Reclaimer pagano davvero |
| Partita riproducibile con un seme | ✅ `new_game(scenario, seed)` |
| Eventi §7.0: effetti delle carte | ✅ 93 opzioni su 93, scritte a mano |
| Eventi: scelte dei giocatori (spazi, Fazioni, rami) | ✅ dichiarate dalla carta e raccolte in UI |
| Eventi: Operazioni gratuite concesse | ✅ in coda, eseguite a costo zero |
| Eventi: «Ineligible» / «remains Eligible» | ✅ applicati alla chiusura della carta |
| Effetti continuativi delle 12 Campaign card | ✅ tutte attive sulle regole |
| Capability delle Asset card | ⬜ in gioco ma ancora inerti |
| Non-Player *Curiosity* | ⬜ regolamento ancora da leggere |
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

Gli asset arrivano dal modulo Vassal e portano con sé attributi estesi di
Finder, che fanno fallire la firma: vanno ripuliti, poi si firma ad-hoc (senza
certificato di sviluppatore) perché Gatekeeper lasci aprire l'app in locale.

```bash
xattr -cr "dist/macos/Red Dust Rebellion — Digital.app" && codesign --force --deep --sign - "dist/macos/Red Dust Rebellion — Digital.app"
```

Poi basta copiare il bundle in `/Applications`. Essendo firmata solo ad-hoc,
alla prima apertura macOS può chiedere conferma (Ctrl-clic → Apri).

## Perché i dati sono affidabili

Popolazione, adiacenze, forze iniziali e regole di Controllo non sono state inserite
"a occhio": il test di setup ricalcola i sette marcatori che il regolamento stampa
sull'Edge Track a inizio partita — Supporto+EG 12, Opposizione+Basi 14, CR
Controllo+Basi 7, Basi nemiche 10, Profits 0, Risorse RD 14, Risorse MG 18 — e in
più verifica che per ogni tipo di pezzo `in gioco + disponibili` sia uguale
all'inventario stampato sulla Faction mat. Se uno di quei numeri fosse sbagliato, i
totali non tornerebbero.

## Note legali

Red Dust Rebellion © 2024 GMT Games, LLC. Progetto amatoriale a scopo
personale/educativo. Gli asset grafici e i testi originali sono proprietà di GMT
Games e dei rispettivi autori e non devono essere ridistribuiti senza autorizzazione.

# Red Dust Rebellion — Digital Edition

Edizione digitale (non ufficiale, amatoriale) di **Red Dust Rebellion**, il volume XII
della Serie COIN di GMT Games — la ribellione marziana del 2250.

Costruita riusando il **motore COIN generico** sviluppato per
[Cuba Libre](https://github.com/Tannoiser2/Cuba-Libre-GMT) e
[All Bridges Burning](https://github.com/Tannoiser2/All-Bridge-Burning): stessa
architettura `coin_engine/` + `games/<gioco>/`, così che il terzo titolo riusi
`GameRegistry`, `GameManifest`, `GameState`, `SpaceState` e la sequenza di gioco.

## Stato

🚧 **Fase 1 — dati e regole di base.** Mappa, spazi, fazioni, pezzi, carte Evento e
schieramento iniziale sono estratti dal modulo Vassal e dal regolamento, e validati
da test headless. Il motore calcola Controllo, Supporto/Opposizione, traccia
EarthGov Confidence e i quattro totali di vittoria.

**86 test passati, 0 falliti.**

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
| Operazioni / Attività Speciali | ⬜ da implementare |
| Round Flashpoint e Dust Storm | ⬜ da implementare |
| Eventi (effetti) | ⬜ testi presenti, effetti da implementare |
| Non-Player *Curiosity* | ⬜ regolamento ancora da leggere |
| Interfaccia Godot | ⬜ da portare (le scene ABB non sono ancora state adattate) |

## Struttura

```
sources/          Materiali sorgente
  rules/          PDF ufficiali (regolamento, playbook, non-player, FAQ, player aid)
                  + estrai_carte_rdr.py  (carte Evento dal Playbook)
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

Alla prima esecuzione su una macchina nuova serve una passata di import per
generare la cache delle `class_name`:

```bash
godot --headless --path godot --editor --quit
```

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

# Roadmap — Red Dust Rebellion Digital

Ordine pensato per avere sempre qualcosa di verificabile con i test headless, come
fatto su Cuba Libre e All Bridges Burning.

## Fase 1 — Dati e fondamenta ✅

- [x] Scaffolding del progetto riusando `coin_engine/` di ABB
- [x] Estrazione poligoni/tracciati dal modulo Vassal (`estrai_zone_rdr.py`)
- [x] Estrazione delle 51 carte Evento dal Playbook (`estrai_carte_rdr.py`)
- [x] `spaces.json` — 23 spazi + Wilderness + Aldrin Cycler, tipo, Popolazione,
      Settore, numeri per i tiri tempesta, adiacenze, linee Maglev
- [x] `factions.json` — 5 Fazioni, 11 tipi di pezzo, 9 caselle EG Confidence
- [x] `setup_standard.json` — schieramento §3.1
- [x] `RDRModule.gd` — Controllo di coalizione, Popolazione variabile, EG
      Confidence, totali di vittoria, bonus del Passo
- [x] 86 test headless
- [x] `docs/RULES_DIGEST.md`

## Fase 2 — Interfaccia ✅

- [x] Scene Godot scritte per la mappa di Mars (`Main.gd`, `RegionView.gd`,
      `TrackOverlay.gd`, `RDRAssets.gd`, autoload `GameController.gd`)
- [x] Render dei 24 poligoni con l'ordine di disegno del Vassal (Deserti sotto,
      Labirinti sopra: il clic nella zona di sovrapposizione va al Labirinto) e
      tinta del Controllo
- [x] Pezzi sulla mappa: cubi, esagoni Nascosti/Attivi, dischi con lato upgrade
- [x] Marker Supporto/Opposizione e Controllo sulle caselle stampate (`sbox`
      estratto dai SetupStack del Vassal)
- [x] Popolazione e Danno per spazio (badge sulla traccia Infrastruttura)
- [x] Edge Track (7 marcatori), EG Confidence (9 caselle ricostruite),
      Flashpoint, cilindri Sequence of Play
- [x] Aldrin Cycler (Earth / Transit / Phobos / Orbit) con i suoi 18 pezzi
- [x] Pannello di stato (vittoria, controllo, risorse) e dettaglio dello spazio
- [x] `tests/scene_smoke.gd`: monta la scena e sa salvare uno screenshot
- [ ] Zoom/pan sulla mappa e finestra delle carte (rimandati)

## Fase 3 — Sequenza di gioco

- [ ] Costruzione del mazzo §3.3 (3 pile da 12, Dust Storm nelle ultime 6)
- [ ] Event Round: ordine di Eligibility dalla carta, opzioni 1ª/2ª, Passo,
      Limited Operation, Desert Efficiency, marker Haboob
- [ ] Traccia Flashpoint e innesco del Flashpoint Round
- [ ] Flashpoint Round (§4.2), 8 fasi
- [ ] Dust Storm Round (§4.3), 5 fasi + check di vittoria
- [ ] Tempeste: tiri d6 bianco/nero, Approaching → Raging, limite di 6

## Fase 4 — Operazioni e Attività Speciali

- [ ] COIN: Train, Logistics, Secure, Recon, Assault (+ Drop Pods, Navigation
      Beacons, Bombard, Suppress per il Controller EarthGov)
- [ ] Ribelli: Rally, March, Travel, Attack, Campaign, Preach
- [ ] SA MarsGov: Entrench, Petition, Transport
- [ ] SA Corporations: Public Relations, Exploit, Raid
- [ ] SA Red Dust: Redistribute, Coordinate, Ambush
- [ ] SA Reclaimer: Purify, Ransack, Ambush
- [ ] House / Repair / Pacify / Agitate come azioni condivise

## Fase 5 — Carte

- [ ] Effetti dei 48 Eventi (testi già in `cards.json`)
- [ ] 30 Asset card (valore, Eventi, Capability) — testi da estrarre
- [ ] 12 Campaign card — testi da estrarre
- [ ] Simboli Non-Player ★/⊘ sulle carte (sottolineato/riquadrato nel Playbook)

## Fase 6 — Non-Player *Curiosity*

- [ ] Lettura del `RDR_Curiosity_NP_Rules_Booklet`
- [ ] Mazzo NP da 24 carte + aid sheet
- [ ] Bot per le quattro Fazioni

## Fase 7 — Rifiniture

- [ ] Integrazione della FAQ ufficiale
- [ ] Simulazioni di bilanciamento (come `sim_runner.gd` di ABB)
- [ ] Salvataggio/ripresa partita
- [ ] GitHub Actions: build desktop + export Web su GitHub Pages

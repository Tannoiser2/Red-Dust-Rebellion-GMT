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

## Fase 3 — Sequenza di gioco ✅

- [x] Costruzione del mazzo §3.3 (3 pile da 12, Dust Storm nelle ultime 7 di
      ciascuna, 12 Eventi fuori dal gioco) — `rules/Deck.gd`
- [x] Event Round: ordine di Eligibility dalla carta, opzioni 1ª/2ª (con la
      deviazione RDR: dopo Op+SA la 2ª può anche fare una Limitata), Passo coi
      bonus per Fazione, Desert Efficiency, scarto Asset dei Reclaimer per
      anticipare il turno — `rules/Sequence.gd`
- [x] Traccia Flashpoint, innesco del round, marker Haboob
- [x] Flashpoint Round (§4.2), 8 fasi — `rules/Rounds.gd`
- [x] Dust Storm Round (§4.3), 5 fasi + check di vittoria + fine partita al terzo
- [x] Tempeste: tabella d6 bianco/nero, Approaching → Raging, limite di 6 marker
- [x] UI: carta corrente/prossima, ordine di Eligibility, turno, pulsanti Passa e
      Concludi carta; il log mostra le fasi dei round
- [ ] Support Phase (Pacify / Lobby / Agitate): meccaniche pronte ma sono scelte
      dei giocatori, in attesa dell'interfaccia delle azioni
- [ ] Redeploy facoltativi (Truppe MG extra, Ribelli verso le proprie Basi, Basi
      CR nella Wilderness): automatizzati solo gli spostamenti obbligatori

## Fase 4 — Operazioni e Attività Speciali ✅ (regole) · ⬜ (UI di movimento)

- [x] COIN: Train, Logistics, Secure, Recon, Assault (+ Drop Pods, Navigation
      Beacons, Bombard, Suppress, Mercenaries e Attack gratuito di risposta)
- [x] Ribelli: Rally, March, Travel, Attack, Campaign, Preach
- [x] SA MarsGov: Entrench (con Truppe Fortificate che assorbono il Danno),
      Petition, Transport
- [x] SA Corporations: Public Relations, Exploit, Raid
- [x] SA Red Dust: Redistribute, Coordinate, Ambush
- [x] SA Reclaimer: Purify, Ransack, Ambush
- [x] House / Repair / Pacify / Agitate come azioni condivise (`rules/Actions.gd`)
- [x] Regole di movimento: un passo di adiacenza + salti Maglev/Spaceport, stop
      nei Labirinti sotto Controllo nemico, restrizioni delle tempeste
- [x] UI: barra delle Operazioni della Fazione di turno, selezione degli spazi
      candidati sulla mappa, Esegui/Annulla
- [x] Pianificatore di movimento in UI: destinazione, tipo di unità, origine
      (solo quelle legali) e quantità; gli spostamenti si accumulano e si
      eseguono insieme all'Operazione
- [x] Logistics in UI (potenziamento delle Basi nei Deserti scelti)
- [x] 9 Attività Speciali su 12 collegate alla UI con scelta degli spazi
- [ ] Transport, Raid con spostamento di SpecOps e Ambush: servono form dedicati
      (spostamenti fra spazi attivati, dadi scelti)
- [ ] Scelte fini nella UI: modalità del Rally, bersagli dell'Assault/Attack,
      Ambush, Pacify/Coordinate

## Fase 5 — Carte

- [x] 30 Asset card: valore, tipo (capability/event/resource), bonus per
      l'Operazione nominata, testi — letti dalle immagini del Vassal
- [x] 12 Campaign card: titoli ed effetti
- [x] Sistema mazzi (`rules/Cards.gd`): mano da 6, pagamento delle Operazioni
      scartando carte, scarti per anticipare il turno (con il bonus di #19/#22),
      Capability permanenti, pescate del Dust Storm Round, rimescolamento
- [x] Partita riproducibile: `GameController.new_game(scenario, seed)`
- [x] Interprete degli Eventi (`rules/Events.gd`) con effetti atomici: Profits,
      Risorse, EG+/EG−, Supply e Popolazione su Earth, spostamenti su spazi
      nominati o scelti, attivazione dei Ribelli
- [x] Estrazione conservativa degli effetti dai testi
      (`sources/rules/estrai_effetti_eventi.py`): un'opzione è automatica solo se
      OGNI sua frase è riconosciuta — **6 opzioni su 93**
- [x] UI: pulsanti Evento / Evento ombreggiato, con il testo nel tooltip; ciò che
      non è automatico finisce nel Log come "da risolvere al tavolo"
- [ ] Libreria di effetti scritti a mano per le 87 opzioni restanti — è l'unico
      modo per automatizzarle: quasi tutte richiedono scelte di spazi, pezzi o
      Operazioni gratuite
- [x] Effetti continuativi di tutte e 12 le Campaign card, agganciati alle
      regole: Basi RD già Dug-In (#1), Profits erosi dalle Basi CORP (#2),
      Supply scartate o ripartite (#3/#8), Maglev vietati al Secure (#4),
      Labirinti bloccati al Supporto Passivo (#5), Assault che sposta verso
      l'Opposizione (#6), unità CORP escluse dal Controllo nei Labirinti (#7),
      costi maggiorati per MarsGov (#9/#10), Transit e Aldrin Cycler bloccati
      (#11), Supporto Passivo che salta il Neutrale (#12)
- [ ] Effetti degli Eventi e delle Capability sulle Asset card
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

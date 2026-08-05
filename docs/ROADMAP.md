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
- [x] Carte in vista: anteprime della carta in corso e della prossima nel
      pannello, con ingrandimento a schermo intero (le 51 immagini del Vassal)
- [x] Marcatori dei tracciati DENTRO le caselle stampate, a griglia quando più
      marcatori condividono la stessa casella
- [x] Cilindri della Sequence of Play nelle 9 caselle vere (`action_box`), non
      più solo Disponibile/Non Disponibile
- [x] Spostamenti a trascinamento dei pezzi, con le frecce sulla mappa
      (`MovesOverlay`) e la lista degli spostamenti dichiarati
- [x] Zoom e scorrimento della mappa: rotellina, gesto magnify, +/−/0,
      trascinamento col tasto destro; lo zoom è una scala sul nodo mappa, così
      pedine e marcatori ingrandiscono insieme alla tavola
- [x] Riga di istruzioni sopra la mappa: di chi è il turno, cosa si sta
      pianificando, quante Operazioni gratuite sono in sospeso
- [x] Tema unico dei comandi (`RDRTheme`), applicato come risorsa `Theme` alla
      scena: vale anche per i tasti creati al volo a ogni turno
- [x] Annulla l'ultima azione (25 passi) con il nome di ciò che si disfa
- [x] Salvataggio e ripresa (`user://partita.json`): stato + sequenza della
      carta in corso, dal menu «Partita…»
- [x] Anteprima di costo ed effetti: l'azione in preparazione viene simulata su
      una COPIA dello stato e il pannello dice quanto costa e cosa cambierebbe,
      prima di premere «Esegui»
- [x] Schermata iniziale come scena a sé (`MainMenu.tscn`): nuova partita,
      seme per rigiocarla identica, ripresa del salvataggio o dell'autosalvataggio
- [x] Salvataggio automatico a ogni cambio carta (`user://autosave.json`)
- [x] Tooltip di regole sulle Operazioni, col paragrafo del regolamento
- [x] Lampeggio degli spazi toccati da un'azione o da uno spostamento
- [ ] Restano da Cuba Libre: animazioni dei pezzi che si spostano davvero da
      uno spazio all'altro (qui c'è solo il lampeggio), scelta dei ruoli
      giocatore/bot nel menu (serve prima il Non-Player *Curiosity*)

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
- [x] Interprete degli Eventi (`rules/Events.gd`): vocabolario di effetti atomici
      (tracciati, Supporto/Opposizione, Danno, pezzi, House/Repair, tempeste,
      carte, Eligibility), filtri sugli spazi, quantità calcolate e condizioni
- [x] Modello delle scelte: ogni opzione dichiara `choices` (spazi, Fazione,
      ramo di un "either/or"); quelle non fornite dal chiamante si riempiono coi
      candidati legali, così l'Evento è sempre risolvibile per intero
- [x] **Libreria di effetti scritti a mano per tutte e 93 le opzioni** delle 48
      carte (`data/event_effects.json`): l'estrazione automatica dai testi
      (`sources/rules/estrai_effetti_eventi.py`, 6 opzioni su 93) è superata e
      scrive ora su un file che il gioco non legge
- [x] Operazioni gratuite concesse dagli Eventi: registrate in
      `pending_free_ops` ed eseguite dal motore delle Operazioni con `free`
      (niente Risorse, niente Asset card), con gli effetti "a seguire"
      (`apply_after`) per le clausole del tipo "poi Nascondi tutti i Ribelli"
- [x] "Ineligible through the next Event Round" e "remains Eligible": applicati
      da `RDRSequence.finish()` alla chiusura della carta
- [x] UI: i pulsanti Evento / Evento ombreggiato aprono la raccolta delle scelte
      una alla volta (spazi sulla mappa, Fazioni e rami con i pulsanti della
      barra); le Operazioni gratuite in sospeso compaiono come pulsanti «★»
- [x] Effetti continuativi di tutte e 12 le Campaign card, agganciati alle
      regole: Basi RD già Dug-In (#1), Profits erosi dalle Basi CORP (#2),
      Supply scartate o ripartite (#3/#8), Maglev vietati al Secure (#4),
      Labirinti bloccati al Supporto Passivo (#5), Assault che sposta verso
      l'Opposizione (#6), unità CORP escluse dal Controllo nei Labirinti (#7),
      costi maggiorati per MarsGov (#9/#10), Transit e Aldrin Cycler bloccati
      (#11), Supporto Passivo che salta il Neutrale (#12)
- [x] **Capability delle 10 Asset card** agganciate alle regole: Attack che
      colpisce di più (#1) e abbatte Satelliti ovunque (#26), tempeste ignorate
      (#2), Ribelle che rientra dopo l'Assault (#3), Purify potenziato (#4),
      Rally senza Base (#5), Bombard che non tocca i Reclaimer (#6), Satelliti
      che contano come Base (#23), Ransack che erode Risorse o Profits (#24),
      Secure/Recon depistati dalle Basi CR (#25)
- [x] **Eventi delle 10 Asset card** in `data/asset_effects.json`, scritti con la
      stessa grammatica delle carte Evento e risolti dalla stessa macchina
- [x] Mano dei Reclaimer giocabile dal pannello
- [ ] Simboli Non-Player ★/⊘ sulle carte (sottolineato/riquadrato nel Playbook)
- [ ] Scelte fini dentro le Operazioni gratuite: l'Evento le mette in coda con
      gli spazi già fissati, ma bersagli, dadi dell'Ambush e modalità del Rally
      usano ancora i piani minimi della UI

## Fase 6 — Non-Player *Curiosity*

- [x] Lettura del `RDR_Curiosity_NP_Rules_Booklet` (32 pagine)
- [x] Space Selection Priorities: **tutte e 4 le tabelle** in
      `data/np_priorities.json` — NP Red Dust, NP Reclaimers e NP CORP trascritte
      dal libretto renderizzato a 600 DPI, NP MarsGov dalla scansione della
      scheda del gioco fisico
- [x] Motore NP (`rules/NonPlayer.gd`): contatori surrogati (Supply Total per MG,
      Agitate Total per RD, Asset Total per CR al posto della mano), procedura di
      Eligibility dei Reclaimer a 3d6, Activation Number con le sue eccezioni e
      con la conversione dei tiri falliti, selettore di spazi guidato dalle
      priorità che spiega anche perché ha scelto così
- [x] **Piece Priorities** (§8.5.8) in `data/np_piece_priorities.json` e nel
      motore: quale pezzo si tocca per primo per piazzare, muovere, rimuovere o
      Attivare — con la lettura rovesciata per i pezzi propri e la regola che
      mette i pezzi dei giocatori davanti a quelli delle Fazioni NP
- [x] **Move Priorities** (§8.5.7) trascritte in `data/np_move_priorities.json`:
      passi A/B/C per Fazione, 11 istruzioni «keep in origin», 17 «move to
      destination»
- [x] Motore di movimento NP (`rules/NonPlayerMove.gd`): «Keep» e «Get» del
      glossario applicati alla lettera (lascia/muovi appena quanto basta,
      contando ciò che c'è già), scelta dell'origine col criterio delle forze
      muovibili, condizioni in rosso della tabella, scelta dei pezzi con le
      Piece Priorities. `RDROperations.legal_origins()` è salita dalle scene alle
      regole perché la usano entrambi
- [x] **Eligibility Table** (§8.5.2) in `data/np_eligibility.json` e nel motore:
      decide se la Fazione NP gioca l'Evento, fa Operazione (+ Attività Speciale),
      una Limitata o passa. Le condizioni su Critical/Performed/effective
      arriveranno da Effective Events ed Event Instructions; finché mancano la
      tabella cade sull'ultima riga e `degraded` lo dichiara
- [x] Ciclo A/B/C completo del movimento e collegamento a Secure, Recon, March e
      Travel, con i tiri di Activation Number fra una coppia e l'altra
- [x] **Turno completo di una Fazione NP** (`GameController.np_take_turn()`):
      Eligibility → pescata della carta Curiosity → lettura dell'albero →
      esecuzione, con tutto il ragionamento nel Log
- [x] Mazzo Curiosity per Fazione, che gira a ciclo continuo come da §8.9
- [x] Istruzioni di Train (col Pacify), Logistics (Basi, acquisti su Earth,
      Aldrin Cycler, Security) e Assault (nelle sue due varianti, con Suppress e
      Bombard nel piano): **tutte e 11 le Operazioni NP agiscono**
- [x] Attività Speciali delle Fazioni NP: «Select 1 Special Activity» prende la
      prima dell'elenco che abbia effetto — Purify, Ransack, Coordinate,
      Redistribute, Entrench, Petition, Public Relations, Exploit, Raid
- [ ] Ambush e Transport: vanno intrecciate, non aggiunte — la prima modifica
      l'Attack mentre lo si risolve, il secondo è un'Operazione di movimento
- [ ] Transport e Raid (Attività Speciali di movimento)
- [x] Interprete delle carte *Curiosity* (§8.5.3) e **tutte e 48 le facce**
      delle 24 carte in `data/np_cards.json`: riquadri in cima con sì/no verso
      «pesca» o «gira», bivi, blocchi di istruzioni e Attività Speciali. Gli `id`
      delle istruzioni puntano alle funzioni di `NonPlayerOps.gd`
- [ ] Da trascrivere: Effective Events, Event Instructions, Capability &
      Campaign Effects, istruzioni NP di Flashpoint e Dust Storm Round
- [x] Libreria delle istruzioni §8.6 (`rules/NonPlayerOps.gd`): Rally (piazza
      Basi, piazza Ribelli, rimetti Nascosti, Dig-In), Attack nelle sue tre
      varianti, Campaign e Preach — eseguite **uno spazio alla volta**, con il
      tiro di Activation Number fra uno e l'altro, così le priorità rileggono la
      plancia come al tavolo
- [ ] Operazioni di movimento NP (Secure, Recon, March, Travel, Transport,
      Raid): bloccate, serve la tabella Move Priorities
- [ ] Attività Speciali §8.7 senza movimento (Redistribute, Coordinate, Purify,
      Ransack, Exploit, Public Relations, Entrench, Petition)
- [ ] Round di Flashpoint e Dust Storm per le Fazioni NP (§8.5.9)
- [ ] L'esempio di gioco del libretto (§8.9, 12 pagine, setup e tiri noti) come
      test di regressione del sistema

## Fase 7 — Rifiniture

- [ ] Integrazione della FAQ ufficiale
- [ ] Simulazioni di bilanciamento (come `sim_runner.gd` di ABB)
- [ ] Salvataggio/ripresa partita
- [ ] GitHub Actions: build desktop + export Web su GitHub Pages

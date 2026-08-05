# Red Dust Rebellion — sintesi operativa del regolamento

Riferimenti: `sources/rules/RDR_Rule+Booklet_1E_Web.pdf` (Rulebook 1E),
`RDR_Play+Booklet_1D_Web.pdf` (Playbook: tutorial + testo di tutte le carte),
`RDR_Curiosity_NP_Rules_Booklet_1D_Web.pdf` (Non-Player *Curiosity*),
`Red_Dust_cheat_sheets.pdf`, `Sector_and_Space_Locator.pdf`,
`Official Red Dust Rebellion FAQ and Clarifications.pdf`.

I numeri di sezione fra parentesi sono quelli del Rulebook.

---

## 0. Che cosa cambia rispetto agli altri COIN già implementati

Questo è il punto più importante: RDR **non** è un COIN standard. Le differenze
strutturali rispetto a Cuba Libre e All Bridges Burning:

| Aspetto | COIN "classico" | Red Dust Rebellion |
| --- | --- | --- |
| Controllo | una Fazione > somma di tutte le altre | **coalizione COIN** (MarsGov+CORP+EarthGov) contro tutti i Ribelli; RD e CR controllano individualmente (§1.9) |
| Popolazione | fissa, stampata | **variabile**: marker Popolazione e Danno sulla traccia Infrastruttura (§1.7) |
| Round periodico | Propaganda / Coup | **due** round distinti: Flashpoint (frequente, §4.2) e Dust Storm (3 in tutta la partita, §4.3) |
| Fine partita | dopo l'ultima Propaganda | dopo il **terzo** Dust Storm Round |
| Risorse | una traccia per Fazione | MarsGov e RD hanno Risorse; CORP ha **Profits**; i Reclaimer pagano **scartando Asset card** (§1.4/§1.5) |
| Fazione extra | — | **EarthGov**: non-giocante, senza vittoria, guidata dal *Controller* (MarsGov o CORP) secondo la traccia EG Confidence (§1.2) |
| Terreno | province/città | **Labirinti** (cerchi, con Spaceport) e **Deserti** (irregolari, con Stazioni per le Basi) + Wilderness |
| Ostacoli | — | **Dust Storm** che bloccano operazioni e movimento (§1.10) |

---

## 1. Mappa (§1.2)

* **3 Settori popolati**: Tharsis Montes (anello esterno 6 Deserti + anello interno
  4 Labirinti e 2 Deserti), Arabia Terra (2 Labirinti + 4 Deserti), Hellas Planitia
  (2 Labirinti + 3 Deserti) → **23 spazi**, più **The Wilderness** (Deserto sempre
  spopolato, limite 6 Basi).
* **Aldrin Cycler**: Earth → Transit → Phobos. Non adiacenti a nulla e fra loro.
  **Orbit** ospita i Satelliti. Phobos è un Labirinto sempre sotto Controllo COIN,
  mai Danneggiabile, vietato ai Ribelli, senza Basi.
* **Adiacenza**: spazi che condividono un bordo nero o blu (Maglev). La Wilderness
  è adiacente a **tutti i Deserti che toccano il bordo del proprio Settore** (13
  spazi: tutti tranne Pavonis Mons e Syria Planum, interni a Tharsis); **nessun
  Labirinto** è adiacente alla Wilderness.
* **Maglev** (5 linee, solo fra Labirinti dello stesso Settore): Europa–Tenzing,
  Tenzing–Shepard, Shepard–Tereshkova, New Córdoba–Shenzhou, e
  **Europa–Tereshkova tratteggiata** (Rodgers Line): inutilizzabile finché non si
  gioca l'Evento **#14 non ombreggiato**.
* **Spaceport**: casella verde più a destra di ogni Labirinto (tutti gli 8 +
  Phobos). Inutilizzabile se coperta da un Danno.
* **Edge Track** 0–50 lungo il bordo alto: Risorse MG/RD, Profits, e i marcatori di
  vittoria di tutte le Fazioni.

Popolazione stampata (totale **33**): Tenzing e Shenzhou 3; Europa, Tereshkova,
Shepard, New Córdoba, Gandhi, Sharma 2; tutti i 15 Deserti settoriali 1;
Wilderness e Phobos 0.

**Numeri Dust Storm** (d6 bianco = Settore, d6 nero = spazio):
1/2 Arabia Terra · 3 Tharsis esterno · 4 Tharsis interno · 5/6 Hellas Planitia.
Hellas Chaos occupa i risultati 3 **e** 4.

---

## 2. Pezzi (§1.3)

| Pezzo | Fazione | Inventario | Note |
| --- | --- | --- | --- |
| MG Troops (cubi blu) | MarsGov | 30 | |
| MG Bases (dischi blu) | MarsGov | 3 | |
| Security (cubi neri) | CORP | 16 | |
| SpecOps (esagoni neri) | CORP | 8 | Nascosti/Attivi |
| CORP Bases (dischi neri) | CORP | 9 | lato *Terraforming* |
| EG Troops (cubi bianchi) | EarthGov | 16 | contano come forze del Controller |
| Satelliti | EarthGov | 6 | **non contano per il Controllo**, ma sono forze EG |
| RD Rebels (esagoni rossi) | Red Dust | 30 | Nascosti/Attivi |
| RD Bases (dischi rossi) | Red Dust | 9 | lato *Dug-In* (solo Deserti) |
| CR Rebels (esagoni arancio) | Reclaimer | 20 | Nascosti/Attivi |
| CR Bases (dischi arancio) | Reclaimer | 15 | lato *Conversion Center* |

* **Nascosto/Attivo**: Ribelli e SpecOps si piazzano **sempre** Nascosti, anche
  quando sostituiscono un altro pezzo. Basi, Satelliti, Truppe e Security sono
  sempre Attivi.
* **Stacking Basi**: 2 per Deserto/Labirinto, 6 nella Wilderness, 0 su Phobos.
* Le forze si piazzano **solo** dalle Disponibili. Se MarsGov / RD / CR non hanno
  Truppe o Ribelli disponibili possono rimuoverne di propri dalla mappa per
  ripiazzarli altrove (mai CORP, EG o Basi).
* **Amici/Nemici** (§1.1): MarsGov, CORP ed EarthGov sono sempre amici (le Basi
  COIN si proteggono a vicenda); Red Dust e Reclaimer sono nemici di tutti,
  **fra loro compresi**, e non si proteggono le Basi.

---

## 3. Popolazione, Danno, Supporto (§1.7, §1.8)

* Traccia **Infrastruttura**: 2 caselle nei Deserti, 4 nei Labirinti. Quadrati
  **verdi** = Popolazione; **grigi** = spazio per marker Popolazione.
* **House**: sposta un marker Popolazione da *Displaced Population* in un quadrato
  grigio (spazio senza Danno). MarsGov → EG+; Red Dust → EG−; CORP → EG+ o EG− a
  scelta.
* **Repair**: rimuove un Danno, consumando un marker da Displaced Population.
  MarsGov costa 3 Risorse (→EG+); Red Dust 2 Risorse (→EG−); CORP rimuove una
  Security nello spazio (→EG+ o EG−).
* **Danno**: rimuove prima i marker Popolazione gialli, poi copre il quadrato
  verde più a destra (−1 Popolazione) e aggiunge **1** marker a Displaced Population.
* **Supporto/Opposizione**: 5 livelli. Passivo = 1 punto per Popolazione, Attivo = 2.
  Gli spazi con Popolazione 0 sono sempre Neutrali.

---

## 4. Controllo (§1.9)

* **COIN Control**: forze (MarsGov + CORP + EarthGov) **>** forze Ribelli (RD + CR).
* **RD / CR Control**: le proprie forze **>** tutte le altre sommate (COIN + l'altro
  Ribelle).
* I Satelliti non contano. Phobos è sempre COIN.

---

## 5. Traccia EarthGov Confidence (§1.2)

Nove caselle, dal basso verso l'alto (valore · Controller · EG Troops/Supply/Pop
aggiunti su Earth durante il Flashpoint):

| # | Valore | Controller | EG Troops | Supply | Pop |
| --- | --- | --- | --- | --- | --- |
| 8 | 10 | MarsGov | 0 | 3 | 3 |
| 7 | 8 | MarsGov | 1 | 3 | 2 |
| 6 | 6 | MarsGov | 2 | 2 | 2 |
| 5 | 4 | CORP | 3 | 2 | 1 |
| 4 | 2 | CORP | 4 | 2 | 1 |
| 3 | 1 | CORP | 4 | 1 | 1 | ← **setup**, lato EG− |
| 2 | 1 | CORP | 6 | 1 | 0 |
| 1 | 0 | CORP | 6 | 1 | 0 |
| 0 | 0 | — | — | — | — | *No Controller* |

* Il marcatore è bifacciale **EG+/EG−**: "set to EG+/EG−" ne gira la faccia; nel
  Flashpoint sale di una casella se EG+, scende se EG−.
* Il **valore** si somma al totale di vittoria MarsGov.
* Il **Controller** usa le Truppe EG come proprie e i Satelliti per potenziare
  Secure (Drop Pods), Recon (Navigation Beacons) e Assault (Bombard/Suppress).
* Se il marcatore raggiunge il fondo: tutte le Truppe EG dalla mappa a Disponibili,
  tutti i Satelliti in Orbit su Earth; nessun pezzo EG può essere piazzato su Mars.

---

## 6. Dust Storm (§1.10)

* **Approaching Storm**: nessun effetto intrinseco, segnala dove colpirà.
* **Raging Storm**:
  * **Deserto**: non selezionabile per Operazioni, Attività Speciali o Eventi.
  * **Labirinto**: selezionabile, ma le forze **non** possono entrarvi né uscirne
    (si possono comunque piazzare dalle Disponibili).
  * Le forze non possono entrare/uscire da aree in tempesta.
* Il **Travel** dei Reclaimer ignora completamente le tempeste.
* Massimo 6 marker tempesta sulla mappa.

---

## 7. Sequenza di gioco (§4.0)

Sono visibili due carte: **Current Event** e **Next Event**.

1. Quando si rivela la Next Event, la traccia **Flashpoint** avanza del valore del
   fulmine (0–4). A 5 (simbolo fulmine finale) si esegue subito un **Flashpoint
   Round** e la traccia torna a 0.
2. I Reclaimer possono scartare fino a 3 Asset card per **avanzare** di altrettante
   posizioni nell'ordine di Eligibility stampato (sono sempre ultimi).
3. Fino a **due** Fazioni Eligible agiscono nell'ordine stampato sulla carta.
4. Si aggiusta l'Eligibility, la Next Event diventa Current Event e si rivela la
   nuova Next Event. Se la nuova Current Event è una **Dust Storm**, si esegue
   subito il **Dust Storm Round** senza rivelare la Next Event.

**Opzioni della 1ª Eligible**: Operazione (senza SA) · Operazione + Attività
Speciale · Evento · (Reclaimer) Evento su una propria Asset card.

**Opzioni della 2ª Eligible**, in base a quanto fatto dalla 1ª:

| 1ª ha fatto | 2ª può |
| --- | --- |
| Operazione senza SA | solo **Limited Operation** |
| Operazione + SA | Limited Operation **oppure** Evento |
| Evento | Operazione (con SA se vuole) |

**Passare**: si resta Eligible. MarsGov +3 Risorse · CORP deve attivare l'Aldrin
Cycler · Red Dust +1 Risorsa · Reclaimer pescano 1 Asset card.

**Limited Operation** = Operazione in **un solo** spazio, senza SA (Secure/Recon/
March possono partire da più origini ma con una sola destinazione).
**Desert Efficiency**: se i Reclaimer sono 2ª Eligible e scelgono la Limited
Operation, possono selezionare più spazi ma pagare con **una sola** Asset card, e
poi pescano una carta.

**Haboob**: quando una Dust Storm è visibile come Next Event, si mette il marker
Haboob sulla Current Event: **Recon e March vietati** in quel round.

---

## 8. Flashpoint Round (§4.2)

1. **Aldrin Cycler** — Transit → Phobos; Popolazione su Phobos → Displaced;
   Satelliti su Phobos → Orbit; ogni Supply su Phobos = **+3 Risorse MarsGov**, poi
   rimosso. Poi 1 Popolazione da Earth a Transit (max 1 alla volta) e **5 altri
   pezzi** scelti dal Controller da Earth a Transit (nessuno se non c'è Controller).
   CORP può spendere Profits (1 per pezzo) per mandarne altri.
2. **Corporate Casualties** — −1 Profit per Base CORP e −1 ogni 2 Security nelle
   Casualties (SpecOps no); poi tutte le forze CORP tornano Disponibili.
3. **EarthGov Confidence** — Satelliti su Mars → Orbit; la traccia sale/scende di
   una casella secondo EG+/EG−; poi si aggiungono su Earth Truppe/Supply/Popolazione
   secondo la nuova casella.
4. **Terraforming** — +2 Profits per la prima Base Terraforming di ciascun Deserto,
   +1 per ogni ulteriore; −1 Profit per ogni Conversion Center in un Deserto.
5. **Dust Storms** — si rimuovono le Raging, le Approaching diventano Raging, poi
   si tira per nuove tempeste tante volte quanto il Flashpoint della Next Event
   (stop a 6 marker sulla mappa).
6. **Attrition** — nei Deserti Spopolati o in tempesta: senza Base COIN si rimuove
   1 MG Troop e 1 Security; senza Base RD si rimuove 1 RD Rebel. **EG Troops,
   SpecOps e CR Rebels non sono mai colpiti.**
7. **Conversion** — in ogni spazio Popolato con un Conversion Center si piazza 1 CR Rebel.
8. **Reset** — Flashpoint a 0.

---

## 9. Dust Storm Round (§4.3)

1. **Victory Phase** — Corporate Casualties; EarthGov Casualties (−1 EG Confidence
   per Satellite e ogni 2 EG Troops nelle Casualties); Displaced Population penalty
   (ogni 2 marker: −3 Risorse MarsGov e −1 Profit); **check di vittoria**.
2. **Resources** — MarsGov: +Popolazione totale degli spazi con Controllo COIN e
   senza Opposizione · CORP: +2 per Base CORP in un Labirinto · Red Dust:
   +Popolazione in Opposizione Attiva **+ Basi RD** · Reclaimer: pescano 1 Asset per
   ogni simbolo scoperto sulla traccia Basi Disponibili, poi scartano fino a 6.
3. **Support** — *Pacify*: in ogni spazio con Controllo COIN MarsGov fa fino a 2 fra
   House / Repair / 3 Risorse per 1 livello verso Supporto Attivo. *Lobby*: MarsGov
   può pagare 5 Risorse per +1 EG Confidence (una volta). *Agitate*: idem per Red
   Dust in ogni spazio con Controllo RD (1 Risorsa per livello verso Opposizione).
4. **Redeploy** — si rimuovono tutte le tempeste, poi: EG Troops su Mars → Phobos o
   spazi con Base MG · MG Troops da Deserti senza Base COIN → Labirinti con Controllo
   COIN o spazi con Base MG (poi facoltativamente le altre) · RD Rebels da Deserti
   senza Opposizione né Base RD → spazi con Base RD (se non ci sono Basi RD vengono
   rimossi) · Reclaimer: prima possono spostare Basi nella Wilderness (i Conversion
   Center si girano sul lato base), poi Ribelli verso spazi con Base CR.
5. **Reset** — Popolazione su Earth pari al valore della traccia EG Confidence ·
   tutti i Ribelli e SpecOps diventano Nascosti · via le Campaign card attive ·
   Asset scartate rimescolate nel mazzo · tutte le Fazioni Eligible · si rivelano
   Current e Next Event · Flashpoint a 0 e si tira per le tempeste sommando i due
   valori Flashpoint.

Al **terzo** Dust Storm Round la partita finisce.

---

## 10. Vittoria (§2.0)

| Fazione | Totale | Soglia |
| --- | --- | --- |
| MarsGov | Totale Supporto + EG Confidence | > 34 |
| Corporations | Profits | > 36 |
| Red Dust | Totale Opposizione + Basi RD su Mars | > 32 |
| Reclaimer | Spazi con Controllo CR + Basi CR su Mars | > Basi **nemiche** su Mars |

Controllo all'inizio di ogni Dust Storm Round. Se nessuno vince entro la fine,
vince il **margine più alto** (valore − soglia). Parità: Reclaimer, poi MarsGov,
poi Red Dust.

---

## 11. Operazioni (§5.0)

Ogni spazio può essere scelto una sola volta per l'Operazione. Si paga dopo aver
risolto tutti gli spazi; non si possono scegliere più spazi di quanti se ne possano
pagare (ma si può interrompere per una SA che dà Risorse).

### COIN

| Op | Chi | Sintesi |
| --- | --- | --- |
| **Train** (§5.1) | MG | Spazi con Base MG o Labirinti con Controllo COIN. Fino a 4 Truppe per spazio, 3 Risorse per spazio dove si piazza. Poi **Pacify** in 1 spazio. |
| **Logistics** (§5.2) | CORP | Seleziona Earth (fino a 4 unità, max 1 SpecOps; extra a 1 Profit l'una), Transit (attiva l'Aldrin Cycler), Deserti con Base CORP (1ª gratis, poi 3 Profits per upgrade a Terraforming). Infine 1 Security per Base CORP a 1 Profit l'una. |
| **Secure** (§5.3) | MG/CORP | Destinazioni = Labirinti. MG paga 3 per Labirinto dove le unità si fermano. Movimento da spazi adiacenti, lungo Maglev, e fra Spaceport di Labirinti con Controllo COIN, senza Danno né tempesta. Stop obbligatorio entrando in un Labirinto sotto Controllo nemico. Poi **Attiva 1 Ribelle per unità propria**; si può rimuovere 1 Security/Truppa per piazzare una Base; poi House o Repair in 1 destinazione. *Drop Pods*: il Controller può usare un Satellite per portare EG Troops da Phobos. |
| **Recon** (§5.4) | MG/CORP | Come Secure ma destinazioni = Deserti (no Maglev; Spaceport solo come origine). MG paga 3 per destinazione. Attiva 1 Ribelle per unità (1 ogni **2** unità nella Wilderness). *Navigation Beacons*: un Satellite rende selezionabile un Deserto in tempesta, oppure Attiva 2 Ribelli in un Deserto senza tempesta. |
| **Assault** (§5.5) | MG/CORP | Spazi con forze proprie e forze nemiche **Attive**. MG paga 3 per spazio. Rimuove 1 Ribelle/Base Attivo per ogni cubo o SpecOps Attivo. Poi nei **Labirinti** (o presso una Base RD **Dug-In**) i Ribelli colpiti possono fare un **Attack gratuito**. *Mercenaries*: +1 Profit ogni 2 forze Ribelli rimosse in uno spazio con Security o SpecOps Attivi. *Bombard* e *Suppress* per il Controller EG. |

### Ribelli

| Op | Chi | Sintesi |
| --- | --- | --- |
| **Rally** (§5.6) | RD/CR | RD: spazi Popolati **senza Supporto**. CR: spazi **Neutrali**. 1 Risorsa per spazio. Piazza 1 Ribelle, o rimpiazza 2 Ribelli con una Base; con Base già presente: piazza Ribelli fino a Popolazione + Basi, **oppure** nasconde tutti i Ribelli, **oppure** (CR) upgrada una Base a Conversion Center e pesca un Asset. RD può poi upgradare **1** Base in un Deserto a Dug-In (anche fuori dagli spazi scelti, anche in Limited Op). |
| **March** (§5.7) | RD | Come Secure per i Ribelli RD, 1 Risorsa per destinazione dove si fermano. In destinazioni con Supporto: se (Ribelli in movimento da una singola origine + cubi e SpecOps presenti) **> 3**, quei Ribelli si Attivano. Chi entra nella Wilderness si Nasconde. |
| **Travel** (§5.8) | CR | Si scelgono le **origini** (1 Risorsa l'una; la Wilderness è gratis). Ribelli e Basi si spostano di 1 spazio adiacente (le Basi mosse si girano sul lato base). **Ignora le Raging Storm.** Stessa regola di Attivazione (>3) sugli spazi con Supporto; si Nasconde chi entra nella Wilderness o in uno spazio con tempesta. I Ribelli Nascosti possono proseguire attraverso spazi con Base CR, anche più volte. |
| **Attack** (§5.9) | RD/CR | Spazi con propri Ribelli e forze nemiche. 1 Risorsa per spazio. Attiva **tutti** i propri Ribelli e tira 2 dadi: se la **somma** ≤ forze totali presenti → 1 Danno; per **ogni dado** ≤ numero dei propri Ribelli → rimuovi **2** forze nemiche (1 EG Troop conta come 2). I Ribelli Nascosti possono essere colpiti; gli SpecOps Nascosti no (e non proteggono le Basi). Basi per ultime. Un Attack CR che distrugge una Base Terraforming permette di piazzare una Base CR. |
| **Campaign** (§5.10) | RD | Spazi Popolati con almeno 1 RD Rebel, 1 Risorsa l'uno. Attiva un Ribelle se nessuno è Attivo, poi sposta di 1 livello verso Opposizione Attiva. Se lo spazio è (o era già) in Opposizione Attiva → pesca una Campaign card. Se finisce a Supporto Passivo → 1 Danno, EG−, e −2 Profits se c'è una Base CORP. Infine **1** carta Campaign in gioco, le altre rimescolate. |
| **Preach** (§5.11) | CR | Spazi Popolati con almeno 1 CR Rebel, 1 Risorsa l'uno. Attiva un Ribelle, poi sposta di 1 livello verso **Neutrale**; se era già Neutrale piazza CR Rebels pari alla Popolazione e rimuove un marker Popolazione (o, se non ce ne sono, piazza un Danno e EG−). |

---

## 12. Attività Speciali (§6.0)

Devono accompagnare un'Operazione (mai una Limited Op), prima/durante/dopo, senza
spezzare la risoluzione di un singolo spazio.

| SA | Fazione | Accompagna | Sintesi |
| --- | --- | --- | --- |
| **Entrench** (§6.1) | MG | Train/Secure/Recon | Fino a 2 spazi con Controllo COIN e forze MG: sostituisci 1 Truppa con una Base; **Fortify** Truppe sui quadrati Popolati (max 1 per Popolazione): assorbono un Danno ciascuna. |
| **Petition** (§6.2) | MG | Secure/Recon/Assault, solo a Operazione conclusa | 1 Supply su Earth + 1 ogni 3 Ribelli Attivati (−1 Profit ciascuno). Se l'Assault ha rimosso più forze Ribelli che COIN: EG+ e −2 Profits. |
| **Transport** (§6.3) | MG | qualsiasi | Phobos + tutti gli spazi con Base MG + 1 spazio extra (2 se Controller EG): muovi Truppe fra quegli spazi. |
| **Public Relations** (§6.4) | CORP | Logistics/Secure/Recon | Fino a 2 spazi con Controllo COIN e Security: Repair quante volte si vuole (+2 Profits per Danno rimosso), House in 1 spazio. Dove è successo: −3 Risorse RD se ci sono forze RD; i Reclaimer scartano 1 Asset se ci sono forze CR. |
| **Exploit** (§6.5) | CORP | Logistics/Assault | Fino a 2 spazi con Base CORP, nessun Danno e più forze CORP che MarsGov: +Profits pari alla Popolazione, poi 1 livello verso Neutrale; se lo spazio è controllato da RD/CR quelli guadagnano Risorse/pescano. |
| **Raid** (§6.6) | CORP | Secure/Recon/Assault | Fino a 2 spazi: muovi fino a 2 SpecOps Nascosti da spazi adiacenti senza tempesta; poi Attiva 1 SpecOps per rimuovere 1 EG Troop **o** 2 altre forze (Satelliti compresi). Se sono state rimosse forze MG/EG → EG−. |
| **Redistribute** (§6.7) | RD | qualsiasi | Fino a 4 spazi Popolati con RD Rebel Nascosto e Controllo RD: Attiva 1 Ribelle, +Popolazione (+1 per Base CORP) Risorse. |
| **Coordinate** (§6.8) | RD | Rally/March/Campaign | Fino a 2 spazi senza Supporto con RD Rebel Nascosto: Attiva 1 Ribelle, House o Repair, poi 1 livello verso Opposizione Attiva; se già Attiva, rimuovi 2 Truppe MG/Security o sostituiscine 1 con un RD Rebel. |
| **Ambush** (§6.9/§6.12) | RD/CR | solo Attack | Fino a 2 spazi già scelti per l'Attack e non ancora risolti, con un Ribelle Nascosto: si Attiva **solo 1** Ribelle e i due dadi si **impostano** a piacere. |
| **Purify** (§6.10) | CR | qualsiasi | Fino a 2 spazi con forze nemiche, un CR Rebel Nascosto e Controllo CR: Attiva 1 Ribelle e poi sostituisci un'unità nemica con un CR Rebel (due se c'è un Conversion Center), **oppure** rimpiazza una Base nemica indifesa con un Conversion Center e pesca un Asset. |
| **Ransack** (§6.11) | CR | qualsiasi | Fino a 2 spazi Danneggiati con un CR Rebel Nascosto: Attiva 1 Ribelle e pesca 1 Asset per ogni Danno. |

---

## 13. Carte (§1.5, §7.0)

* **51 Eventi** (48 + 3 Dust Storm). Ogni carta ha valore Flashpoint (0–4) e
  l'ordine di Eligibility; quasi tutte hanno testo **non ombreggiato** e
  **ombreggiato** (le #32, #34, #47 hanno un solo effetto). Alcune opzioni portano
  il simbolo EG+/EG−.
* **Mazzo** (§3.3): tolte le 3 Dust Storm, si mescolano le 48, si formano 3 pile da
  12 (le restanti 12 escono dal gioco senza essere viste), si mescola una Dust Storm
  nelle 6 carte in fondo a ogni pila, poi si impilano → **39 carte**.
* **30 Asset card** (solo Reclaimer): valore in Risorse, alcune con Evento, alcune
  **Capability** permanenti (che danno anche un'Operazione gratuita in 2 spazi + 1
  pescata, una tantum). Mano massima 6; le scartate rientrano nel mazzo al Reset del
  Dust Storm Round.
* **12 Campaign card** (solo Red Dust): 1 in gioco al setup, effetto continuo fino
  al Reset del prossimo Dust Storm Round.
* Gli Eventi non possono violare lo stacking delle Basi, non piazzano forze non
  Disponibili, non piazzano mai Ribelli su Phobos, non bersagliano Deserti in Raging
  Storm né muovono forze dentro/fuori Labirinti in tempesta.

---

## 14. Scambi (§1.6)

MarsGov e Red Dust possono trasferirsi Risorse mentre chi riceve sta eseguendo
un'azione. I Reclaimer possono spendere Asset card per trasferire Risorse a MG/RD.
MG e RD possono trasferire Risorse ai Reclaimer solo per pagare un'Operazione che i
Reclaimer stanno eseguendo, e devono essere spese subito. **Le Corporations non
hanno Risorse e non ne possono né dare né ricevere.**

---

## 15. Punti da verificare / TODO di modellazione

* Simboli **★** e **⊘** stampati sotto le icone delle Fazioni sulle carte: servono
  solo alle regole Non-Player (Critical / Not Performed, §8.5.5). Il Playbook li
  indica con sottolineature e riquadri che l'estrazione testuale non conserva:
  vanno ricavati dalle immagini delle carte o dalle pagine del Playbook con analisi
  di stile.
* Il sistema Non-Player *Curiosity* (mazzo da 24 carte + aid sheet) è tutto ancora
  da leggere e implementare: `sources/rules/RDR_Curiosity_NP_Rules_Booklet_1D_Web.pdf`.
* Testi delle 30 Asset card e delle 12 Campaign card: da estrarre (immagini
  `CR 1..30` e `RD 1..12` nel modulo Vassal).
* La FAQ ufficiale non è ancora stata integrata in questa sintesi.

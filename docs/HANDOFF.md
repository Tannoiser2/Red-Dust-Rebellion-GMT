# Passaggio di consegne

Stato al 6 agosto 2026, commit `7adc3d5`. Questo documento serve a chi riprende
il lavoro senza aver seguito quello precedente: dice **dov'è la roba**, **cosa
funziona davvero**, **cosa manca** e soprattutto **quali trappole sono già
costate tempo**, perché non le ripaghi due volte.

---

## 1. Cos'è

Implementazione digitale di *Red Dust Rebellion* (GMT 2024, serie COIN Vol. XII)
in **Godot 4.7 / GDScript**. Regole complete a quattro Fazioni, più il sistema
Non-Player *Curiosity* che permette di giocare in solitario contro fino a tre
bot — o di far giocare la partita interamente ai bot, che è anche il modo
migliore per collaudarla.

Il progetto vive in `godot/`. Si apre con l'editor Godot 4.7; la scena iniziale
è `scenes/MainMenu.tscn`.

Repository: <https://github.com/Tannoiser2/Red-Dust-Rebellion-GMT>
Build giocabile nel browser: <https://tannoiser2.github.io/Red-Dust-Rebellion-GMT/>

La build Web sta sulla branch **`gh-pages`**, che contiene *solo* l'export e non
ha in comune la storia con `master`. Si rigenera così, e va poi spinta a mano su
quella branch:

```bash
godot --headless --path godot --export-release "Web" "../web/index.html"
```

Il preset Web è **senza thread** di proposito: GitHub Pages non invia gli header
COOP/COEP che `SharedArrayBuffer` richiede, e con l'export a thread la pagina
resta bianca. Non rimetterlo a `true` pensando di guadagnare prestazioni.

## 2. Impianto

```
godot/
  coin_engine/            motore generico della serie COIN, condiviso fra titoli
    GameState.gd          stato della partita, serializzabile (save/load, undo)
    SpaceState.gd         pezzi e marcatori di uno spazio
    SequenceOfPlay.gd     §4.1 chi agisce, in quale casella, quando finisce la carta
    GameDef/SpaceDef/…    definizioni caricate dai JSON

  games/red_dust_rebellion/
    RDRModule.gd          regole specifiche del titolo: Controllo di coalizione,
                          Popolazione variabile, EarthGov, contatori surrogati NP
    rules/
      Operations.gd       §5.0 le 11 Operazioni
      SpecialActivities.gd §6.0 le 11 Attività Speciali
      Actions.gd          azioni condivise: House, Repair, Shift, movimento
      Events.gd           §7.0 interprete degli Eventi (dati, non codice)
      Cards.gd            mazzi Asset e Campaign
      Rounds.gd           §4.2 Flashpoint Round, §4.3 Dust Storm Round, tempeste
      Sequence.gd         specializzazione RDR della Sequence of Play
      NonPlayer.gd        §8.0 tabelle: Eligibility, Space/Move/Piece Priorities
      NonPlayerOps.gd     §8.6/§8.7 esecuzione delle Operazioni e Speciali del bot
      NonPlayerMove.gd    §8.5.7 motore Keep/Get del movimento
      NonPlayerRound.gd   §8.5.9 Round periodici del bot
    data/                 TUTTE le regole variabili stanno qui, non nel codice
    assets/               immagini normalizzate dal modulo Vassal

  scenes/
    GameController.gd     autoload: possiede stato e regole, emette state_changed
    Main.gd               la scena di gioco (mappa + pannello)
    RegionView.gd         una zona cliccabile, coi suoi pezzi
    TrackOverlay.gd       marcatori dei tracciati e cilindri della Sequence
    MapAnimator.gd        pezzi che volano, spazi che lampeggiano
    RDRAssets.gd/RDRTheme.gd  texture e aspetto

  tests/
    test_runner.gd        1029 asserzioni sulle regole, senza scena
    scene_smoke.gd        122 controlli montando davvero Main.tscn
```

**Il principio portante: le regole variabili sono dati.** Le 93 opzioni degli
Eventi, le 48 facce delle carte Curiosity, le quattro tabelle di priorità, le
istruzioni del Dust Storm Round sono JSON in `data/`, interpretati da GDScript.
Aggiungere una carta non richiede codice nuovo — richiede una voce nel JSON e,
se usa un'operazione mai vista, un `case` in più nell'interprete.

## 3. Come si lavora

**Appena clonato, prima di ogni altra cosa:** la cache di import di Godot
(`godot/.godot/`) non sta nel repository, e senza di essa nessuna texture è
caricabile — le due suite danno *zero* asserzioni e sembra tutto rotto. Un giro
a vuoto dell'editor la ricostruisce:

```bash
godot --headless --path godot --editor --quit
```

Serve anche più tardi, ogni volta che si aggiunge un'immagine in `assets/` o si
crea una nuova classe con `class_name`: la cache delle classi si aggiorna lì.

```bash
godot --headless --path godot -s res://tests/test_runner.gd
```

```bash
godot --headless --path godot -s res://tests/scene_smoke.gd
```

Devono dare **1029 passati, 0 falliti** e **122 ok**. Entrambe le suite girano
in meno di un minuto: falle girare sempre, sono il paracadute.

Build dell'app macOS — la firma va fatta **fuori dalla cartella sincronizzata**,
perché iCloud rimette gli attributi estesi appena li togli e `codesign` rifiuta:

```bash
godot --headless --path godot --export-release "macOS" "../dist/macos/Red Dust Rebellion — Digital.app"
```

```bash
rm -rf /tmp/rdr && mkdir -p /tmp/rdr && ditto --norsrc --noextattr --noacl "dist/macos/Red Dust Rebellion — Digital.app" "/tmp/rdr/Red Dust Rebellion — Digital.app" && xattr -cr "/tmp/rdr/Red Dust Rebellion — Digital.app" && codesign --force --deep --sign - "/tmp/rdr/Red Dust Rebellion — Digital.app" && ditto --norsrc --noextattr --noacl "/tmp/rdr/Red Dust Rebellion — Digital.app" "/Applications/Red Dust Rebellion — Digital.app"
```

Fonti di verità in `sources/rules/`: regolamento, Playbook, libretto *Curiosity*
(32 pagine), FAQ ufficiale del 15/05/2025, e le scansioni delle schede del gioco
fisico. Si leggono con PyMuPDF (`fitz`) renderizzando a 300–600 DPI. **Non
inventare una regola: è quasi sempre scritta da qualche parte, e il resto del
progetto è stato costruito andandola a leggere.**

## 4. Cosa funziona

- **Regole a quattro Fazioni**: tutte e 11 le Operazioni, tutte e 11 le Attività
  Speciali, i Round periodici, le tempeste, la vittoria.
- **Carte**: 48 Evento su 51 con effetti scritti (le 3 mancanti sono le Dust
  Storm, che l'Evento non ce l'hanno) per 93 opzioni, **0 manuali**; 10 Asset
  Event; 10 Capability applicate dal motore; 12 Campaign su 12.
- **Sistema Non-Player completo**: tutte e quattro le tabelle di priorità, le 48
  facce delle carte Curiosity, Eligibility, Effective Events, Event Instructions,
  simboli ★/⊘, movimento Keep/Get, Ambush e Transport, Capability & Campaign
  Effects, Flashpoint e Dust Storm Round. Una partita di soli bot arriva alla
  fine da sola.
- **Interfaccia**: mappa con zoom e pan, drag & drop per gli spostamenti,
  animazione dei pezzi, anteprima delle azioni, undo, salvataggio e
  autosalvataggio, Log a colori con dettagli collassabili.

## 5. Cosa manca — in ordine di valore

### 5.1 Le scelte che l'interfaccia non sa chiedere ← il divario più grosso

Il motore conosce le regole; l'interfaccia non offre tutti i modi di
esercitarle, e decide al posto tuo con un «piano minimo». Le regole *ci sono*:
manca il modo di usarle.

| Azione | Cosa l'interfaccia decide da sé |
|---|---|
| Rally | Sempre «piazza 1 Ribelle»: niente Base, niente Dig-In |
| Assault | Niente Suppress, niente Bombard |
| Logistics | Niente acquisti su Earth, niente Transit |
| Raid | Non muove gli SpecOps dagli spazi adiacenti |
| Entrench, Public Relations, Coordinate, Purify | Parametri fissi |
| **Transport** | Non azionabile: elencata con 0 spazi, non gestita dal dispatcher |
| **Ambush** | Assente dall'interfaccia (il motore la esegue, il bot la usa) |

I punti d'intervento: `GameController._run_operation_on()` e
`_run_special_on()` costruiscono i piani; `Main.gd` costruisce la barra
(`_refresh_op_bar`) e raccoglie gli spazi. Serve un form per azione, non un
pulsante in più.

### 5.2 Support Phase e Redeploy per i giocatori

Nel Dust Storm Round, Pacify/Lobby/Agitate e i Redeploy facoltativi sono scelte
del giocatore e l'interfaccia non le chiede: vengono saltate con una riga nel
Log. Per le Fazioni NP invece sono implementate (`NonPlayerRound.gd`), quindi il
comportamento corretto è già scritto e si può prendere a modello.

### 5.3 Voci minori

Un'istruzione NP (Event #30 per i Reclaimer) dalla FAQ; simulazioni di
bilanciamento; GitHub Actions. Sono in `docs/ROADMAP.md`, 8 voci aperte in tutto.

## 6. Trappole già pagate

Ognuna di queste è costata tempo. Sono qui perché non lo costino di nuovo.

**L'autoload esegue `_ready()` al primo frame, non prima.** In uno script
`-s`, `root.get_node("GameController")` restituisce il nodo, ma la partita che
gli chiedi di creare viene poi sostituita da quella di default. `await
process_frame` **prima** di `new_game()`. Lo smoke test dichiarava un seme fisso
e girava su partite casuali per settimane.

**`sequence.act()` restituisce un bool e va guardato.** Se l'azione non è legale
in quello slot non registra niente, la Fazione di turno non cambia, e chi la
richiama entra in un ciclo infinito: il Log scorre e la plancia resta ferma. Ci
sono due blocchi già capitati così.

**Una Fazione NP non traccia Risorse (§8.5.4).** Non è un dettaglio contabile:
se le chiedi (`can_repair` lo faceva) il bot smette di agire in silenzio appena
esaurisce quelle dello schieramento. Usa `module.resources_delta()` per i
cambi generici e `RDRActions._can_afford/_spend` per i costi delle azioni.
Il Passo di un bot passa da `GameController.do_pass()`, non da
`sequence.act_pass()`, altrimenti perde Aldrin Cycler e Asset card.

**Il Log è il miglior strumento diagnostico che c'è.** Far giocare una partita
di soli bot e rileggere il Log ha trovato più bug dei test sintetici: il
Redistribute che regalava Risorse a un bot, le Operazioni gratuite mai eseguite,
il Passo che non fruttava. Menu «Partita… → Salva il Log sulla Scrivania»: il
file contiene tutte le righe, dettagli compresi.

**Non committare dati di gioco incerti.** Durante l'estrazione dei simboli ★/⊘
il riconoscimento sbagliava; la cosa giusta è stata cancellare il file e
verificare 204 ritagli a vista, non tenere dati plausibili. Un JSON sbagliato in
`data/` è peggio di un JSON mancante, perché nessuno lo va più a controllare.

**Attenzione ai test degeneri.** Più volte un test è passato o fallito per
ragioni diverse da quelle credute: uno spazio già al massimo di Supporto, un
solo nemico da rimuovere che rende i dadi indifferenti, Profits a zero che
nascondono un decremento. Quando un test fallisce, prima di correggere il codice
verifica che lo scenario dica quello che credi.

## 7. Convenzioni

- **Commenti e messaggi in italiano**, e spiegano *perché*, non *cosa*. Dove una
  scelta viene da una regola, il commento cita il paragrafo (§5.9, §8.5.4).
- **Commit descrittivi**: cosa cambia, perché, e cosa ha rivelato. La cronologia
  è stata usata più volte per ricostruire il ragionamento.
- **Ogni bug trovato diventa un test**, nella suite che lo avrebbe preso: le
  regole in `test_runner.gd`, il flusso di gioco in `scene_smoke.gd`.
- **Niente numeri magici nel codice** se possono stare in `data/`.

## 8. Se riprendo da zero, da dove comincio

1. Fai girare le due suite: devono dare 1029 e 122.
2. Apri l'app, avvia una partita di soli bot, lasciala finire, salva il Log e
   leggilo. In mezz'ora capisci come gira il gioco meglio che leggendo il codice.
3. Leggi `docs/ROADMAP.md` per le 8 voci aperte e `docs/RULES_DIGEST.md` per il
   riassunto delle regole.
4. Il primo lavoro utile è §5.1: dare all'interfaccia le scelte che le mancano,
   partendo dal Rally (l'Operazione più usata dai Ribelli, dove la scelta
   Base/Dig-In cambia di più la partita) e dall'Assault con Suppress e Bombard.

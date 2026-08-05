class_name RDRSequence
extends SequenceOfPlay

## Sequenza di una carta Evento in Red Dust Rebellion (§4.1).
##
## Differenze rispetto alla tabella COIN standard implementata dal motore:
##  * se la 1ª Disponibile fa Operazione + Attività Speciale, la 2ª può scegliere
##    fra Operazione Limitata **e** Evento (nello standard solo l'Evento);
##  * i Reclaimer sono sempre ultimi nell'ordine stampato, ma prima che chiunque
##    agisca possono scartare fino a 3 Asset card per avanzare di altrettante
##    posizioni;
##  * il Passo non dà Risorse a tutti: MarsGov +3, Red Dust +1, le Corporations
##    devono attivare l'Aldrin Cycler e i Reclaimer pescano una Asset card;
##  * Desert Efficiency: i Reclaimer 2ª Disponibili che scelgono l'Operazione
##    Limitata possono selezionare più spazi pagandoli con una sola Asset card.

## Asset card scartate dai Reclaimer per anticipare il proprio turno (§4.1).
var reclaimer_shift: int = 0
## Effetti collaterali del Passo che il chiamante deve eseguire (l'Aldrin Cycler
## dei CORP e la pescata dei Reclaimer non sono Risorse).
var pass_effects: Array[String] = []


func second_slot_actions(first: int) -> Array[int]:
	match first:
		A.OPERATION:
			return [A.LIMITED_OPERATION]
		A.OPERATION_WITH_SPECIAL:
			# §4.1: "may execute a Limited Operation or instead execute the Event".
			return [A.LIMITED_OPERATION, A.EVENT]
		A.EVENT:
			return [A.OPERATION, A.OPERATION_WITH_SPECIAL]
		_:
			return [A.LIMITED_OPERATION]


## §4.1: i Reclaimer scartano `n` Asset card (max 3) e avanzano di `n` posizioni
## nell'ordine STAMPATO sulla carta, non fra le sole Fazioni Disponibili — quindi
## a volte bastano meno carte del previsto per diventare 1ª Disponibile.
## Va fatto prima che qualsiasi Fazione agisca; restituisce false altrimenti.
func reclaimer_discard(n: int) -> bool:
	if n <= 0 or _idx > 0 or not actors().is_empty():
		return false
	n = mini(n, 3)
	var printed: Array[String] = []
	for fid in card.faction_order:
		printed.append(String(fid))
	var pos := printed.find("reclaimer")
	if pos < 0:
		return false
	printed.remove_at(pos)
	printed.insert(maxi(0, pos - n), "reclaimer")
	reclaimer_shift = n
	# Ricostruisce la coda delle Disponibili sul nuovo ordine stampato.
	_eligible_order.clear()
	for fid in printed:
		if state.eligibility.get(fid, CoinEnums.Eligibility.ELIGIBLE) == CoinEnums.Eligibility.ELIGIBLE:
			_eligible_order.append(fid)
	return true


## Numero minimo di Asset card da scartare perché i Reclaimer diventino la
## `target`-esima Fazione Disponibile (1 = prima). -1 se non è raggiungibile.
func reclaimer_cost_to_reach(target: int) -> int:
	for n in range(0, 4):
		var printed: Array[String] = []
		for fid in card.faction_order:
			printed.append(String(fid))
		var pos := printed.find("reclaimer")
		printed.remove_at(pos)
		printed.insert(maxi(0, pos - n), "reclaimer")
		var rank := 0
		for fid in printed:
			if state.eligibility.get(fid, CoinEnums.Eligibility.ELIGIBLE) == CoinEnums.Eligibility.ELIGIBLE:
				rank += 1
				if fid == "reclaimer":
					break
		if rank <= target:
			return n
	return -1


## §4.1: il Passo. Oltre alle Risorse registra gli effetti non-Risorsa, che il
## chiamante esegue (`aldrin_cycler` per le Corporations, `draw_asset` per i
## Reclaimer).
func act_pass() -> bool:
	var fid := pending_faction()
	if fid == "":
		return false
	match fid:
		"corporations":
			pass_effects.append("aldrin_cycler")
		"reclaimer":
			pass_effects.append("draw_asset")
	return super()


## §7.0: alcuni Eventi rendono una Fazione Non Disponibile per tutto l'Event
## Round successivo ("Ineligible through the next Event Round"), altri lasciano
## Disponibile chi ha appena agito ("remains Eligible"). Le due liste sono
## riempite da RDREvents e consumate qui, alla chiusura della carta.
func finish() -> void:
	super()
	for fid in state.tracks.get("stay_eligible", []):
		state.eligibility[String(fid)] = CoinEnums.Eligibility.ELIGIBLE
	state.tracks["stay_eligible"] = []
	for fid in state.tracks.get("forced_ineligible", []):
		state.eligibility[String(fid)] = CoinEnums.Eligibility.INELIGIBLE
	state.tracks["forced_ineligible"] = []


## §4.1 Desert Efficiency: vale solo per i Reclaimer 2ª Disponibili che mettono
## il proprio cilindro nella casella Operazione Limitata.
func desert_efficiency_applies(fid: String, action: int) -> bool:
	return fid == "reclaimer" and action == A.LIMITED_OPERATION and not is_first_slot()

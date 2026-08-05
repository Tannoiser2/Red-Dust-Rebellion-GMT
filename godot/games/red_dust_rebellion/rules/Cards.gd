class_name RDRCards
extends RefCounted

## Mazzi Asset (Reclaimer) e Campaign (Red Dust) — §1.5.
##
## Asset: mano da 6 carte al massimo; si scartano per pagare le Risorse delle
## Operazioni (valore maggiorato se la carta nomina quell'Operazione), per
## anticipare il proprio turno nell'ordine di Eligibility, o per giocarne
## l'Evento. Le Capability restano in gioco permanentemente. Gli scarti
## rientrano nel mazzo al Reset del Dust Storm Round (§4.3).
##
## Campaign: una carta in gioco alla volta, rimossa dal gioco al Reset.

const HAND_LIMIT := 6

var state: GameState
var module: RDRModule
var rng: RandomNumberGenerator
var assets: Dictionary = {}      ## numero -> definizione
var campaigns: Dictionary = {}
var log_lines: Array[String] = []


func _init(p_state: GameState, p_module: RDRModule, p_rng: RandomNumberGenerator = null) -> void:
	state = p_state
	module = p_module
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	for c in _load(RDRModule.DATA_DIR + "assets.json"):
		assets[int(c["number"])] = c
	for c in _load(RDRModule.DATA_DIR + "campaigns.json"):
		campaigns[int(c["number"])] = c


func _load(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("RDRCards: file non trovato %s" % path)
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed.get("cards", []) if typeof(parsed) == TYPE_DICTIONARY else []


# ---------------------------------------------------------------------------
# Preparazione (§3.3)
# ---------------------------------------------------------------------------

## Mescola i due mazzi, dà 3 Asset ai Reclaimer e mette in gioco una Campaign.
func setup() -> void:
	state.tracks["asset_deck"] = _shuffled(assets.keys())
	state.tracks["asset_hand"] = []
	state.tracks["asset_discard"] = []
	state.tracks["capabilities"] = []
	for i in range(3):
		draw_asset()
	state.tracks["campaign_deck"] = _shuffled(campaigns.keys())
	state.tracks["campaign_in_play"] = -1
	draw_campaign_into_play()


func _shuffled(numbers: Array) -> Array:
	var out: Array = numbers.duplicate()
	out.sort()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


# ---------------------------------------------------------------------------
# Asset card
# ---------------------------------------------------------------------------

func hand() -> Array:
	return state.tracks.get("asset_hand", [])


func deck() -> Array:
	return state.tracks.get("asset_deck", [])


func discard_pile() -> Array:
	return state.tracks.get("asset_discard", [])


func active_capabilities() -> Array:
	return state.tracks.get("capabilities", [])


## §1.5: se il mazzo è esaurito non si pesca più fino al Reset del prossimo
## Dust Storm Round, quando gli scarti vengono rimescolati.
func draw_asset(n: int = 1) -> int:
	var drawn := 0
	for i in range(n):
		var d: Array = deck()
		if d.is_empty():
			log_lines.append("Mazzo Asset esaurito: nessuna pescata fino al prossimo Dust Storm Round.")
			break
		hand().append(d.pop_back())
		drawn += 1
	enforce_hand_limit()
	return drawn


## §1.5: dopo qualsiasi pescata si scarta fino a un massimo di 6 carte in mano.
func enforce_hand_limit() -> int:
	var h: Array = hand()
	var over := 0
	while h.size() > HAND_LIMIT:
		# Si scartano per prime le carte di puro valore, tenendo Eventi e Capability.
		var idx := _cheapest_index(h)
		discard_pile().append(h[idx])
		h.remove_at(idx)
		over += 1
	return over


func value_of(number: int, operation: String = "") -> int:
	var c: Dictionary = assets.get(number, {})
	if operation != "" and String(c.get("bonus_operation", "")) == operation:
		return int(c.get("bonus_value", c.get("value", 0)))
	return int(c.get("value", 0))


## §1.5: i Reclaimer scartano carte per un valore complessivo pari o superiore
## al costo; l'eccedenza è persa. Restituisce false se la mano non basta.
func pay(amount: int, operation: String = "") -> bool:
	if amount <= 0:
		return true
	var h: Array = hand()
	# Politica automatica: si spendono prima le carte di solo valore (le più
	# efficienti), tenendo Eventi e Capability finché possibile.
	var order: Array = h.duplicate()
	order.sort_custom(func(a, b):
		var ka := _spend_rank(int(a), operation)
		var kb := _spend_rank(int(b), operation)
		return ka > kb)
	var total := 0
	var chosen: Array = []
	for number in order:
		if total >= amount:
			break
		chosen.append(number)
		total += value_of(int(number), operation)
	if total < amount:
		return false
	for number in chosen:
		h.erase(number)
		discard_pile().append(number)
	log_lines.append("I Reclaimer scartano %d Asset card per %d Risorse (costo %d)." % [
		chosen.size(), total, amount])
	return true


## Quanto "conviene" spendere questa carta: prima le Resource, poi il valore.
func _spend_rank(number: int, operation: String) -> int:
	var c: Dictionary = assets.get(number, {})
	var kind_bonus := 100 if String(c.get("kind", "")) == "resource" else 0
	return kind_bonus + value_of(number, operation)


func _cheapest_index(h: Array) -> int:
	var best := 0
	var best_rank := 99999
	for i in range(h.size()):
		var r := _spend_rank(int(h[i]), "")
		if r < best_rank:
			best_rank = r
			best = i
	return best


## §4.1: scarta `n` carte per avanzare di `n` posizioni nell'ordine stampato.
## Le carte #19 e #22 fanno pescare una carta se scartate per diventare 1ª.
func discard_for_eligibility(n: int) -> int:
	var h: Array = hand()
	var done := 0
	var bonus_draws := 0
	while done < n and not h.is_empty():
		var idx := _cheapest_index(h)
		var number := int(h[idx])
		if String(assets.get(number, {}).get("text", "")).begins_with("If discarded to claim First Eligible"):
			bonus_draws += 1
		discard_pile().append(number)
		h.remove_at(idx)
		done += 1
	if bonus_draws > 0:
		draw_asset(bonus_draws)
	return done


## §1.5: giocare l'Evento di una carta la scarta; una Capability invece resta
## in gioco (e non torna mai nel mazzo) e dà una Operazione gratuita una tantum.
func play_asset_event(number: int) -> Dictionary:
	var h: Array = hand()
	if not h.has(number):
		return {"ok": false, "error": "Carta non in mano."}
	var c: Dictionary = assets.get(number, {})
	var kind := String(c.get("kind", ""))
	if kind == "resource":
		return {"ok": false, "error": "Questa carta non ha un Evento."}
	h.erase(number)
	if kind == "capability":
		active_capabilities().append(number)
		log_lines.append("Capability in gioco: %s. Operazione gratuita in 2 spazi + 1 pescata." % c.get("title", number))
		return {"ok": true, "error": "", "capability": true, "free_operation": true}
	discard_pile().append(number)
	log_lines.append("Evento Asset giocato: %s." % c.get("title", number))
	return {"ok": true, "error": "", "capability": false}


func has_capability(number: int) -> bool:
	return active_capabilities().has(number)


## §4.3 Reset: gli scarti rientrano nel mazzo (le Capability in gioco no).
func reshuffle_discards() -> void:
	var d: Array = deck()
	for number in discard_pile():
		d.append(number)
	state.tracks["asset_discard"] = []
	state.tracks["asset_deck"] = _shuffled(d)


# ---------------------------------------------------------------------------
# Campaign card (§5.10)
# ---------------------------------------------------------------------------

func campaign_in_play() -> int:
	return int(state.tracks.get("campaign_in_play", -1))


## §5.10: si pescano una o più carte, se ne mette in gioco una e le altre
## tornano mescolate nel mazzo.
func draw_campaign_into_play(count: int = 1) -> int:
	var d: Array = state.tracks.get("campaign_deck", [])
	var drawn: Array = []
	for i in range(maxi(1, count)):
		if d.is_empty():
			break
		drawn.append(d.pop_back())
	if drawn.is_empty():
		return -1
	var keep := int(drawn[0])
	# La carta già in gioco viene sostituita e torna nel mazzo.
	var previous := campaign_in_play()
	if previous > 0:
		d.append(previous)
	for i in range(1, drawn.size()):
		d.append(drawn[i])
	state.tracks["campaign_deck"] = _shuffled(d)
	state.tracks["campaign_in_play"] = keep
	log_lines.append("Campaign in gioco: %s." % campaigns.get(keep, {}).get("title", keep))
	return keep


## §4.3 Reset: la Campaign attiva esce DAL GIOCO (non torna nel mazzo).
func remove_campaign() -> void:
	state.tracks["campaign_in_play"] = -1


func campaign_title(number: int) -> String:
	return String(campaigns.get(number, {}).get("title", ""))


func asset_title(number: int) -> String:
	return String(assets.get(number, {}).get("title", ""))

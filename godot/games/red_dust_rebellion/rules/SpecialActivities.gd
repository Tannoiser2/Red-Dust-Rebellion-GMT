class_name RDRSpecials
extends RefCounted

## Le Attività Speciali (§6.0).
##
## MarsGov: Entrench, Petition, Transport · Corporations: Public Relations,
## Exploit, Raid · Red Dust: Redistribute, Coordinate, Ambush ·
## Reclaimer: Purify, Ransack, Ambush.
##
## Ogni SA accompagna un'Operazione (§6.0): `accompanies()` dichiara quali, e
## `can_accompany()` lo verifica. Come per le Operazioni, il piano contiene le
## scelte del giocatore e il risultato è `{ok, error}`.

const ACCOMPANIES := {
	"entrench": ["train", "secure", "recon"],
	"petition": ["secure", "recon", "assault"],
	"transport": ["train", "logistics", "secure", "recon", "assault"],
	"public_relations": ["logistics", "secure", "recon"],
	"exploit": ["logistics", "assault"],
	"raid": ["secure", "recon", "assault"],
	"redistribute": ["rally", "march", "attack", "campaign"],
	"coordinate": ["rally", "march", "campaign"],
	"ambush": ["attack"],
	"purify": ["rally", "travel", "attack", "preach"],
	"ransack": ["rally", "travel", "attack", "preach"],
}

var state: GameState
var module: RDRModule
var act: RDRActions
var cards: RDRCards = null
var log_lines: Array[String] = []


func _init(p_state: GameState, p_module: RDRModule) -> void:
	state = p_state
	module = p_module
	act = RDRActions.new(p_state, p_module)


func can_accompany(sa: String, operation: String) -> bool:
	return ACCOMPANIES.get(sa, []).has(operation)


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


func _done() -> Dictionary:
	log_lines.append_array(act.log_lines)
	act.log_lines.clear()
	module.recompute_all_control(state)
	module.refresh_victory_tracks(state)
	return {"ok": true, "error": ""}


## Pescata/scarto dei Reclaimer, se i mazzi sono collegati.
func _cr_draw(n: int) -> void:
	if cards == null:
		log_lines.append("I Reclaimer pescherebbero %d Asset card (mazzi non collegati)." % n)
		return
	cards.draw_asset(n)
	log_lines.append_array(cards.log_lines)
	cards.log_lines.clear()


func _cr_discard(n: int) -> void:
	if cards == null:
		log_lines.append("I Reclaimer scarterebbero %d Asset card (mazzi non collegati)." % n)
		return
	for i in range(n):
		var h: Array = cards.hand()
		if h.is_empty():
			break
		cards.discard_pile().append(h.pop_back())


func _profits(delta: int) -> void:
	state.tracks["profits"] = clampi(int(state.tracks.get("profits", 0)) + delta, 0, 50)


# ===========================================================================
# MARTIAN GOVERNMENT
# ===========================================================================

## §6.1 Entrench — fino a 2 spazi con Controllo COIN e forze MarsGov: si può
## sostituire una Truppa con una Base, poi Fortificare Truppe sui quadrati
## Popolati (una per punto di Popolazione).
## plan = {spaces: [{id, build_base: bool, fortify: int}]}
func entrench(plan: Dictionary) -> Dictionary:
	var entries: Array = plan.get("spaces", [])
	if entries.size() > 2:
		return _fail("Entrench: al massimo due spazi.")
	for e in entries:
		var sid := String(e.get("id", ""))
		if state.spaces[sid].control != "coin":
			return _fail("Entrench: %s non è sotto Controllo COIN." % sid)
		if module.count_in(state, sid, "mg_troop") == 0:
			return _fail("Entrench: nessuna Truppa MarsGov in %s." % sid)
	for e in entries:
		var sid := String(e["id"])
		if bool(e.get("build_base", false)) and act.can_place_base(sid) \
				and module.count_in(state, sid, "mg_troop") > 0:
			module.remove_pieces(state, sid, "mg_troop", 1, "available")
			module.place_from_available(state, sid, "mg_base", 1)
		# Ogni quadrato Popolato può ospitare al massimo una Truppa Fortificata.
		var room := module.population(state, sid) - act.fortified(sid)
		var n: int = mini(mini(int(e.get("fortify", 0)), room), module.count_in(state, sid, "mg_troop"))
		if n > 0:
			module.add_marker(state, sid, "fortified", n)
	return _done()


## §6.2 Petition — solo a Operazione conclusa. Un marker Supply su Earth, più uno
## ogni 3 Ribelli Attivati dall'Operazione; ogni Supply costa 1 Profit alle
## Corporations. Se l'Assault ha rimosso più forze Ribelli che COIN: EG+ e −2 Profits.
## plan = {rebels_activated: int, assault_favourable: bool}
func petition(plan: Dictionary) -> Dictionary:
	var supplies := 1 + int(int(plan.get("rebels_activated", 0)) / 3.0)
	module.add_marker(state, "earth", "supply", supplies)
	_profits(-supplies)
	if bool(plan.get("assault_favourable", false)):
		act.set_eg("EG+")
		_profits(-2)
	log_lines.append("Petition: %d Supply su Earth, −%d Profits." % [supplies, supplies])
	return _done()


## §6.3 Transport — Phobos, tutti gli spazi con Base MG e uno spazio extra (due
## se EarthGov Controller): si spostano Truppe fra quegli spazi.
## plan = {extra: [sid], moves: [{from, to, type, count}]}
func transport(plan: Dictionary) -> Dictionary:
	var extra: Array = plan.get("extra", [])
	var allowed_extra := 2 if module.eg_controller(state) == "marsgov" else 1
	if extra.size() > allowed_extra:
		return _fail("Transport: al massimo %d spazi aggiuntivi." % allowed_extra)
	var pool: Array[String] = ["phobos"]
	for sid in module.mars_spaces(state):
		if module.count_in(state, sid, "mg_base") > 0:
			pool.append(sid)
	for sid in extra:
		pool.append(String(sid))
	for m in plan.get("moves", []):
		var from_sid := String(m.get("from", ""))
		var to_sid := String(m.get("to", ""))
		if not pool.has(from_sid) or not pool.has(to_sid):
			return _fail("Transport: %s → %s non è fra gli spazi attivati." % [from_sid, to_sid])
		var t := String(m.get("type", "mg_troop"))
		if t == "eg_troop" and module.eg_controller(state) != "marsgov":
			return _fail("Transport: le Truppe EG servono l'EarthGov Controller.")
		if module.count_in(state, from_sid, t) < int(m.get("count", 0)):
			return _fail("Transport: Truppe insufficienti in %s." % from_sid)
	for m in plan.get("moves", []):
		module.move_pieces(state, String(m["from"]), String(m["to"]),
			String(m.get("type", "mg_troop")), int(m["count"]))
	return _done()


# ===========================================================================
# CORPORATIONS
# ===========================================================================

## §6.4 Public Relations — fino a 2 spazi con Controllo COIN e Security: Repair
## quante volte si vuole (+2 Profits per Danno rimosso), House in uno solo.
## Dove è successo qualcosa: −3 Risorse RD se ci sono forze RD; i Reclaimer
## scartano un Asset se ci sono forze CR.
## plan = {spaces: [{id, repairs: int, house: bool}]}
func public_relations(plan: Dictionary) -> Dictionary:
	var entries: Array = plan.get("spaces", [])
	if entries.size() > 2:
		return _fail("Public Relations: al massimo due spazi.")
	for e in entries:
		var sid := String(e.get("id", ""))
		if state.spaces[sid].control != "coin":
			return _fail("Public Relations: %s non è sotto Controllo COIN." % sid)
		if module.count_in(state, sid, "security") == 0:
			return _fail("Public Relations: nessuna Security in %s." % sid)
	var houses := 0
	for e in entries:
		var sid := String(e["id"])
		var did := false
		for i in range(int(e.get("repairs", 0))):
			if not act.repair(sid, "corporations", String(e.get("eg", "EG+"))):
				break
			_profits(2)
			did = true
		if bool(e.get("house", false)) and houses == 0:
			if act.house(sid, "corporations", String(e.get("eg", "EG+"))):
				houses += 1
				did = true
		if not did:
			continue
		if module.count_in(state, sid, "rd_rebel") + module.count_in(state, sid, "rd_base") > 0:
			state.add_resources("red_dust", -3, 50)
		if module.count_in(state, sid, "cr_rebel") + module.count_in(state, sid, "cr_base") > 0:
			_cr_discard(1)
	return _done()


## §6.5 Exploit — fino a 2 spazi con Base CORP, nessun Danno e più forze CORP che
## MarsGov (le Truppe EG contano per il Controller): +Profits pari alla
## Popolazione, poi uno spostamento verso il Neutrale; se lo spazio è controllato
## da RD/CR quelli ne traggono beneficio.
## plan = {spaces: [sid]}
func exploit(plan: Dictionary) -> Dictionary:
	var spaces: Array = plan.get("spaces", [])
	if spaces.size() > 2:
		return _fail("Exploit: al massimo due spazi.")
	for sid in spaces:
		var s := String(sid)
		if module.count_in(state, s, "corp_base") == 0:
			return _fail("Exploit: nessuna Base CORP in %s." % s)
		if module.marker(state, s, "damage") > 0:
			return _fail("Exploit: %s è Danneggiata." % s)
		# §1.3: "forze" comprende anche le Basi, non solo le unità.
		var corp := module.count_in(state, s, "security") + module.count_in(state, s, "specops") \
			+ module.count_in(state, s, "corp_base")
		var mg := module.count_in(state, s, "mg_troop") + module.count_in(state, s, "mg_base")
		if module.eg_controller(state) == "corporations":
			corp += module.count_in(state, s, "eg_troop")
		else:
			mg += module.count_in(state, s, "eg_troop")
		if corp <= mg:
			return _fail("Exploit: in %s le forze CORP non superano quelle MarsGov." % s)
	for sid in spaces:
		var s := String(sid)
		var pop := module.population(state, s)
		_profits(pop)
		var st: SpaceState = state.spaces[s]
		if st.support != CoinEnums.Support.NEUTRAL:
			act.shift(s, -1 if st.support > 0 else 1)
		if st.control == "red_dust":
			state.add_resources("red_dust", pop, 50)
		elif st.control == "reclaimer":
			_cr_draw(1)
	return _done()


## §6.6 Raid — fino a 2 spazi: prima si muovono fino a 2 SpecOps Nascosti da
## spazi adiacenti senza tempesta, poi si Attiva uno SpecOps per rimuovere una
## Truppa EG oppure due altre forze qualsiasi (Satelliti compresi).
## plan = {spaces: [{id, moves: [{from, count}], targets: [type_id]}]}
func raid(plan: Dictionary) -> Dictionary:
	var entries: Array = plan.get("spaces", [])
	if entries.size() > 2:
		return _fail("Raid: al massimo due spazi.")
	for e in entries:
		var sid := String(e.get("id", ""))
		for m in e.get("moves", []):
			var from_sid := String(m.get("from", ""))
			if not state.game_def.space(sid).adjacent.has(from_sid):
				return _fail("Raid: %s non è adiacente a %s." % [from_sid, sid])
			if module.has_raging_storm(state, from_sid):
				return _fail("Raid: %s è sotto Raging Storm." % from_sid)
	var hit_coin := false
	for e in entries:
		var sid := String(e["id"])
		var moved := 0
		for m in e.get("moves", []):
			var n: int = mini(2 - moved, int(m.get("count", 0)))
			moved += module.move_pieces(state, String(m["from"]), sid, "specops", n, "hidden")
		var targets: Array = e.get("targets", [])
		if targets.is_empty():
			continue
		if act.activate(sid, "specops", 1) == 0:
			continue
		# Una Truppa EG, oppure due forze di qualunque altro tipo.
		var budget := 2
		for t in targets:
			var type_id := String(t)
			if budget <= 0:
				break
			var pt: PieceTypeDef = state.game_def.piece_type(type_id)
			if pt != null and pt.is_base and not act.base_removable(sid, type_id):
				continue
			if module.remove_pieces(state, sid, type_id, 1, act.removal_dest(type_id)) == 0:
				continue
			budget -= 2 if type_id == "eg_troop" else 1
			if type_id in ["mg_troop", "mg_base", "eg_troop", "satellite"]:
				hit_coin = true
	if hit_coin:
		act.set_eg("EG-")
	return _done()


# ===========================================================================
# RED DUST
# ===========================================================================

## §6.7 Redistribute — fino a 4 spazi Popolati con un Ribelle RD Nascosto e
## Controllo Red Dust: si Attiva un Ribelle e si guadagnano Risorse pari alla
## Popolazione, +1 per ogni Base CORP presente.
## plan = {spaces: [sid]}
func redistribute(plan: Dictionary) -> Dictionary:
	var spaces: Array = plan.get("spaces", [])
	if spaces.size() > 4:
		return _fail("Redistribute: al massimo quattro spazi.")
	for sid in spaces:
		var s := String(sid)
		if module.population(state, s) <= 0:
			return _fail("Redistribute: %s non è Popolato." % s)
		if state.spaces[s].control != "red_dust":
			return _fail("Redistribute: %s non è sotto Controllo Red Dust." % s)
		if module.count_in(state, s, "rd_rebel", "hidden") == 0:
			return _fail("Redistribute: nessun Ribelle Nascosto in %s." % s)
	var gain := 0
	for sid in spaces:
		var s := String(sid)
		act.activate(s, "rd_rebel", 1)
		gain += module.population(state, s) + module.count_in(state, s, "corp_base")
	state.add_resources("red_dust", gain, 50)
	log_lines.append("Redistribute: +%d Risorse Red Dust." % gain)
	return _done()


## §6.8 Coordinate — fino a 2 spazi senza Supporto con un Ribelle RD Nascosto:
## si Attiva un Ribelle, poi House o Repair, poi uno spostamento verso
## l'Opposizione Attiva; se già Attiva, si rimuovono 2 Truppe MG/Security oppure
## se ne sostituisce una con un Ribelle RD.
## plan = {spaces: [{id, action: "house"/"repair"/"", at_max: "remove"/"replace"}]}
func coordinate(plan: Dictionary) -> Dictionary:
	var entries: Array = plan.get("spaces", [])
	if entries.size() > 2:
		return _fail("Coordinate: al massimo due spazi.")
	for e in entries:
		var sid := String(e.get("id", ""))
		if state.spaces[sid].support > 0:
			return _fail("Coordinate: %s è sotto Supporto." % sid)
		if module.count_in(state, sid, "rd_rebel", "hidden") == 0:
			return _fail("Coordinate: nessun Ribelle Nascosto in %s." % sid)
	for e in entries:
		var sid := String(e["id"])
		act.activate(sid, "rd_rebel", 1)
		match String(e.get("action", "")):
			"house": act.house(sid, "red_dust")
			"repair": act.repair(sid, "red_dust")
		if state.spaces[sid].support != CoinEnums.Support.ACTIVE_OPPOSITION:
			act.shift(sid, -1)
		elif String(e.get("at_max", "remove")) == "replace":
			# §6.8: le Security rimosse così vanno fra le Disponibili.
			for t in ["mg_troop", "security"]:
				if module.count_in(state, sid, t) > 0:
					module.remove_pieces(state, sid, t, 1, "available")
					module.place_from_available(state, sid, "rd_rebel", 1, "hidden")
					break
		else:
			var left := 2
			for t in ["mg_troop", "security"]:
				if left <= 0:
					break
				left -= module.remove_pieces(state, sid, t, left, "available")
	return _done()


# ===========================================================================
# RECLAIMER
# ===========================================================================

## §6.10 Purify — fino a 2 spazi con forze nemiche, un Ribelle CR Nascosto e
## Controllo Reclaimer: si Attiva un Ribelle, poi si sostituisce un'unità nemica
## con un Ribelle CR (due se c'è un Conversion Center), oppure si rimpiazza una
## Base nemica indifesa con un Conversion Center.
## plan = {spaces: [{id, mode: "convert"/"occupy", targets: [type_id]}]}
func purify(plan: Dictionary) -> Dictionary:
	var entries: Array = plan.get("spaces", [])
	if entries.size() > 2:
		return _fail("Purify: al massimo due spazi.")
	for e in entries:
		var sid := String(e.get("id", ""))
		if state.spaces[sid].control != "reclaimer":
			return _fail("Purify: %s non è sotto Controllo Reclaimer." % sid)
		if module.count_in(state, sid, "cr_rebel", "hidden") == 0:
			return _fail("Purify: nessun Ribelle Nascosto in %s." % sid)
	for e in entries:
		var sid := String(e["id"])
		act.activate(sid, "cr_rebel", 1)
		if String(e.get("mode", "convert")) == "occupy":
			for base_id in ["mg_base", "corp_base", "rd_base"]:
				if module.count_in(state, sid, base_id) == 0:
					continue
				if not act.base_removable(sid, base_id):
					continue
				# §6.10: le forze CORP/EarthGov sostituite tornano fra le
				# Disponibili, non nelle Casualties.
				module.remove_pieces(state, sid, base_id, 1, "available")
				module.place_from_available(state, sid, "cr_base", 1, "conversion_center")
				_cr_draw(1)
				break
		else:
			var swaps := 2 if module.count_in(state, sid, "cr_base", "conversion_center") > 0 else 1
			# Capability #4 "The Mind Twister": una forza nemica in più per spazio.
			if module.capability_active(state, 4):
				swaps += 1
			# NB: si cicla sulle SOSTITUZIONI, non sui tipi di bersaglio: con due
			# sostituzioni disponibili e un solo tipo indicato se ne faceva una
			# sola, e il Conversion Center non serviva a niente.
			var targets: Array = e.get("targets",
				["mg_troop", "security", "eg_troop", "rd_rebel"])
			while swaps > 0:
				var done := false
				for t in targets:
					var type_id := String(t)
					var pt: PieceTypeDef = state.game_def.piece_type(type_id)
					if pt != null and pt.is_base:
						continue
					if module.remove_pieces(state, sid, type_id, 1, "available") == 0:
						continue
					module.place_from_available(state, sid, "cr_rebel", 1, "hidden")
					swaps -= 1
					done = true
					break
				if not done:
					break
	return _done()


## §6.11 Ransack — fino a 2 spazi Danneggiati con un Ribelle CR Nascosto: si
## Attiva un Ribelle e si pesca un Asset per ogni Danno presente.
## plan = {spaces: [sid]}
func ransack(plan: Dictionary) -> Dictionary:
	var spaces: Array = plan.get("spaces", [])
	if spaces.size() > 2:
		return _fail("Ransack: al massimo due spazi.")
	for sid in spaces:
		var s := String(sid)
		if module.marker(state, s, "damage") == 0:
			return _fail("Ransack: %s non ha Danni." % s)
		if module.count_in(state, s, "cr_rebel", "hidden") == 0:
			return _fail("Ransack: nessun Ribelle Nascosto in %s." % s)
	var draws := 0
	for sid in spaces:
		var s := String(sid)
		act.activate(s, "cr_rebel", 1)
		draws += module.marker(state, s, "damage")
	_cr_draw(draws)
	log_lines.append("Ransack: %d Asset card." % draws)
	# Capability #24 "AI Unleashed": il Ransack toglie anche 3 Risorse MarsGov
	# oppure 1 Profit — si sceglie col piano, di default le Risorse.
	if module.capability_active(state, 24) and not spaces.is_empty():
		if String(plan.get("ai_target", "resources")) == "profits":
			_profits(-1)
			log_lines.append("AI Unleashed: −1 Profit.")
		else:
			state.add_resources("marsgov", -3, 50)
			log_lines.append("AI Unleashed: −3 Risorse MarsGov.")
	return _done()


# ===========================================================================
# §6.9 / §6.12 AMBUSH — Red Dust e Reclaimer
# ===========================================================================

## L'Ambush non è un'azione a sé: modifica l'Attack. Verifica che gli spazi
## indicati siano fra quelli scelti per l'Attack e abbiano un Ribelle Nascosto,
## e restituisce i dadi scelti da passare a `RDROperations.attack()`.
## plan = {faction, attack_spaces: [sid], choices: {sid: [d1, d2]}}
func ambush(plan: Dictionary) -> Dictionary:
	var faction := String(plan.get("faction", "red_dust"))
	var rebel := "rd_rebel" if faction == "red_dust" else "cr_rebel"
	var attack_spaces: Array = plan.get("attack_spaces", [])
	var choices: Dictionary = plan.get("choices", {})
	if choices.size() > 2:
		return _fail("Ambush: al massimo due spazi.")
	for sid in choices.keys():
		var s := String(sid)
		if not attack_spaces.has(s):
			return _fail("Ambush: %s non è fra gli spazi scelti per l'Attack." % s)
		if module.count_in(state, s, rebel, "hidden") == 0:
			return _fail("Ambush: nessun Ribelle Nascosto in %s." % s)
		var dice: Array = choices[sid]
		if dice.size() != 2 or int(dice[0]) < 1 or int(dice[0]) > 6 \
				or int(dice[1]) < 1 or int(dice[1]) > 6:
			return _fail("Ambush: i dadi devono essere due valori da 1 a 6.")
	var out := _done()
	out["dice"] = choices
	return out

class_name RDRNonPlayerOps
extends RefCounted

## Esecuzione delle Operazioni Non-Player (§8.6) e delle Attività Speciali
## (§8.7): le procedure che il libretto *Curiosity* scrive per esteso.
##
## ARCHITETTURA. Una carta *Curiosity* non contiene procedure: contiene un
## ELENCO ORDINATO di istruzioni numerate ("① Place Bases where 3+ RD Rebels…",
## "② Select spaces using Place Rebels"). §8.6 e §8.7 dicono cosa significa
## ciascuna istruzione. Qui c'è quindi la **libreria delle istruzioni**, indicizzata
## per nome: quando arriveranno le 24 carte basterà elencarne i nomi in ordine e
## il motore le eseguirà. Le carte diventano dati, non codice.
##
## §8.5.4: le Fazioni NP non scelgono tutti gli spazi in blocco. Ne scelgono uno,
## eseguono, tirano l'Activation Number e solo se passa ne scelgono un altro.
## Per questo qui l'Operazione è eseguita uno spazio alla volta: le priorità
## rileggono la plancia dopo ogni spazio, come al tavolo.
##
## NON implementate perché serve la tabella Move Priorities, che non è nel
## libretto: Secure, Recon, March, Travel, Transport, Raid. `can_run()` lo dice.

## Operazioni che spostano pezzi: servono le Move Priorities (§8.5.7).
const NEEDS_MOVE_PRIORITIES := ["secure", "recon", "march", "travel", "transport", "raid"]

var state: GameState
var module: RDRModule
var np: RDRNonPlayer
var ops: RDROperations
var log_lines: Array[String] = []


func _init(p_np: RDRNonPlayer, p_ops: RDROperations) -> void:
	np = p_np
	ops = p_ops
	state = p_np.state
	module = p_np.module


## Si può eseguire questa Operazione per questa Fazione NP, con i dati che ci sono?
func can_run(faction: String, op_id: String) -> Dictionary:
	if NEEDS_MOVE_PRIORITIES.has(op_id):
		return {"ok": false, "error":
			"%s sposta pezzi: serve la tabella Move Priorities (§8.5.7), non riprodotta nel libretto." % op_id}
	if not np.has_table(faction):
		return {"ok": false, "error":
			"manca la tabella Space Selection Priorities di NP %s." % faction}
	return {"ok": true, "error": ""}


# ---------------------------------------------------------------------------
# Ciclo di selezione degli spazi (§8.5.4 + §8.5.6)
# ---------------------------------------------------------------------------

## Esegue `body` in uno spazio alla volta: sceglie con le priorità, esegue, tira
## l'Activation Number e continua finché il tiro passa. `candidates` è chiamata a
## ogni giro perché la plancia cambia. Restituisce gli spazi usati davvero.
func run_by_space(faction: String, column: String, candidates: Callable, body: Callable,
		activation_number: int, limited: bool = false) -> Array:
	var used: Array = []
	var cap: int = np.limited_space_cap(faction) if limited else 99
	while used.size() < cap:
		var pool: Array = []
		for sid in candidates.call():
			if not used.has(String(sid)):
				pool.append(String(sid))
		if pool.is_empty():
			break
		var pick: Dictionary = np.select_space(faction, column, pool)
		var sid2 := String(pick["space"])
		if sid2 == "":
			break
		if not bool(body.call(sid2)):
			break
		used.append(sid2)
		log_lines.append("NP %s: %s (%s)." % [faction, _name(sid2), pick["row"]])
		# §8.5.4: l'Activation Number decide se si continua.
		if activation_number <= 0:
			continue
		var check: Dictionary = np.activation_check(faction, activation_number, limited)
		if not bool(check["ok"]):
			break
	return used


# ---------------------------------------------------------------------------
# §8.6.6 NP RED DUST / §8.6.7 NP CHURCH OF THE RECLAIMER
# ---------------------------------------------------------------------------

## "Place Bases where 3+ Rebels and 1+ Hidden Rebel" (Rally).
func rally_place_bases(faction: String, activation_number: int,
		limited: bool = false) -> Array:
	var rebel := _rebel(faction)
	var column := "place_or_dig_in_bases" if faction == "red_dust" else "place_or_upgrade_bases"
	var candidates := func() -> Array:
		var out: Array = []
		for sid in ops.rally_candidates(faction):
			var s := String(sid)
			if module.count_in(state, s, rebel) >= 3 \
					and module.count_in(state, s, rebel, "hidden") >= 1 \
					and ops.act.can_place_base(s) \
					and module.available(state, _base(faction)) > 0:
				out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.rally({"faction": faction,
			"spaces": [{"id": sid, "mode": "base"}]}).get("ok", false))
	return run_by_space(faction, column, candidates, body, activation_number, limited)


## "Select spaces using Place Rebels" (Rally).
func rally_place_rebels(faction: String, activation_number: int,
		limited: bool = false) -> Array:
	var candidates := func() -> Array:
		return Array(ops.rally_candidates(faction))
	var body := func(sid: String) -> bool:
		return bool(ops.rally({"faction": faction,
			"spaces": [{"id": sid, "mode": "place"}]}).get("ok", false))
	return run_by_space(faction, "place_rebels", candidates, body, activation_number, limited)


## "Flip most Rebels where all Active": fra gli spazi con una Base propria e soli
## Ribelli Attivi, quelli con più Ribelli Attivi; lì si rimettono tutti Nascosti.
func rally_flip_hidden(faction: String, activation_number: int,
		limited: bool = false) -> Array:
	var rebel := _rebel(faction)
	var candidates := func() -> Array:
		var out: Array = []
		for sid in ops.rally_candidates(faction):
			var s := String(sid)
			if module.count_in(state, s, _base(faction)) > 0 \
					and module.count_in(state, s, rebel, "active") > 0 \
					and module.count_in(state, s, rebel, "hidden") == 0:
				out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.rally({"faction": faction,
			"spaces": [{"id": sid, "mode": "hide"}]}).get("ok", false))
	var column := "place_or_dig_in_bases" if faction == "red_dust" else "place_or_upgrade_bases"
	return run_by_space(faction, column, candidates, body, activation_number, limited)


## §8.6.6 "Dig In": un solo Deserto, alla fine del Rally (nessun tiro di AN).
func rally_dig_in() -> String:
	var pool: Array = []
	for sid in module.mars_spaces(state):
		if module.is_desert(state, String(sid)) \
				and module.count_in(state, String(sid), "rd_base", "basic") > 0:
			pool.append(String(sid))
	if pool.is_empty():
		return ""
	var pick: Dictionary = np.select_space("red_dust", "place_or_dig_in_bases", pool)
	var sid2 := String(pick["space"])
	if sid2 != "":
		ops.rally({"faction": "red_dust", "spaces": [{"id": sid2, "mode": "place"}],
			"dig_in": sid2})
		log_lines.append("NP red_dust: Base Dug-In a %s." % _name(sid2))
	return sid2


## §8.6.6/§8.6.7 Attack. `mode` sceglie quale delle tre istruzioni della carta:
##   "support"      — spazi a Supporto (RD) / a Supporto o Opposizione (CR)
##   "three_rebels" — spazi con 3+ Ribelli propri (RD: e senza Opposizione)
##   "all_active"   — spazi dove tutti i propri Ribelli sono già Attivi
func attack(faction: String, mode: String, activation_number: int,
		limited: bool = false) -> Array:
	var rebel := _rebel(faction)
	var candidates := func() -> Array:
		var out: Array = []
		for sid in module.mars_spaces(state):
			var s := String(sid)
			if not ops.act.selectable(s, ops.act.storm_free(faction)):
				continue
			if module.count_in(state, s, rebel) == 0:
				continue
			if ops._enemy_force_count(s, faction) == 0:
				continue
			var sup: int = state.spaces[s].support
			match mode:
				"support":
					if faction == "red_dust":
						if sup <= 0:
							continue
					elif sup == CoinEnums.Support.NEUTRAL:
						continue
				"three_rebels":
					if module.count_in(state, s, rebel) < 3:
						continue
					if faction == "red_dust" and sup < 0:
						continue
				"all_active":
					if module.count_in(state, s, rebel, "hidden") > 0:
						continue
			out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.attack({"faction": faction, "spaces": [sid]}).get("ok", false))
	return run_by_space(faction, "attack", candidates, body, activation_number, limited)


## §8.6.6 Campaign — Red Dust. Se lo spazio ha una Base RD e Ribelli Nascosti,
## lo si sceglie solo se almeno un Ribelle resterebbe Nascosto.
func campaign(activation_number: int, limited: bool = false) -> Array:
	var candidates := func() -> Array:
		var out: Array = []
		for sid in module.mars_spaces(state):
			var s := String(sid)
			if not ops.act.selectable(s):
				continue
			if module.population(state, s) <= 0 or module.count_in(state, s, "rd_rebel") == 0:
				continue
			if module.count_in(state, s, "rd_base") > 0 \
					and module.count_in(state, s, "rd_rebel", "hidden") > 0 \
					and module.count_in(state, s, "rd_rebel", "hidden") < 2:
				continue  # resterebbe scoperta la Base
			out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.campaign({"spaces": [sid]}).get("ok", false))
	return run_by_space("red_dust", "shift_active_opposition", candidates, body,
		activation_number, limited)


## §8.6.7 Preach — Reclaimer. Stessa cautela sulla Base scoperta.
func preach(activation_number: int, limited: bool = false) -> Array:
	var candidates := func() -> Array:
		var out: Array = []
		for sid in module.mars_spaces(state):
			var s := String(sid)
			if not ops.act.selectable(s, ops.act.storm_free("reclaimer")):
				continue
			if module.population(state, s) <= 0 or module.count_in(state, s, "cr_rebel") == 0:
				continue
			if module.count_in(state, s, "cr_base") > 0 \
					and module.count_in(state, s, "cr_rebel", "hidden") > 0 \
					and module.count_in(state, s, "cr_rebel", "hidden") < 2:
				continue
			out.append(s)
		return out
	var body := func(sid: String) -> bool:
		return bool(ops.preach({"spaces": [sid]}).get("ok", false))
	return run_by_space("reclaimer", "place_damage", candidates, body,
		activation_number, limited)


# ---------------------------------------------------------------------------

func _rebel(faction: String) -> String:
	return "cr_rebel" if faction == "reclaimer" else "rd_rebel"


func _base(faction: String) -> String:
	return "cr_base" if faction == "reclaimer" else "rd_base"


func _name(sid: String) -> String:
	var sd: SpaceDef = state.game_def.space(sid)
	return sd.name if sd != null else sid

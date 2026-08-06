class_name RDROperations
extends RefCounted

## Le Operazioni (§5.0).
##
## COIN: Train (MG), Logistics (CORP), Secure, Recon, Assault.
## Ribelli: Rally, March (RD), Travel (CR), Attack, Campaign (RD), Preach (CR).
##
## Ogni Operazione riceve un `plan` (le scelte del giocatore) e restituisce
## `{ok: bool, error: String, spent: int}`. Le validazioni sono fatte prima di
## toccare lo stato: se `ok` è false nulla è stato modificato.
##
## NOTA sui Reclaimer: pagano le Risorse scartando Asset card (§1.5). Se `cards`
## è collegato le carte vengono scartate davvero, col valore maggiorato quando la
## carta nomina l'Operazione in corso; altrimenti il costo finisce in
## `state.tracks["cr_unpaid"]` e resta solo annotato nel log.

var state: GameState
var module: RDRModule
var act: RDRActions
var rng: RandomNumberGenerator
## Serve a Logistics e al Passo delle Corporations per l'Aldrin Cycler.
var rounds: RDRRounds = null
## Mazzi Asset e Campaign: se collegati, i Reclaimer pagano davvero e le
## Campaign card entrano in gioco.
var cards: RDRCards = null
var log_lines: Array[String] = []
## Operazione in corso, per il valore maggiorato delle Asset card (§1.5).
var _current_op := ""
## Spazi in cui l'Assault in corso ha tolto forze Reclaimer (Capability #3).
var _cr_metabolism_spaces: Array[String] = []
## §7.0: le Operazioni gratuite concesse dagli Eventi non costano Risorse (né
## Asset card per i Reclaimer).
var free := false

## Ganci del sistema Non-Player, riempiti da `RDRNonPlayerOps`. Servono dove
## un'Operazione fa una scelta che al tavolo spetterebbe al giocatore e che per
## un bot va invece letta dalle tabelle §8.5.6 e §8.5.8.
## `np_piece_order.call(acting, sid, purpose) -> Array[String]` (Piece Priorities)
## `np_space_order.call(acting, column, candidates) -> String` (Space Selection)
var np_piece_order: Callable = Callable()
var np_space_order: Callable = Callable()


func _init(p_state: GameState, p_module: RDRModule, p_rng: RandomNumberGenerator = null) -> void:
	state = p_state
	module = p_module
	act = RDRActions.new(p_state, p_module)
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


func _flush() -> void:
	log_lines.append_array(act.log_lines)
	act.log_lines.clear()


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "spent": 0}


func _done(spent: int) -> Dictionary:
	_flush()
	module.recompute_all_control(state)
	module.refresh_victory_tracks(state)
	return {"ok": true, "error": "", "spent": spent}


## §5.0: il costo si paga dopo aver risolto tutti gli spazi, e non si possono
## scegliere più spazi di quanti se ne possano pagare.
func _can_pay(faction: String, cost: int) -> bool:
	# §8.5.4: «NP Factions do not track or spend Resources». I Reclaimer NP, in
	# particolare, non hanno una mano di Asset card ma un Asset Total.
	if free or module.is_np(state, faction):
		return true
	if faction == "corporations":
		return true  # le Corporations non spendono Risorse per le Operazioni
	if faction == "reclaimer":
		# §1.5: deve poter coprire il costo con le Asset card in mano.
		if cards == null:
			return true
		var total := 0
		for number in cards.hand():
			total += cards.value_of(int(number), _current_op)
		return total >= cost
	return state.get_resources(faction) >= cost


func _pay(faction: String, cost: int) -> void:
	if cost <= 0:
		return
	if module.is_np(state, faction):
		return   # §8.5.4: le Fazioni NP non spendono Risorse
	if free:
		log_lines.append("Operazione gratuita: %d Risorse non pagate." % cost)
		return
	if faction == "reclaimer":
		if cards == null:
			state.tracks["cr_unpaid"] = int(state.tracks.get("cr_unpaid", 0)) + cost
			log_lines.append("I Reclaimer pagherebbero %d Risorse scartando Asset card (mazzi non collegati)." % cost)
			return
		cards.pay(cost, _current_op)
		log_lines.append_array(cards.log_lines)
		cards.log_lines.clear()
		return
	if faction == "corporations":
		return
	state.add_resources(faction, -cost, 50)


func _eg_controlled_by(faction: String) -> bool:
	return module.eg_controller(state) == faction


## Unità che una Fazione COIN può muovere (le Truppe EG solo se ne è Controller).
func _coin_unit_types(faction: String) -> Array[String]:
	var out: Array[String] = []
	if faction == "marsgov":
		out.append("mg_troop")
	else:
		out.append("security")
		out.append("specops")
	if _eg_controlled_by(faction):
		out.append("eg_troop")
	return out


# ===========================================================================
# §5.1 TRAIN — MarsGov
# ===========================================================================

## Spazi selezionabili: qualsiasi spazio con Base MG, o Labirinti con Controllo COIN.
func train_candidates() -> PackedStringArray:
	var out := PackedStringArray()
	for sid in module.mars_spaces(state):
		if not act.selectable(sid):
			continue
		if module.count_in(state, sid, "mg_base") > 0 \
				or (module.is_labyrinth(state, sid) and state.spaces[sid].control == "coin"):
			out.append(sid)
	return out


## plan = {spaces: [{id, troops}], pacify: {id, actions: ["house"/"repair"/"shift"]}}
func train(plan: Dictionary) -> Dictionary:
	var entries: Array = plan.get("spaces", [])
	if entries.is_empty():
		return _fail("Train: nessuno spazio scelto.")
	var candidates := train_candidates()
	var paid_spaces := 0
	for e in entries:
		var sid := String(e.get("id", ""))
		if not candidates.has(sid):
			return _fail("Train: %s non è selezionabile." % sid)
		if int(e.get("troops", 0)) > 0:
			paid_spaces += 1
	var cost := paid_spaces * 3 + _campaign_cost("marsgov", "train", plan.get("spaces", []).map(
		func(e): return String(e.get("id", ""))))
	if not _can_pay("marsgov", cost):
		return _fail("Train: Risorse insufficienti (%d)." % cost)

	for e in entries:
		var sid := String(e.get("id", ""))
		var want: int = mini(4, int(e.get("troops", 0)))
		if want > 0:
			module.place_from_available(state, sid, "mg_troop", want)
	_pay("marsgov", cost)

	# §5.1: si può Pacify in UNO degli spazi selezionati con Controllo COIN.
	var pac: Dictionary = plan.get("pacify", {})
	if not pac.is_empty():
		var pid := String(pac.get("id", ""))
		var listed := false
		for e in entries:
			if String(e.get("id", "")) == pid:
				listed = true
		if not listed:
			return _fail("Train: Pacify solo in uno spazio selezionato.")
		module.recompute_all_control(state)
		act.pacify(pid, pac.get("actions", []))
	return _done(cost)


# ===========================================================================
# §5.2 LOGISTICS — Corporations
# ===========================================================================

## plan = {earth: {security, specops, extra}, transit: bool, deserts: [sid],
##         security_at: [sid]}
func logistics(plan: Dictionary) -> Dictionary:
	var earth: Dictionary = plan.get("earth", {})
	var deserts: Array = plan.get("deserts", [])
	var profits := int(state.tracks.get("profits", 0))

	# Earth: fino a 4 unità (max 1 SpecOps); le eccedenti costano 1 Profit l'una.
	var sec := int(earth.get("security", 0))
	var spec := int(earth.get("specops", 0))
	if spec > 1 + int(earth.get("extra", 0)):
		return _fail("Logistics: al massimo 1 SpecOps gratuito su Earth.")
	var units := sec + spec
	var extra: int = maxi(0, units - 4)
	# Le Basi Terraforming: la prima è gratis, ogni Deserto successivo costa 3 Profits.
	var upgrade_cost: int = maxi(0, deserts.size() - 1) * 3
	var sec_at: Array = plan.get("security_at", [])
	var total_cost := extra + upgrade_cost + sec_at.size()
	if profits < total_cost:
		return _fail("Logistics: Profits insufficienti (%d)." % total_cost)

	for sid in deserts:
		if not module.is_desert(state, String(sid)) or module.count_in(state, String(sid), "corp_base") == 0:
			return _fail("Logistics: %s non ha una Base CORP in un Deserto." % sid)

	if sec > 0:
		module.place_from_available(state, "earth", "security", sec)
	if spec > 0:
		module.place_from_available(state, "earth", "specops", spec, "hidden")

	# §5.2: selezionando Transit si risolve l'Aldrin Cycler.
	if bool(plan.get("transit", false)) and module.campaign_active(state, 11):
		return _fail("Campaign «Comms Cutoff»: Logistics non può selezionare Transit.")
	if bool(plan.get("transit", false)):
		if rounds != null:
			rounds.aldrin_cycler()
			log_lines.append_array(rounds.log_lines)
			rounds.log_lines.clear()
		else:
			log_lines.append("Logistics: Aldrin Cycler non collegato.")

	for sid in deserts:
		var s := String(sid)
		if module.count_in(state, s, "corp_base", "basic") > 0:
			state.spaces[s].remove_piece("corporations", "corp_base", 1, "basic")
			state.spaces[s].add_piece("corporations", "corp_base", 1, "terraforming")

	# Infine, 1 Security a ogni Base CORP pagando 1 Profit l'una.
	for sid in sec_at:
		var s := String(sid)
		if module.count_in(state, s, "corp_base") > 0:
			module.place_from_available(state, s, "security", 1)

	state.tracks["profits"] = profits - total_cost
	return _done(total_cost)


# ===========================================================================
# Movimento condiviso da Secure / Recon / March / Travel
# ===========================================================================

## Costo aggiuntivo delle Operazioni MarsGov per le Campaign card attive.
## #10 "General Strike": +1 Risorsa per spazio senza Supporto.
## #9 "Legal Injunctions": ogni spazio in Opposizione scelto per Secure costa 6.
func _campaign_cost(faction: String, op_id: String, spaces: Array) -> int:
	if faction != "marsgov":
		return 0
	var extra := 0
	for sid in spaces:
		var st: SpaceState = state.spaces[String(sid)]
		if module.campaign_active(state, 10) and st.support <= 0:
			extra += 1
		if module.campaign_active(state, 9) and op_id == "secure" and st.support < 0:
			extra += 3   # 3 base + 3 = 6 Risorse per quello spazio
	return extra


## §5.3/§5.7: destinazioni raggiungibili da `origin`. Un passo di adiacenza,
## più tutti i salti che si vogliono via Maglev e Spaceport; ci si ferma appena
## si entra in un Labirinto sotto Controllo nemico.
func reachable_labyrinths(origin: String, control: String) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {origin: true}
	var queue: Array[String] = []

	# Primo passo: adiacenza (una sola volta).
	var sd: SpaceDef = state.game_def.space(origin)
	if sd != null and act.can_leave(origin):
		for a in sd.adjacent:
			var s := String(a)
			if module.is_labyrinth(state, s) and act.can_enter(s) and not seen.has(s):
				seen[s] = true
				out.append(s)
				if not _enemy_controlled(s, control):
					queue.append(s)
	# Da qualunque Labirinto raggiunto (e dall'origine se è un Labirinto) si
	# prosegue via Maglev e Spaceport.
	if module.is_labyrinth(state, origin):
		queue.append(origin)
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		# Campaign #4 "Transport Workers": il Secure non può usare i Maglev.
		var hops := PackedStringArray() if (control == "coin" and module.campaign_active(state, 4)) \
			else act.maglev_links(cur)
		for s in act.spaceport_links(cur, control):
			hops.append(s)
		for h in hops:
			var s := String(h)
			if seen.has(s) or not act.can_enter(s):
				continue
			seen[s] = true
			out.append(s)
			if not _enemy_controlled(s, control):
				queue.append(s)
	return out


## §5.4: le destinazioni Deserto si raggiungono per adiacenza, oppure partendo da
## un Labirinto con Spaceport (dopo essersi spostati fra Spaceport).
func reachable_deserts(origin: String, control: String) -> PackedStringArray:
	var out := PackedStringArray()
	var hubs: Array[String] = [origin]
	if module.is_labyrinth(state, origin):
		for s in act.spaceport_links(origin, control):
			hubs.append(String(s))
	for hub in hubs:
		var sd: SpaceDef = state.game_def.space(hub)
		if sd == null or not act.can_leave(hub):
			continue
		for a in sd.adjacent:
			var s := String(a)
			if module.is_desert(state, s) and act.can_enter(s) and not out.has(s):
				out.append(s)
	return out


## Spazi da cui `type_id` può raggiungere `dest` con quell'Operazione. Stava solo
## nella scena; serve anche al sistema Non-Player, quindi vive qui.
## §6.3: gli spazi che il Transport collega senza attivarne altri — Phobos e
## ogni spazio con una Base MarsGov. `extra` aggiunge quelli attivati apposta.
func transport_pool(extra: Array = []) -> PackedStringArray:
	var out := PackedStringArray(["phobos"])
	for sid in module.mars_spaces(state):
		if module.count_in(state, String(sid), "mg_base") > 0:
			out.append(String(sid))
	for sid in extra:
		if not Array(out).has(String(sid)):
			out.append(String(sid))
	return out


func legal_origins(op_id: String, faction: String, dest: String,
		type_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var control := "coin" if op_id in ["secure", "recon"] \
		else ("red_dust" if op_id == "march" else "reclaimer")
	var dest_def: SpaceDef = state.game_def.space(dest)
	if dest_def == null:
		return out
	# §6.3 Transport: non si va per adiacenza ma per rete — Phobos, gli spazi con
	# una Base MG e quelli attivati in più sono tutti collegati fra loro.
	if op_id == "transport":
		for sid in transport_pool():
			var s2 := String(sid)
			if s2 != dest and module.count_in(state, s2, type_id) > 0:
				out.append(s2)
		return out
	for s in state.game_def.spaces:
		if s.id == dest or module.count_in(state, s.id, type_id) == 0:
			continue
		if op_id == "travel":
			# §5.8: le forze Reclaimer si spostano di uno spazio adiacente.
			if Array(dest_def.adjacent).has(s.id):
				out.append(s.id)
			continue
		var reach := reachable_labyrinths(s.id, control)
		if op_id in ["recon", "march"]:
			for x in reachable_deserts(s.id, control):
				reach.append(x)
		if Array(reach).has(dest):
			out.append(s.id)
	return out


## Come sopra, per più tipi di unità in una volta sola.
func legal_origins_for(op_id: String, faction: String, dest: String,
		types: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for t in types:
		for sid in legal_origins(op_id, faction, dest, String(t)):
			if not Array(out).has(String(sid)):
				out.append(String(sid))
	return out


func _enemy_controlled(sid: String, control: String) -> bool:
	var c: String = state.spaces[sid].control
	return c != "" and c != control


## Esegue gli spostamenti dichiarati validandoli contro `allowed`.
func _resolve_moves(moves: Array, allowed_types: Array[String],
		control: String, dest_kind: String) -> String:
	for m in moves:
		var from_sid := String(m.get("from", ""))
		var to_sid := String(m.get("to", ""))
		var type_id := String(m.get("type", ""))
		var n := int(m.get("count", 0))
		if not allowed_types.has(type_id):
			return "%s non è un'unità che questa Operazione può muovere." % type_id
		if module.count_in(state, from_sid, type_id) < n:
			return "%s: unità insufficienti in %s." % [type_id, from_sid]
		var reach := reachable_labyrinths(from_sid, control) if dest_kind == "labyrinth" \
			else reachable_deserts(from_sid, control)
		if not reach.has(to_sid):
			return "%s non è raggiungibile da %s." % [to_sid, from_sid]
	for m in moves:
		module.move_pieces(state, String(m["from"]), String(m["to"]),
			String(m["type"]), int(m["count"]))
	return ""


# ===========================================================================
# §5.3 SECURE / §5.4 RECON — MarsGov e Corporations
# ===========================================================================

## plan = {faction, dest: [sid], moves: [{from,to,type,count}], base_at: [sid],
##         house_repair: {id, action}, drop_pods: [sid]}
func secure(plan: Dictionary) -> Dictionary:
	return _secure_or_recon(plan, "labyrinth")


## plan = come Secure; `beacons` sostituisce `drop_pods` (§5.4).
func recon(plan: Dictionary) -> Dictionary:
	return _secure_or_recon(plan, "desert")


func _secure_or_recon(plan: Dictionary, kind: String) -> Dictionary:
	var faction := String(plan.get("faction", "marsgov"))
	var dest: Array = plan.get("dest", [])
	if dest.is_empty():
		return _fail("Nessuna destinazione scelta.")
	var beacons: Array = plan.get("beacons", [])
	for sid in dest:
		var s := String(sid)
		if kind == "labyrinth" and not module.is_labyrinth(state, s):
			return _fail("Secure: %s non è un Labirinto." % s)
		if kind == "desert" and not module.is_desert(state, s):
			return _fail("Recon: %s non è un Deserto." % s)
		# §5.4 Navigation Beacons: un Satellite rende selezionabile un Deserto
		# in tempesta, altrimenti la Raging Storm lo esclude.
		if not act.selectable(s) and not beacons.has(s):
			return _fail("%s è sotto Raging Storm." % s)

	# §5.3/§5.4: MarsGov paga 3 Risorse per destinazione (nel Secure solo quelle
	# dove le unità si fermano davvero; qui il piano elenca già quelle).
	var cost := 3 * dest.size() if faction == "marsgov" else 0
	cost += _campaign_cost(faction, "secure" if kind == "labyrinth" else "recon", dest)
	if not _can_pay(faction, cost):
		return _fail("Risorse insufficienti (%d)." % cost)

	var allowed := _coin_unit_types(faction)
	var err := _resolve_moves(plan.get("moves", []), allowed, "coin", kind)
	if err != "":
		return _fail(err)

	# Satelliti dall'Orbita: Drop Pods (Secure) e Navigation Beacons (Recon).
	if _eg_controlled_by(faction):
		for sid in plan.get("drop_pods", []):
			if module.count_in(state, "orbit", "satellite") > 0:
				module.move_pieces(state, "orbit", String(sid), "satellite", 1)
		for sid in beacons:
			if module.count_in(state, "orbit", "satellite") > 0:
				module.move_pieces(state, "orbit", String(sid), "satellite", 1)

	# Attivazione dei Ribelli: 1 per unità propria presente (1 ogni 2 nella
	# Wilderness), più 2 per ogni Navigation Beacon senza tempesta.
	for sid in dest:
		var s := String(sid)
		var units := 0
		for t in allowed:
			units += module.count_in(state, s, t)
		# Capability #25 "Genetic Masking": dove c'è una Base CR, il Secure e il
		# Recon contano 2 unità COIN in meno.
		if module.capability_active(state, 25) and module.count_in(state, s, "cr_base") > 0:
			units = maxi(0, units - 2)
		var n := units
		if s == "wilderness":
			n = int(units / 2.0)
		if beacons.has(s) and not module.has_raging_storm(state, s):
			n += 2
		act.activate_any_rebel(s, n)

	# Si può rimuovere una Security (CORP) o una Truppa MG per piazzare una Base.
	var base_unit := "mg_troop" if faction == "marsgov" else "security"
	var base_type := "mg_base" if faction == "marsgov" else "corp_base"
	for sid in plan.get("base_at", []):
		var s := String(sid)
		if not dest.has(s) or not act.can_place_base(s):
			continue
		if module.count_in(state, s, base_unit) == 0:
			continue
		# §5.3: le Security rimosse per piazzare una Base vanno fra le Disponibili,
		# non nelle Casualties.
		module.remove_pieces(state, s, base_unit, 1, "available")
		module.place_from_available(state, s, base_type, 1)

	_pay(faction, cost)
	module.recompute_all_control(state)

	# House o Repair una volta, in una destinazione con Controllo COIN.
	var hr: Dictionary = plan.get("house_repair", {})
	if not hr.is_empty():
		var sid := String(hr.get("id", ""))
		if dest.has(sid) and state.spaces[sid].control == "coin":
			if String(hr.get("action", "")) == "house":
				act.house(sid, faction, String(hr.get("eg", "EG+")))
			else:
				act.repair(sid, faction, String(hr.get("eg", "EG+")))
	return _done(cost)


# ===========================================================================
# §5.5 ASSAULT — MarsGov e Corporations
# ===========================================================================

## plan = {faction, spaces: [sid], activate_specops: [sid], bombard: [sid],
##         suppress: {id, dest: {rebel_type: sid}}, free_attacks: [...] }
func assault(plan: Dictionary) -> Dictionary:
	var faction := String(plan.get("faction", "marsgov"))
	var spaces: Array = plan.get("spaces", [])
	if spaces.is_empty():
		return _fail("Assault: nessuno spazio scelto.")
	var allowed := _coin_unit_types(faction)
	for sid in spaces:
		var s := String(sid)
		if not act.selectable(s):
			return _fail("Assault: %s è sotto Raging Storm." % s)
		var own := 0
		for t in allowed:
			own += module.count_in(state, s, t)
		if own == 0:
			return _fail("Assault: nessuna forza propria in %s." % s)
	var cost := 3 * spaces.size() if faction == "marsgov" else 0
	cost += _campaign_cost(faction, "assault", spaces)
	if not _can_pay(faction, cost):
		return _fail("Assault: Risorse insufficienti (%d)." % cost)

	_cr_metabolism_spaces.clear()
	# Le Corporations possono rivelare SpecOps prima di risolvere.
	for sid in plan.get("activate_specops", []):
		act.activate(String(sid), "specops", 99)

	var free_attackers: Array = []
	for sid in spaces:
		var s := String(sid)
		var hits := 0
		for t in allowed:
			if t == "specops":
				hits += module.count_in(state, s, t, "active")
			else:
				hits += module.count_in(state, s, t)
		# §5.5 Bombard: un Satellite dall'Orbita rimuove 2 forze nemiche in più
		# e piazza un Danno se il bersaglio è un Labirinto.
		var bombard: bool = plan.get("bombard", []).has(s) and _eg_controlled_by(faction) \
			and module.count_in(state, "orbit", "satellite") > 0
		if bombard:
			module.move_pieces(state, "orbit", s, "satellite", 1)
			hits += 2

		# Campaign #6 "Mothers of Mars": ogni Labirinto scelto per l'Assault
		# scivola di un livello verso l'Opposizione Attiva.
		if module.campaign_active(state, 6) and module.is_labyrinth(state, s):
			act.shift(s, -1)
		var before_rd := module.count_in(state, s, "rd_rebel") + module.count_in(state, s, "rd_base")
		var before_cr := module.count_in(state, s, "cr_rebel") + module.count_in(state, s, "cr_base")
		var removed: Array[String] = []
		if bombard and module.capability_active(state, 6):
			# Capability #6 "Deep Tunneling": i 2 colpi in più del Bombard non
			# possono toccare le forze Reclaimer.
			removed = act.remove_enemy_forces(s, ["rd_rebel", "rd_base"], 2, true)
			removed.append_array(act.remove_enemy_forces(
				s, ["rd_rebel", "cr_rebel", "rd_base", "cr_base"], hits - 2, true))
		else:
			removed = act.remove_enemy_forces(
				s, ["rd_rebel", "cr_rebel", "rd_base", "cr_base"], hits, true)
		# Capability #3 "Enhanced Metabolism": dove i Reclaimer hanno perso
		# qualcosa potranno rimettere un Ribelle a fine Assault.
		if module.count_in(state, s, "cr_rebel") + module.count_in(state, s, "cr_base") < before_cr:
			_cr_metabolism_spaces.append(s)
		if bombard and module.is_labyrinth(state, s):
			act.place_damage(s)

		# §5.5 Mercenaries: +1 Profit ogni 2 forze Ribelli rimosse in uno spazio
		# con Security o SpecOps Attivi (anche durante un Assault MarsGov).
		if module.count_in(state, s, "security") > 0 or module.count_in(state, s, "specops", "active") > 0:
			var merc := int(removed.size() / 2.0)
			if merc > 0:
				state.tracks["profits"] = clampi(int(state.tracks.get("profits", 0)) + merc, 0, 50)

		# §5.5: nei Labirinti (o presso una Base RD Dug-In) i Ribelli colpiti
		# possono rispondere con un Attack gratuito, se ne resta almeno uno.
		var dug_in := module.count_in(state, s, "rd_base", "dug_in") > 0
		if module.is_labyrinth(state, s) or dug_in:
			var after_rd := module.count_in(state, s, "rd_rebel") + module.count_in(state, s, "rd_base")
			var after_cr := module.count_in(state, s, "cr_rebel") + module.count_in(state, s, "cr_base")
			if before_rd > after_rd and module.count_in(state, s, "rd_rebel") > 0 \
					and (module.is_labyrinth(state, s) or dug_in):
				free_attackers.append({"space": s, "faction": "red_dust"})
			if before_cr > after_cr and module.count_in(state, s, "cr_rebel") > 0 \
					and module.is_labyrinth(state, s):
				free_attackers.append({"space": s, "faction": "reclaimer"})

	_pay(faction, cost)

	# §5.5 Suppress: in uno spazio NON scelto per l'Assault con Truppe EG e
	# Ribelli, il Controller sposta Ribelli fino al numero delle Truppe EG.
	var sup: Dictionary = plan.get("suppress", {})
	if not sup.is_empty() and _eg_controlled_by(faction):
		var sid := String(sup.get("id", ""))
		if not spaces.has(sid) and module.count_in(state, sid, "eg_troop") > 0:
			var budget := module.count_in(state, sid, "eg_troop")
			for entry in sup.get("moves", []):
				if budget <= 0:
					break
				var t := String(entry.get("type", "rd_rebel"))
				var to_sid := String(entry.get("to", ""))
				if not module.is_desert(state, to_sid):
					continue
				if not state.game_def.space(sid).adjacent.has(to_sid):
					continue
				var n: int = mini(budget, int(entry.get("count", 1)))
				budget -= module.move_pieces(state, sid, to_sid, t, n)
			if state.spaces[sid].support < 0:
				act.shift(sid, 1)

	# Gli Attack gratuiti di risposta si risolvono senza costo.
	for fa in free_attackers:
		_resolve_attack_space(String(fa["space"]), String(fa["faction"]), [])

	# Capability #3 "Enhanced Metabolism": dopo un Assault che ha tolto forze
	# Reclaimer, i Reclaimer rimettono un Ribelle in uno di quegli spazi. La
	# scelta spetterebbe a loro, ma cade nel mezzo dell'Assault di qualcun altro
	# e l'interfaccia non la sa ancora chiedere: si prende il primo spazio, che
	# è anche esattamente quel che prescrive la scheda per i Reclaimer NP
	# («place a Rebel into the first Assault space where any CR forces are
	# moved»). `cr_metabolism` nel piano permette di indicarne un altro.
	if module.capability_active(state, 3) and not _cr_metabolism_spaces.is_empty():
		var wanted := String(plan.get("cr_metabolism", ""))
		var back: String = wanted if _cr_metabolism_spaces.has(wanted) \
			else String(_cr_metabolism_spaces[0])
		if module.place_from_available(state, back, "cr_rebel", 1, "hidden") > 0:
			log_lines.append("Enhanced Metabolism: 1 Ribelle Reclaimer torna in %s." %
				state.game_def.space(back).name)
	return _done(cost)


# ===========================================================================
# §5.6 RALLY — Red Dust e Reclaimer
# ===========================================================================

## Spazi selezionabili: Red Dust in spazi Popolati senza Supporto, Reclaimer in
## spazi Neutrali di Mars.
func rally_candidates(faction: String) -> PackedStringArray:
	var out := PackedStringArray()
	var storm_free := act.storm_free(faction)
	for sid in module.mars_spaces(state):
		if not act.selectable(sid, storm_free):
			continue
		var st: SpaceState = state.spaces[sid]
		if faction == "red_dust":
			if module.population(state, sid) > 0 and st.support <= 0:
				out.append(sid)
		else:
			if st.support == CoinEnums.Support.NEUTRAL:
				out.append(sid)
	return out


## plan = {faction, spaces: [{id, mode}], dig_in: sid}
## mode: "place" (1 Ribelle) · "base" (2 Ribelli → Base) · "fill" (Ribelli fino a
## Popolazione + Basi) · "hide" (tutti Nascosti) · "upgrade" (solo Reclaimer).
func rally(plan: Dictionary) -> Dictionary:
	_current_op = "rally"
	var faction := String(plan.get("faction", "red_dust"))
	var rebel := "rd_rebel" if faction == "red_dust" else "cr_rebel"
	var base := "rd_base" if faction == "red_dust" else "cr_base"
	var entries: Array = plan.get("spaces", [])
	if entries.is_empty():
		return _fail("Rally: nessuno spazio scelto.")
	var candidates := rally_candidates(faction)
	for e in entries:
		if not candidates.has(String(e.get("id", ""))):
			return _fail("Rally: %s non è selezionabile." % e.get("id", ""))
	var cost := entries.size()
	if not _can_pay(faction, cost):
		return _fail("Rally: Risorse insufficienti (%d)." % cost)

	for e in entries:
		var sid := String(e["id"])
		var mode := String(e.get("mode", "place"))
		# §1.5: la Capability #23 fa contare i Satelliti come una Base CR in più;
		# la #5 permette ai Reclaimer "fill" e "hide" anche senza Base.
		var has_base := (module.cr_bases_in(state, sid) > 0) if faction == "reclaimer" \
			else module.count_in(state, sid, base) > 0
		if faction == "reclaimer" and module.capability_active(state, 5):
			has_base = true
		match mode:
			"place":
				module.place_from_available(state, sid, rebel, 1, "hidden")
			"base":
				if module.count_in(state, sid, rebel) >= 2 and act.can_place_base(sid):
					module.remove_pieces(state, sid, rebel, 2, "available")
					# Campaign #1 "Construction Workers Guild": le nuove Basi RD
					# si piazzano già sul lato Dug-In.
					var side := "dug_in" if (base == "rd_base" and module.campaign_active(state, 1)) else ""
					module.place_from_available(state, sid, base, 1, side)
			"fill":
				if has_base:
					var n := module.population(state, sid) + (module.cr_bases_in(state, sid) \
						if faction == "reclaimer" else module.count_in(state, sid, base))
					module.place_from_available(state, sid, rebel, n, "hidden")
			"hide":
				if has_base:
					act.hide(sid, rebel, 99)
			"upgrade":
				# §5.6: solo i Reclaimer, e la Base diventa Conversion Center.
				if faction == "reclaimer" and module.count_in(state, sid, base, "basic") > 0:
					state.spaces[sid].remove_piece("reclaimer", base, 1, "basic")
					state.spaces[sid].add_piece("reclaimer", base, 1, "conversion_center")
					if cards != null:
						cards.draw_asset(1)
						log_lines.append_array(cards.log_lines)
						cards.log_lines.clear()
					else:
						log_lines.append("I Reclaimer pescherebbero 1 Asset card (mazzi non collegati).")

	# §5.6: il Red Dust può poi potenziare UNA Base in un Deserto a Dug-In, anche
	# fuori dagli spazi scelti e anche in un'Operazione Limitata.
	var dig := String(plan.get("dig_in", ""))
	if faction == "red_dust" and dig != "":
		if module.is_desert(state, dig) and module.count_in(state, dig, "rd_base", "basic") > 0:
			state.spaces[dig].remove_piece("red_dust", "rd_base", 1, "basic")
			state.spaces[dig].add_piece("red_dust", "rd_base", 1, "dug_in")
	_pay(faction, cost)
	return _done(cost)


# ===========================================================================
# §5.7 MARCH (Red Dust) / §5.8 TRAVEL (Reclaimer)
# ===========================================================================

## plan = {dest: [sid], moves: [{from,to,count}]}
func march(plan: Dictionary) -> Dictionary:
	_current_op = "march"
	var dest: Array = plan.get("dest", [])
	if dest.is_empty():
		return _fail("March: nessuna destinazione scelta.")
	for sid in dest:
		if not act.selectable(String(sid)):
			return _fail("March: %s è sotto Raging Storm." % sid)
	var cost := dest.size()
	if not _can_pay("red_dust", cost):
		return _fail("March: Risorse insufficienti (%d)." % cost)

	# I gruppi in movimento si controllano per origine (§5.7).
	var groups: Array = plan.get("moves", [])
	for m in groups:
		var from_sid := String(m.get("from", ""))
		var to_sid := String(m.get("to", ""))
		var n := int(m.get("count", 0))
		if module.count_in(state, from_sid, "rd_rebel") < n:
			return _fail("March: Ribelli insufficienti in %s." % from_sid)
		var reach := reachable_labyrinths(from_sid, "red_dust")
		for s in reachable_deserts(from_sid, "red_dust"):
			reach.append(s)
		if not reach.has(to_sid):
			return _fail("March: %s non è raggiungibile da %s." % [to_sid, from_sid])

	for m in groups:
		var from_sid := String(m["from"])
		var to_sid := String(m["to"])
		var n := int(m["count"])
		module.move_pieces(state, from_sid, to_sid, "rd_rebel", n)
		_moving_rebels_reveal(to_sid, "rd_rebel", n)
	_pay("red_dust", cost)
	return _done(cost)


## §5.7/§5.8: in una destinazione con Supporto, se i Ribelli in arrivo da una
## singola origine più i cubi e gli SpecOps presenti superano 3, quei Ribelli si
## Attivano. Chi entra nella Wilderness si Nasconde comunque.
func _moving_rebels_reveal(to_sid: String, rebel: String, n: int) -> void:
	if to_sid == "wilderness":
		act.hide(to_sid, rebel, 99)
		return
	if state.spaces[to_sid].support <= 0:
		return
	var cubes := module.count_in(state, to_sid, "mg_troop") \
		+ module.count_in(state, to_sid, "security") \
		+ module.count_in(state, to_sid, "eg_troop") \
		+ module.count_in(state, to_sid, "specops")
	if n + cubes > 3:
		act.activate(to_sid, rebel, n)


## §5.8: Travel sceglie le ORIGINI (la Wilderness è gratis) e ignora le tempeste.
## plan = {origins: [sid], moves: [{from,to,count,type}]}   type: cr_rebel | cr_base
func travel(plan: Dictionary) -> Dictionary:
	_current_op = "travel"
	var origins: Array = plan.get("origins", [])
	if origins.is_empty():
		return _fail("Travel: nessuna origine scelta.")
	var cost := 0
	for sid in origins:
		if String(sid) != "wilderness":
			cost += 1
	if not _can_pay("reclaimer", cost):
		return _fail("Travel: Risorse insufficienti (%d)." % cost)

	for m in plan.get("moves", []):
		var from_sid := String(m.get("from", ""))
		var to_sid := String(m.get("to", ""))
		var type_id := String(m.get("type", "cr_rebel"))
		if not origins.has(from_sid):
			return _fail("Travel: %s non è fra le origini scelte." % from_sid)
		if not state.game_def.space(from_sid).adjacent.has(to_sid):
			return _fail("Travel: %s non è adiacente a %s." % [to_sid, from_sid])
		if module.count_in(state, from_sid, type_id) < int(m.get("count", 0)):
			return _fail("Travel: pezzi insufficienti in %s." % from_sid)

	for m in plan.get("moves", []):
		var from_sid := String(m["from"])
		var to_sid := String(m["to"])
		var type_id := String(m.get("type", "cr_rebel"))
		var n := int(m["count"])
		module.move_pieces(state, from_sid, to_sid, type_id, n)
		if type_id == "cr_base":
			# Un Conversion Center che si sposta torna sul lato base.
			var up := module.count_in(state, to_sid, "cr_base", "conversion_center")
			if up > 0:
				state.spaces[to_sid].remove_piece("reclaimer", "cr_base", up, "conversion_center")
				state.spaces[to_sid].add_piece("reclaimer", "cr_base", up, "basic")
		else:
			_moving_rebels_reveal(to_sid, "cr_rebel", n)
			# Chi entra in uno spazio con tempesta (di qualsiasi tipo) si Nasconde.
			if module.storm(state, to_sid) > 0:
				act.hide(to_sid, "cr_rebel", 99)
	_pay("reclaimer", cost)
	return _done(cost)


# ===========================================================================
# §5.9 ATTACK — Red Dust e Reclaimer
# ===========================================================================

## plan = {faction, spaces: [sid], ambush: {sid: [d1, d2]}}
func attack(plan: Dictionary) -> Dictionary:
	_current_op = "attack"
	var faction := String(plan.get("faction", "red_dust"))
	var spaces: Array = plan.get("spaces", [])
	if spaces.is_empty():
		return _fail("Attack: nessuno spazio scelto.")
	var rebel := "rd_rebel" if faction == "red_dust" else "cr_rebel"
	var storm_free := act.storm_free(faction)
	for sid in spaces:
		var s := String(sid)
		if not act.selectable(s, storm_free):
			return _fail("Attack: %s è sotto Raging Storm." % s)
		if module.count_in(state, s, rebel) == 0:
			return _fail("Attack: nessun Ribelle in %s." % s)
		if _enemy_force_count(s, faction) == 0:
			return _fail("Attack: nessuna forza nemica in %s." % s)
	var cost := spaces.size()
	if not _can_pay(faction, cost):
		return _fail("Attack: Risorse insufficienti (%d)." % cost)

	var ambush: Dictionary = plan.get("ambush", {})
	for sid in spaces:
		_resolve_attack_space(String(sid), faction, ambush.get(String(sid), []))
	_pay(faction, cost)
	return _done(cost)


func _enemy_force_count(sid: String, faction: String) -> int:
	var n := 0
	for type_id in RDRModule.PIECE_OWNER.keys():
		var owner: String = RDRModule.PIECE_OWNER[type_id]
		if owner == faction:
			continue
		n += module.count_in(state, sid, String(type_id))
	return n


## §5.9: si Attivano tutti i propri Ribelli e si tirano 2 dadi. Se la somma è
## minore o uguale alle forze totali presenti si piazza un Danno; per ogni dado
## minore o uguale al numero dei propri Ribelli si rimuovono 2 forze nemiche
## (una Truppa EG ne vale 2). Con Ambush si sceglie il valore dei dadi e si
## Attiva un solo Ribelle Nascosto.
func _resolve_attack_space(sid: String, faction: String, ambush_dice: Array) -> void:
	var rebel := "rd_rebel" if faction == "red_dust" else "cr_rebel"
	if ambush_dice.size() == 2:
		act.activate(sid, rebel, 1)
	else:
		act.activate(sid, rebel, 99)
	var rebels := module.count_in(state, sid, rebel)
	var total_forces := 0
	for type_id in RDRModule.PIECE_OWNER.keys():
		total_forces += module.count_in(state, sid, String(type_id))

	var d1: int = int(ambush_dice[0]) if ambush_dice.size() == 2 else rng.randi_range(1, 6)
	var d2: int = int(ambush_dice[1]) if ambush_dice.size() == 2 else rng.randi_range(1, 6)
	if d1 + d2 <= total_forces:
		act.place_damage(sid)
	var budget := 0
	var hits := 0
	if d1 <= rebels:
		budget += 2
		hits += 1
	if d2 <= rebels:
		budget += 2
		hits += 1
	# Capability #1 "Subdermal Weaponry": ogni dado riuscito toglie una forza
	# nemica in più.
	if faction == "reclaimer" and module.capability_active(state, 1):
		budget += hits
	if budget <= 0:
		return

	# §5.9: gli SpecOps Nascosti non si possono colpire (e non proteggono le Basi);
	# i Ribelli Nascosti dell'altra Fazione sì. Le Basi per ultime.
	var priority: Array[String] = []
	for type_id in _attack_removal_order(sid, faction):
		if RDRModule.PIECE_OWNER[String(type_id)] == faction:
			continue
		priority.append(String(type_id))
	var spent := 0
	while spent < budget:
		var removed := _remove_one_for_attack(sid, priority)
		if removed == "":
			break
		# Ogni Truppa EG rimossa consuma due "forze".
		spent += 2 if removed == "eg_troop" else 1
	# Capability #26 "Ares Rockets": quel che avanza può colpire i Satelliti
	# ovunque su Mars, non solo nello spazio dell'Attack.
	if faction == "reclaimer" and module.capability_active(state, 26):
		while spent < budget:
			var o := _ares_target(sid, faction)
			if o == "":
				break
			if module.remove_pieces(state, o, "satellite", 1, "casualties") == 0:
				break
			log_lines.append("Ares Rockets: Satellite abbattuto in %s." %
				state.game_def.space(o).name)
			spent += 1
	log_lines.append("%s: Attack %s — dadi %d/%d su %d Ribelli e %d forze." % [
		state.game_def.space(sid).name, faction, d1, d2, rebels, total_forces])


## §5.9: gli SpecOps Nascosti non si possono colpire (e non proteggono le Basi);
## i Ribelli Nascosti dell'altra Fazione sì. Le Basi per ultime.
## Per una Fazione NP l'ordine lo detta la tabella Piece Priorities (§8.5.8), che
## fra l'altro decide se un Attack riuscito con "Ares Rockets" spende un colpo
## su un Satellite invece che sulle forze a terra.
func _attack_removal_order(sid: String, faction: String) -> Array:
	const DEFAULT_ORDER := ["mg_troop", "security", "eg_troop", "satellite",
		"rd_rebel", "cr_rebel", "specops", "mg_base", "corp_base", "rd_base", "cr_base"]
	if np_piece_order.is_null() or not module.is_np(state, faction):
		return DEFAULT_ORDER
	var order: Array = np_piece_order.call(faction, sid, "enemy")
	if order.is_empty():
		return DEFAULT_ORDER
	# La tabella non nomina per forza tutti i tipi: quel che manca resta in coda
	# nell'ordine di default, così non si smette mai di poter colpire.
	var out: Array = []
	for t in order:
		if RDRModule.PIECE_OWNER.has(String(t)) and not out.has(String(t)):
			out.append(String(t))
	for t in DEFAULT_ORDER:
		if not out.has(t):
			out.append(t)
	return out


## Dove "Ares Rockets" abbatte il prossimo Satellite. Per una Fazione NP la
## scheda manda alla colonna Remove or Replace delle Space Selection Priorities.
func _ares_target(sid: String, faction: String) -> String:
	var pool: Array = []
	for other in module.mars_spaces(state):
		var o := String(other)
		if o != sid and module.count_in(state, o, "satellite") > 0:
			pool.append(o)
	if pool.is_empty():
		return ""
	if np_space_order.is_null() or not module.is_np(state, faction):
		return String(pool[0])
	var pick := String(np_space_order.call(faction, "remove_or_replace", pool))
	return pick if pick != "" else String(pool[0])


func _remove_one_for_attack(sid: String, priority: Array[String]) -> String:
	for type_id in priority:
		var t := String(type_id)
		if module.count_in(state, sid, t) == 0:
			continue
		# Gli SpecOps sono colpibili solo se Attivi.
		if t == "specops":
			if module.count_in(state, sid, t, "active") == 0:
				continue
			module.remove_pieces(state, sid, t, 1, act.removal_dest(t), "active")
			return t
		var pt: PieceTypeDef = state.game_def.piece_type(t)
		if pt != null and pt.is_base and not act.base_removable(sid, t):
			continue
		if module.remove_pieces(state, sid, t, 1, act.removal_dest(t)) > 0:
			return t
	return ""


# ===========================================================================
# §5.10 CAMPAIGN (Red Dust) / §5.11 PREACH (Reclaimer)
# ===========================================================================

## plan = {spaces: [sid]}
func campaign(plan: Dictionary) -> Dictionary:
	_current_op = "campaign"
	var spaces: Array = plan.get("spaces", [])
	if spaces.is_empty():
		return _fail("Campaign: nessuno spazio scelto.")
	for sid in spaces:
		var s := String(sid)
		if not act.selectable(s):
			return _fail("Campaign: %s è sotto Raging Storm." % s)
		if module.population(state, s) <= 0 or module.count_in(state, s, "rd_rebel") == 0:
			return _fail("Campaign: %s non è Popolato o non ha Ribelli RD." % s)
	var cost := spaces.size()
	if not _can_pay("red_dust", cost):
		return _fail("Campaign: Risorse insufficienti (%d)." % cost)

	var draws := 0
	for sid in spaces:
		var s := String(sid)
		var was_active_opp: bool = state.spaces[s].support == CoinEnums.Support.ACTIVE_OPPOSITION
		if module.count_in(state, s, "rd_rebel", "active") == 0:
			act.activate(s, "rd_rebel", 1)
		act.shift(s, -1)
		var now: int = state.spaces[s].support
		if now == CoinEnums.Support.ACTIVE_OPPOSITION or was_active_opp:
			draws += 1
		if now == CoinEnums.Support.PASSIVE_SUPPORT:
			act.place_damage(s)
			act.set_eg("EG-")
			if module.count_in(state, s, "corp_base") > 0:
				state.tracks["profits"] = clampi(int(state.tracks.get("profits", 0)) - 2, 0, 50)
	if draws > 0:
		if cards != null:
			cards.draw_campaign_into_play(draws)
			log_lines.append_array(cards.log_lines)
			cards.log_lines.clear()
		else:
			log_lines.append("Campaign: %d carte pescate, 1 in gioco (mazzi non collegati)." % draws)
	_pay("red_dust", cost)
	return _done(cost)


## plan = {spaces: [sid]}
func preach(plan: Dictionary) -> Dictionary:
	_current_op = "preach"
	var spaces: Array = plan.get("spaces", [])
	if spaces.is_empty():
		return _fail("Preach: nessuno spazio scelto.")
	var storm_free := act.storm_free("reclaimer")
	for sid in spaces:
		var s := String(sid)
		if not act.selectable(s, storm_free):
			return _fail("Preach: %s è sotto Raging Storm." % s)
		if module.population(state, s) <= 0 or module.count_in(state, s, "cr_rebel") == 0:
			return _fail("Preach: %s non è Popolato o non ha Ribelli CR." % s)
	var cost := spaces.size()
	if not _can_pay("reclaimer", cost):
		return _fail("Preach: Risorse insufficienti (%d)." % cost)

	for sid in spaces:
		var s := String(sid)
		if module.count_in(state, s, "cr_rebel", "active") == 0:
			act.activate(s, "cr_rebel", 1)
		var st: SpaceState = state.spaces[s]
		if st.support != CoinEnums.Support.NEUTRAL:
			act.shift(s, -1 if st.support > 0 else 1)
		else:
			# §5.11: già Neutrale — arrivano Ribelli pari alla Popolazione e si
			# toglie un marker Popolazione; se non ce ne sono, Danno ed EG−.
			module.place_from_available(state, s, "cr_rebel", module.population(state, s), "hidden")
			if module.marker(state, s, "pop_markers") > 0:
				module.add_marker(state, s, "pop_markers", -1)
				act.normalize_support(s)
			else:
				act.place_damage(s)
				act.set_eg("EG-")
	_pay("reclaimer", cost)
	return _done(cost)

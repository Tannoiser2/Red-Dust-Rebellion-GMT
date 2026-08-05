class_name CardDef
extends RefCounted

## Definizione (immutabile) di una carta del mazzo COIN.

var number: int = 0
var title: String = ""

## Ordine delle Fazioni stampato in cima alla carta (id, da sinistra a destra).
## Determina chi è 1ª / 2ª Disponibile.
var faction_order: PackedStringArray = PackedStringArray()

var is_propaganda: bool = false     ## carta Propaganda / Coup (round periodico)
var is_capability: bool = false     ## Evento con Capacità Insorgenti (effetto duraturo)
var is_momentum: bool = false       ## Evento Momentum (effetto fino al round successivo)
var is_pivotal: bool = false        ## Carta Pivotal (in ABB: Red Revolt! trigger Phase II)

var unshaded: String = ""           ## testo non-ombreggiato dell'Evento
var shaded: String = ""             ## testo ombreggiato dell'Evento
var translation: String = ""        ## traduzione italiana sintetica (Chiaro:/Ombr.:)
var history: String = ""            ## descrizione storica dal Playbook

## Simboli Non-player stampati sulla carta (ABB §8.1.4): faction_id → stringa
## con "P" (Pass per giocare il prossimo Evento), "i" (gioca con istruzioni),
## "e" (simbolo pieno: gioca senza istruzioni, priorità generali §8.1.7).
var np: Dictionary = {}


## La carta ha il simbolo `sym` ("P"/"i"/"e") per la fazione?
func np_has(faction_id: String, sym: String) -> bool:
	return String(np.get(faction_id, "")).contains(sym)


func _init(p_number: int = 0, p_title: String = "") -> void:
	number = p_number
	title = p_title


static func from_dict(d: Dictionary) -> CardDef:
	var c := CardDef.new(int(d.get("number", 0)), String(d.get("title", "")))
	for f in d.get("factionOrder", d.get("faction_order", [])):
		c.faction_order.append(String(f))
	c.is_propaganda = bool(d.get("propaganda", d.get("is_propaganda", false)))
	c.is_capability = bool(d.get("capability", d.get("is_capability", false)))
	c.is_momentum = bool(d.get("momentum", d.get("is_momentum", false)))
	c.is_pivotal = bool(d.get("pivotal", d.get("is_pivotal", false)))
	c.unshaded = String(d.get("unshaded", ""))
	c.shaded = String(d.get("shaded", ""))
	c.translation = String(d.get("it", d.get("translation", "")))
	c.history = String(d.get("history", ""))
	var np_d: Dictionary = d.get("np", {})
	for k in np_d.keys():
		c.np[String(k)] = String(np_d[k])
	return c

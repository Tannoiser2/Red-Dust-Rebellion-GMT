class_name RDRAssets
extends RefCounted

## Caricamento (con cache) delle texture del modulo Red Dust Rebellion.
## I nomi dei file sono quelli normalizzati in `assets/`, rinominati dal modulo
## Vassal: il suffisso "-a" dell'originale significa "lato simbolo scoperto",
## cioè Attivo per Ribelli/SpecOps e lato potenziato per le Basi.

## NB: le funzioni sono statiche, e in GDScript una `static func` non può accedere
## ai singleton di autoload (GameRegistry): la cartella asset è quindi una costante.
const ASSETS_DIR := "res://games/red_dust_rebellion/assets/"

static var _cache: Dictionary = {}

## piece_type_id + stato -> nome file.
const PIECE_FILES := {
	"mg_troop": "mg_troop.png",
	"mg_base": "mg_base.png",
	"security": "security.png",
	"corp_base:basic": "corp_base.png",
	"corp_base:terraforming": "corp_base_terraforming.png",
	"specops:hidden": "specops_hidden.png",
	"specops:active": "specops_active.png",
	"eg_troop": "eg_troop.png",
	"satellite": "satellite.png",
	"rd_rebel:hidden": "rd_rebel_hidden.png",
	"rd_rebel:active": "rd_rebel_active.png",
	"rd_base:basic": "rd_base.png",
	"rd_base:dug_in": "rd_base_dug_in.png",
	"cr_rebel:hidden": "cr_rebel_hidden.png",
	"cr_rebel:active": "cr_rebel_active.png",
	"cr_base:basic": "cr_base.png",
	"cr_base:conversion_center": "cr_base_conversion.png",
}

const SUPPORT_FILES := {
	CoinEnums.Support.ACTIVE_SUPPORT: "support_active.png",
	CoinEnums.Support.PASSIVE_SUPPORT: "support_passive.png",
	CoinEnums.Support.PASSIVE_OPPOSITION: "opposition_passive.png",
	CoinEnums.Support.ACTIVE_OPPOSITION: "opposition_active.png",
}

const CONTROL_FILES := {
	"coin": "control_coin.png",
	"red_dust": "control_red_dust.png",
	"reclaimer": "control_reclaimer.png",
}

## Colori per il testo su fondo scuro: il nero delle Corporations sarebbe illeggibile.
const TEXT_COLORS := {
	"marsgov": Color("6aa8e8"),
	"corporations": Color("b8b8b8"),
	"red_dust": Color("e8695a"),
	"reclaimer": Color("f0a05a"),
	"earthgov": Color("ecf0f1"),
}

## Colori delle Fazioni (tinta del Controllo sulla mappa e UI).
const FACTION_COLORS := {
	"marsgov": Color("2f6fb5"),
	"corporations": Color("1c1c1c"),
	"red_dust": Color("c0392b"),
	"reclaimer": Color("e67e22"),
	"earthgov": Color("ecf0f1"),
	"coin": Color("2f6fb5"),
}


static func tex(file_name: String) -> Texture2D:
	if file_name == "":
		return null
	if _cache.has(file_name):
		return _cache[file_name]
	var path := ASSETS_DIR + file_name
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if t == null:
		push_warning("RDRAssets: texture mancante %s" % path)
	_cache[file_name] = t
	return t


## Immagine della carta Evento numero `n` (assets/cards/01.jpg … 51.jpg).
static func card_tex(number: int) -> Texture2D:
	if number < 1 or number > 51:
		return null
	return tex("cards/%02d.jpg" % number)


static func piece_tex(type_id: String, state: String = "") -> Texture2D:
	var key := "%s:%s" % [type_id, state] if state != "" else type_id
	if not PIECE_FILES.has(key):
		key = type_id
	return tex(String(PIECE_FILES.get(key, "")))


static func support_tex(level: int) -> Texture2D:
	return tex(String(SUPPORT_FILES.get(level, "")))


static func control_tex(control: String) -> Texture2D:
	return tex(String(CONTROL_FILES.get(control, "")))


static func control_color(control: String) -> Color:
	return FACTION_COLORS.get(control, Color(1, 1, 1, 0)) as Color


## Colore leggibile su fondo scuro (pannello laterale, log).
static func text_color(faction: String) -> Color:
	return TEXT_COLORS.get(faction, Color.WHITE) as Color

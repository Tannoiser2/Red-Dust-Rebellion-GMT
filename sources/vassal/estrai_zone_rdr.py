"""Estrae poligoni e geometrie dal modulo Vassal di Red Dust Rebellion.

Uso (dalla root del repo):
    python3 sources/vassal/estrai_zone_rdr.py

Legge `sources/vassal/buildFile.xml` e scrive:
  * godot/games/red_dust_rebellion/data/regions.json    poligoni normalizzati [0..1]
  * godot/games/red_dust_rebellion/data/board_layout.json  tracciati/box/SoP

La tavola Vassal "RDR Game Board" (RDR_Game Board.jpg) è 5175x3775 px e le zone
usano direttamente quelle coordinate: nessun crop, la normalizzazione è diretta.
"""

import json
import os
import xml.etree.ElementTree as ET

BOARD_W, BOARD_H = 5175.0, 3775.0

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILD_FILE = os.path.join(REPO, "sources", "vassal", "buildFile.xml")
DATA_DIR = os.path.join(REPO, "godot", "games", "red_dust_rebellion", "data")

ZONE_TAG = "VASSAL.build.module.map.boardPicker.board.mapgrid.Zone"

# Nome zona Vassal -> id snake_case del modulo Godot.
# NB: il Vassal scrive "New Cordoba" e "Gandhi" senza accenti.
SPACES = {
    # Tharsis Montes — anello esterno (Deserti)
    "Ascraeus Mons": "ascraeus_mons",
    "Tharsis Tholus": "tharsis_tholus",
    "Arsia Mons": "arsia_mons",
    "Noctis Labyrinthus": "noctis_labyrinthus",
    "Sinai Planum": "sinai_planum",
    "Daedalia Planum": "daedalia_planum",
    # Tharsis Montes — anello interno
    "Pavonis Mons": "pavonis_mons",
    "Syria Planum": "syria_planum",
    "Europa": "europa",
    "Tenzing": "tenzing",
    "Tereshkova": "tereshkova",
    "Shepard": "shepard",
    # Arabia Terra
    "Rutherford": "rutherford",
    "Radau": "radau",
    "Marth": "marth",
    "Trouvelot": "trouvelot",
    "New Cordoba": "new_cordoba",
    "Shenzhou": "shenzhou",
    # Hellas Planitia
    "Alpheus Colles": "alpheus_colles",
    "Coronae Montes": "coronae_montes",
    "Hellas Chaos": "hellas_chaos",
    "Gandhi": "gandhi",
    "Sharma": "sharma",
    # Deserto non settoriale
    "The Wilderness": "wilderness",
}

# Spazi "fuori Mars" dell'Aldrin Cycler + box di servizio.
OFF_MAP = {
    "Earth": "earth",
    "Transit": "transit",
    "Phobos": "phobos",
    "Orbit": "orbit",
    "Casualties": "casualties",
    "Displaced Population": "displaced_population",
}

# Zone della Sequence of Play (posizione dei cilindri Eligibility).
SOP = {
    "Eligible Factions": "eligible",
    "Pass": "pass",
    "1st Faction Op Only": "op1_op",
    "1st Faction Op + SA": "op1_op_sa",
    "1st Faction Event": "op1_event",
    "2nd Faction Lim OP": "op2_limop",
    "2nd Faction Lim OP or Event": "op2_limop_or_event",
    "2nd Faction Event": "op2_event",
    "Ineligible Factions": "ineligible",
}

CARD_SLOTS = {
    "Current Event": "current_event",
    "Asset Card(s) in Play": "assets_in_play",
    "Campaign 1": "campaign_1",
    "Campaign 2": "campaign_2",
    "Campaign 3": "campaign_3",
}


def parse_path(path):
    return [tuple(int(v) for v in p.split(",")) for p in path.split(";")]


def norm_poly(pts):
    return [[round(x / BOARD_W, 5), round(y / BOARD_H, 5)] for x, y in pts]


def centroid(pts):
    return [
        round(sum(p[0] for p in pts) / len(pts) / BOARD_W, 5),
        round(sum(p[1] for p in pts) / len(pts) / BOARD_H, 5),
    ]


def bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return [
        round(min(xs) / BOARD_W, 5),
        round(min(ys) / BOARD_H, 5),
        round(max(xs) / BOARD_W, 5),
        round(max(ys) / BOARD_H, 5),
    ]


def main():
    root = ET.parse(BUILD_FILE).getroot()
    zones = {}
    order = []
    for z in root.iter(ZONE_TAG):
        name = z.attrib.get("name") or ""
        path = z.attrib.get("path") or ""
        if not path or name in zones:
            continue
        zones[name] = parse_path(path)
        order.append(name)

    regions = {}
    for vassal_name, sid in SPACES.items():
        pts = zones[vassal_name]
        regions[sid] = {
            "polygon": norm_poly(pts),
            "anchor": centroid(pts),
            "bbox": bbox(pts),
            # ordine di disegno: i Deserti stanno sotto, i Labirinti (cerchi) sopra
            "z": order.index(vassal_name),
        }

    off = {}
    for vassal_name, sid in OFF_MAP.items():
        pts = zones[vassal_name]
        off[sid] = {"polygon": norm_poly(pts), "anchor": centroid(pts), "bbox": bbox(pts)}

    # Edge Track: le zone "0".."50" lungo il bordo superiore della tavola.
    track = {}
    for i in range(51):
        if str(i) in zones:
            track[str(i)] = centroid(zones[str(i)])

    sop = {k2: centroid(zones[k1]) for k1, k2 in SOP.items() if k1 in zones}
    flashpoint = {}
    for label, key in [
        ("Flashpoint 0", "0"),
        ("Flashpoint 1", "1"),
        ("Flashpoint 2", "2"),
        ("Flashpoint 3", "3"),
        ("Flashpoint 4", "4"),
        ("Flashpoint Trigger", "trigger"),
    ]:
        if label in zones:
            flashpoint[key] = centroid(zones[label])
    eg = {}
    for label in zones:
        if label.startswith("EG Confidence "):
            eg[label.rsplit(" ", 1)[1]] = centroid(zones[label])
    cards = {k2: centroid(zones[k1]) for k1, k2 in CARD_SLOTS.items() if k1 in zones}

    os.makedirs(DATA_DIR, exist_ok=True)
    with open(os.path.join(DATA_DIR, "regions.json"), "w", encoding="utf-8") as fh:
        json.dump(
            {
                "_note": (
                    "Estratto da sources/vassal/buildFile.xml (Red Dust Rebellion 1.0, "
                    "tavola 'RDR Game Board' 5175x3775). polygon/anchor/bbox normalizzati "
                    "[0..1]; z = ordine di disegno Vassal (i Labirinti circolari stanno "
                    "sopra i Deserti che li circondano)."
                ),
                "board": {"width": int(BOARD_W), "height": int(BOARD_H)},
                "regions": regions,
                "off_map": off,
            },
            fh,
            ensure_ascii=False,
            indent=1,
        )

    with open(os.path.join(DATA_DIR, "board_layout.json"), "w", encoding="utf-8") as fh:
        json.dump(
            {
                "_note": "Geometrie dei tracciati della tavola, normalizzate [0..1].",
                "edge_track": track,
                "flashpoint_track": flashpoint,
                "eg_confidence_track": eg,
                "sop": sop,
                "card_slots": cards,
            },
            fh,
            ensure_ascii=False,
            indent=1,
        )

    print("regions:", len(regions), "off_map:", len(off), "edge_track:", len(track))
    print("sop:", len(sop), "flashpoint:", len(flashpoint), "eg:", len(eg))


if __name__ == "__main__":
    main()

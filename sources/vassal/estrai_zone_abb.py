"""Estrae i poligoni delle zone (spazi mappa) dal modulo Vassal di All Bridges Burning.

Uso:
    cd <repo>/tmp_vmod
    unzip ../"Materiale ABB"/All_Bridges_Burning_1.2.vmod.zip
    python3 ../sources/vassal/estrai_zone_abb.py

Scrive `godot/games/all_bridges_burning/data/regions.json` con i poligoni
normalizzati nello spazio [0..1]x[0..1] rispetto alla mappa ABB croppata a 3829x3000 (zona Map Vassal).
"""

import re
import json
import os
import sys

# Coordinata di riferimento della mappa Vassal (ABB Map-FINAL-150-BRcut-Canvas-4.png).
# La PNG sorgente è 6000x3000, ma la zona "Map" del Vassal (area utile) finisce
# a x=3829; il resto è "Card Decks Area" + "Play Area" decorativi. Normalizziamo
# usando questo bordo destro, così le coordinate corrispondono alla map.jpg
# generata croppando il sorgente a [0..3829].
MAP_W, MAP_H = 3829.0, 3000.0

# Mappatura nome Vassal -> id snake_case del modulo Godot.
PROVINCES = {
    "Häme": "hame",
    "Karelia": "karelia",
    "Kuopion lääni": "kuopion_laani",
    "Mikkelin lääni": "mikkelin_laani",
    "Oulun lääni": "oulun_laani",
    "Pohjanmaa": "pohjanmaa",
    "Uusimaa": "uusimaa",
    "Varsinais-Suomi": "varsinais_suomi",
}

CITIES = {
    "Helsinki": "helsinki",
    "Tampere": "tampere",
    "Turku": "turku",
    "Vaasa": "vaasa",
    "Viipuri": "viipuri",
}


def fix_latin(s: str) -> str:
    """Vassal scrive UTF-8 dentro file letti come latin-1; sistema le accentate."""
    try:
        return s.encode("latin-1").decode("utf-8")
    except Exception:
        return s


def parse_zones(build_file: str) -> dict:
    raw = open(build_file, encoding="latin-1").read()
    zones = {}
    for n, p in re.findall(r'Zone[^>]*name="([^"]*)"[^>]*path="([^"]*)"', raw):
        zones[fix_latin(n)] = p
    return zones


def parse_setup_stacks(build_file: str) -> dict:
    raw = open(build_file, encoding="latin-1").read()
    stacks = {}
    for m in re.finditer(
        r'SetupStack[^>]*name="([^"]*)"[^>]*?x="(-?\d+)"[^>]*?y="(-?\d+)"', raw
    ):
        stacks[fix_latin(m.group(1))] = (int(m.group(2)), int(m.group(3)))
    return stacks


def poly(zones: dict, name: str) -> list:
    pts = []
    for pair in zones[name].split(";"):
        x, y = pair.split(",")
        pts.append([round(int(x) / MAP_W, 4), round(int(y) / MAP_H, 4)])
    # Rimuovi duplicati consecutivi
    out = []
    for pt in pts:
        if not out or out[-1] != pt:
            out.append(pt)
    return out


def centroid(pts: list) -> list:
    return [
        round(sum(p[0] for p in pts) / len(pts), 4),
        round(sum(p[1] for p in pts) / len(pts), 4),
    ]


def circle_from_pts(pts: list) -> list:
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    r = min(max(xs) - min(xs), max(ys) - min(ys)) / 2
    return [round(cx, 4), round(cy, 4), round(r, 4)]


def marker(stacks: dict, name: str) -> list | None:
    if name in stacks:
        x, y = stacks[name]
        return [round(x / MAP_W, 4), round(y / MAP_H, 4)]
    return None


def zone_center(zones: dict, name: str) -> list | None:
    """Centro normalizzato della Zone Vassal `name` (es. 'Häme Control')."""
    if name not in zones:
        return None
    pts = []
    for pair in zones[name].split(";"):
        try:
            x, y = pair.split(",")
            pts.append((int(x), int(y)))
        except Exception:
            pass
    if not pts:
        return None
    xs = [pt[0] for pt in pts]
    ys = [pt[1] for pt in pts]
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    return [round(cx / MAP_W, 4), round(cy / MAP_H, 4)]


# Mappa nome Zone Vassal -> chiave board_layout "available_<fid>" per i pool
# delle Available Forces.
AVAIL_ZONES = {
    "Available Forces Senate":    "senate",
    "Available Forces Reds":      "reds",
    "Available Forces Moderates": "moderates",
    "Russian Forces":             "russians",
    "German Forces":              "germans",
}

# Altre Zone Vassal mappate a box ad uso UI (Capabilities panel, ecc.).
EXTRA_BOX_ZONES = {
    "Capabilities": "capabilities",
    "Political Display": "political_display",
    "Prisoners of War": "prisoners_of_war",
}


def avail_box(zones: dict, vname: str) -> list | None:
    """Bounding box normalizzato della Zone delle Available Forces."""
    if vname not in zones:
        return None
    pts = []
    for pair in zones[vname].split(";"):
        try:
            x, y = pair.split(",")
            pts.append((int(x), int(y)))
        except Exception:
            pass
    if not pts:
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return [
        round(min(xs) / MAP_W, 4), round(min(ys) / MAP_H, 4),
        round(max(xs) / MAP_W, 4), round(max(ys) / MAP_H, 4),
    ]


def cell_slots(build_file: str) -> dict:
    """Posizioni normalizzate degli slot 'Senate/Moderates/Reds Cell N'."""
    raw = open(build_file, encoding="latin-1").read()
    pat = re.compile(
        r'SetupStack[^>]*name="((?:Senate|Moderates|Reds) Cell) ([0-9]+)"'
        r'[^>]*x="(-?\d+)"[^>]*y="(-?\d+)"'
    )
    out: dict = {}
    for m in pat.finditer(raw):
        fid = m.group(1).split()[0].lower()
        n = int(m.group(2))
        x, y = int(m.group(3)), int(m.group(4))
        out.setdefault(fid + "_cell", {})[n] = [
            round(x / MAP_W, 4), round(y / MAP_H, 4)
        ]
    return {k: [d[i] for i in sorted(d.keys())] for k, d in out.items()}


# Mappa province -> file mask PNG nel modulo Vassal (cartella images/).
PROVINCE_MASKS = {
    "Häme":            "Hame_Mask.png",
    "Karelia":         "Karelia_Mask.png",
    "Kuopion lääni":   "Kuopion_Mask.png",
    "Mikkelin lääni":  "Mikkelin_Mask.png",
    "Oulun lääni":     "Oulun-Mask.png",
    "Pohjanmaa":       "Pohjanmaa_Mask.png",
    "Uusimaa":         "Uusimaa-Mask.png",
    "Varsinais-Suomi": "Varsinais-Suomi_Mask.png",
}


def mask_rect(zones: dict, vname: str, mask_path: str) -> dict | None:
    """Calcola ancora + rect normalizzato della mask: allinea il bbox dei pixel
    opachi al bbox del poligono Vassal della Zone."""
    try:
        from PIL import Image
    except ImportError:
        print("ATTENZIONE: Pillow non installato, salto le mask. (pip install Pillow)", file=sys.stderr)
        return None
    if vname not in zones:
        return None
    pts = [tuple(map(int, p.split(","))) for p in zones[vname].split(";")]
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    px0, py0 = min(xs), min(ys)
    img = Image.open(mask_path)
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    mw, mh = img.size
    bbox = img.split()[3].getbbox()
    if bbox is None:
        return None
    mbx0, mby0, _, _ = bbox
    ax = px0 - mbx0
    ay = py0 - mby0
    return [
        round(ax / MAP_W, 4),
        round(ay / MAP_H, 4),
        round((ax + mw) / MAP_W, 4),
        round((ay + mh) / MAP_H, 4),
    ]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(here, "..", ".."))
    tmp_vmod = os.path.join(repo_root, "tmp_vmod")
    build_file = os.path.join(tmp_vmod, "buildFile")
    if not os.path.exists(build_file):
        print(
            f"ERRORE: {build_file} non trovato. Scompatta il .vmod in {tmp_vmod}/.",
            file=sys.stderr,
        )
        sys.exit(1)

    zones = parse_zones(build_file)
    stacks = parse_setup_stacks(build_file)

    regions: dict = {}
    spaces_list: list = []
    missing: list = []

    masks_dir = os.path.join(tmp_vmod, "images")
    assets_regions_dir = os.path.join(
        repo_root, "godot", "games", "all_bridges_burning", "assets", "regions"
    )
    for vname, sid in PROVINCES.items():
        if vname not in zones:
            missing.append(vname)
            continue
        pts = poly(zones, vname)
        entry: dict = {"polygon": pts, "anchor": centroid(pts)}
        # Mask Vassal (pixel-perfect): copia in assets/regions/ + calcola rect.
        mask_file = PROVINCE_MASKS.get(vname)
        if mask_file:
            src_mask = os.path.join(masks_dir, mask_file)
            if os.path.exists(src_mask):
                dst_name = "%s_mask.png" % sid
                dst_path = os.path.join(assets_regions_dir, dst_name)
                os.makedirs(assets_regions_dir, exist_ok=True)
                try:
                    with open(src_mask, "rb") as srcf, open(dst_path, "wb") as dstf:
                        dstf.write(srcf.read())
                except Exception as exc:
                    print(f"ATTENZIONE: mask copia fallita per {sid}: {exc}", file=sys.stderr)
                rect = mask_rect(zones, vname, src_mask)
                if rect is not None:
                    entry["mask"] = "regions/" + dst_name
                    entry["mask_rect"] = rect
        cbox = marker(stacks, vname + " Control") or zone_center(zones, vname + " Control")
        if cbox:
            entry["cbox"] = cbox
            # sbox: posizione marker Sup/Opp — affiancato orizzontalmente al cbox
            # (Control box e Sup/Opp box sono adiacenti sulla mappa stampata).
            entry["cbox"] = [round(cbox[0] - 0.0163, 4), cbox[1]]
            entry["sbox"] = [round(cbox[0] + 0.0168, 4), cbox[1]]
        regions[sid] = entry
        spaces_list.append(
            {
                "id": sid,
                "name": vname,
                "type": "province",
                "pop": 0,  # TODO: leggere dalla mappa
                "adjacent": [],  # TODO: PR adiacenze
            }
        )

    for vname, sid in CITIES.items():
        if vname not in zones:
            missing.append(vname)
            continue
        pts = poly(zones, vname)
        c = circle_from_pts(pts)
        entry = {"circle": c, "anchor": [c[0], c[1]], "polygon": pts}
        cbox = marker(stacks, vname + " Control") or zone_center(zones, vname + " Control")
        if cbox:
            entry["cbox"] = cbox
            # sbox: posizione marker Sup/Opp — offset 4% sotto cbox (non c'è una
            # Zone Vassal dedicata, ma è una distanza visivamente coerente sul
            # board).
            entry["cbox"] = [round(cbox[0] - 0.0163, 4), cbox[1]]
            entry["sbox"] = [round(cbox[0] + 0.0168, 4), cbox[1]]
        regions[sid] = entry
        spaces_list.append(
            {
                "id": sid,
                "name": vname,
                "type": "city",
                "pop": 0,  # TODO: leggere dalla mappa (es. Tampere=1)
                "adjacent": [],
            }
        )

    if missing:
        print("ATTENZIONE: zone Vassal non trovate:", missing, file=sys.stderr)

    out_regions = {
        "_note": (
            "Estratto da All_Bridges_Burning_1.2.vmod (zona Map 3829x3000). "
            "polygon=poligono normalizzato [0..1]; "
            "circle=[cx,cy,r] per le città; "
            "cbox=posizione marcatore Controllo; "
            "anchor=centro per ancorare pezzi."
        ),
        "regions": regions,
    }
    out_spaces = {
        "_note": (
            "8 province + 5 città estratte dal Vassal. "
            "Popolazione e adiacenze sono da popolare dal regolamento "
            "(ABBLivingRules.pdf)."
        ),
        "spaces": spaces_list,
    }

    data_dir = os.path.join(
        repo_root, "godot", "games", "all_bridges_burning", "data"
    )
    os.makedirs(data_dir, exist_ok=True)
    # Preserva pop e adjacent esistenti in spaces.json (popolati a mano dal
    # regolamento / calcolati da calcola_adiacenze_abb.py). Se mancano,
    # restano 0 / [] come default dei nuovi spazi.
    existing_path = os.path.join(data_dir, "spaces.json")
    if os.path.exists(existing_path):
        try:
            existing = json.load(open(existing_path, encoding="utf-8"))
            by_id = {s["id"]: s for s in existing.get("spaces", [])}
            for s in spaces_list:
                old = by_id.get(s["id"])
                if old:
                    s["pop"] = old.get("pop", s["pop"])
                    s["adjacent"] = old.get("adjacent", s["adjacent"])
            # Preserva _note esistente: a mano si è aggiunto un commento più ricco
            # (riferimento al regolamento, calcolo adiacenze) che non vogliamo
            # sovrascrivere ad ogni rilancio dell'extractor.
            if "_note" in existing:
                out_spaces["_note"] = existing["_note"]
        except Exception as exc:
            print(f"ATTENZIONE: impossibile fondere spaces.json esistente: {exc}", file=sys.stderr)
    with open(os.path.join(data_dir, "regions.json"), "w", encoding="utf-8") as f:
        json.dump(out_regions, f, ensure_ascii=False, indent=2)
    with open(existing_path, "w", encoding="utf-8") as f:
        json.dump(out_spaces, f, ensure_ascii=False, indent=2)

    # Merge boxes Available Forces + slot Cell dentro board_layout.json (preserva
    # gli altri campi: track, polarization_track, sop, ecc.).
    bl_path = os.path.join(data_dir, "board_layout.json")
    if os.path.exists(bl_path):
        bl: dict = json.load(open(bl_path, encoding="utf-8"))
        bl.setdefault("box", {})
        for vname, fid in AVAIL_ZONES.items():
            box = avail_box(zones, vname)
            if box is not None:
                bl["box"]["available_" + fid] = box
        for vname, key in EXTRA_BOX_ZONES.items():
            box = avail_box(zones, vname)
            if box is not None:
                bl["box"][key] = box
        slots = cell_slots(build_file)
        if slots:
            bl["cell_slots"] = slots
        with open(bl_path, "w", encoding="utf-8") as f:
            json.dump(bl, f, ensure_ascii=False, indent=2)
        print(
            f"  board_layout: boxes={list(AVAIL_ZONES.values())} "
            f"cell_slots={ {k: len(v) for k,v in slots.items()} }"
        )

    print(f"Scritte {len(regions)} regioni e {len(spaces_list)} spazi.")
    for sid in regions:
        e = regions[sid]
        tag = "poly%d" % len(e["polygon"]) if "polygon" in e else "circle"
        has_cbox = "cbox" in e
        print(f"  {sid:20s} {tag:10s} cbox={has_cbox}")


if __name__ == "__main__":
    main()

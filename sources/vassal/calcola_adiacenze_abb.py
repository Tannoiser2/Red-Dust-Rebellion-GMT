"""Calcola le adiacenze fra spazi ABB a partire dai poligoni normalizzati.

Due spazi sono adiacenti se i loro poligoni si toccano (regola §1.2.3 del
regolamento ABB: "Any two spaces that border on (touch) one another are
adjacent"). Le città in ABB sono contenute dentro la loro provincia di
appartenenza: aggiungiamo sempre l'adiacenza città↔provincia di contenimento.

Uso:
    python3 sources/vassal/calcola_adiacenze_abb.py [--apply]

Senza `--apply` stampa solo le adiacenze trovate (per ispezione).
Con `--apply` aggiorna in-place godot/games/all_bridges_burning/data/spaces.json
con i campi `adjacent`.
"""

import json
import os
import sys
from math import hypot

# Soglia di tolleranza: due bordi sono "in contatto" se la distanza minima fra
# i loro punti è ≤ EPS (in unità normalizzate [0..1] sulla mappa 6000x3000).
# 0.005 ≈ 30 px — robusto contro imprecisioni del tracciato Vassal.
EPS = 0.006

# Contenimento città → provincia (geografia Finlandia 1917).
CITY_IN_PROVINCE = {
    "helsinki": "uusimaa",
    "tampere": "hame",
    "turku": "varsinais_suomi",
    "vaasa": "pohjanmaa",
    "viipuri": "karelia",
}


def point_segment_dist(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    """Distanza punto P da segmento AB."""
    abx, aby = bx - ax, by - ay
    apx, apy = px - ax, py - ay
    denom = abx * abx + aby * aby
    if denom == 0:
        return hypot(apx, apy)
    t = max(0.0, min(1.0, (apx * abx + apy * aby) / denom))
    cx, cy = ax + t * abx, ay + t * aby
    return hypot(px - cx, py - cy)


def polygons_touch(p1: list, p2: list, eps: float) -> bool:
    """Vero se almeno un vertice di p1 dista ≤ eps da un segmento di p2 o viceversa."""
    n2 = len(p2)
    for vx, vy in p1:
        for i in range(n2):
            ax, ay = p2[i]
            bx, by = p2[(i + 1) % n2]
            if point_segment_dist(vx, vy, ax, ay, bx, by) <= eps:
                return True
    n1 = len(p1)
    for vx, vy in p2:
        for i in range(n1):
            ax, ay = p1[i]
            bx, by = p1[(i + 1) % n1]
            if point_segment_dist(vx, vy, ax, ay, bx, by) <= eps:
                return True
    return False


def bbox(pts: list) -> tuple:
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def bbox_overlap(a: tuple, b: tuple, pad: float = 0.0) -> bool:
    return not (
        a[2] + pad < b[0] or b[2] + pad < a[0] or a[3] + pad < b[1] or b[3] + pad < a[1]
    )


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(here, "..", ".."))
    data_dir = os.path.join(repo_root, "godot", "games", "all_bridges_burning", "data")
    regions = json.load(open(os.path.join(data_dir, "regions.json"), encoding="utf-8"))["regions"]
    spaces_doc = json.load(open(os.path.join(data_dir, "spaces.json"), encoding="utf-8"))
    spaces = spaces_doc["spaces"]

    # Poligoni di tutti gli spazi (le città hanno sempre polygon, oltre a circle)
    polys: dict = {sid: r["polygon"] for sid, r in regions.items() if "polygon" in r}
    boxes: dict = {sid: bbox(polys[sid]) for sid in polys}

    adj: dict = {sid: set() for sid in polys}

    ids = list(polys.keys())
    for i, a in enumerate(ids):
        for b in ids[i + 1 :]:
            # Salta se i bounding box non si toccano (con pad EPS)
            if not bbox_overlap(boxes[a], boxes[b], pad=EPS):
                continue
            # Salta coppie città-città (le città non si toccano direttamente)
            type_a = next((s["type"] for s in spaces if s["id"] == a), "")
            type_b = next((s["type"] for s in spaces if s["id"] == b), "")
            if type_a == "city" and type_b == "city":
                continue
            if polygons_touch(polys[a], polys[b], EPS):
                adj[a].add(b)
                adj[b].add(a)

    # Forza adiacenza città ↔ provincia di contenimento
    for city, province in CITY_IN_PROVINCE.items():
        if city in adj and province in adj:
            adj[city].add(province)
            adj[province].add(city)

    # Stampa sintesi
    print("Adiacenze calcolate (EPS=%.4f):" % EPS)
    for sid in sorted(adj):
        ns = sorted(adj[sid])
        print(f"  {sid:18s} → {', '.join(ns) if ns else '(nessuno)'}")

    apply = "--apply" in sys.argv
    if not apply:
        print("\n(esegui di nuovo con --apply per scriverle in spaces.json)")
        return

    # Aggiorna spaces.json in-place
    by_id = {s["id"]: s for s in spaces}
    for sid, neighbors in adj.items():
        if sid in by_id:
            by_id[sid]["adjacent"] = sorted(neighbors)
    out_path = os.path.join(data_dir, "spaces.json")
    spaces_doc["_note"] = (
        "8 province + 5 città estratte dal Vassal. Adiacenze calcolate dai "
        "poligoni (regola §1.2.3); città legate alla provincia di contenimento. "
        "Popolazione (pop) letta dalla mappa stampata."
    )
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(spaces_doc, f, ensure_ascii=False, indent=2)
    print(f"\nAggiornato {out_path}")


if __name__ == "__main__":
    main()

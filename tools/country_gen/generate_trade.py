"""Génère le commerce de départ : data/countries/trade.json.

- Exportations et importations en % du PIB : tableau Wikipédia dans sa version du 1er janvier 2026,
  saisies ou estimées pour les pays absents.
- Surtaxes bilatérales en vigueur au 1er janvier 2026 : trade_config.json.
- Flux entre pays (modèle gravitaire) : le commerce entre deux pays est d'autant plus fort qu'ils sont
  proches (capitales), qu'ils ont un accord commercial (data/trade_agreements) ou une frontière commune ;
  les flux sont calés par ajustement proportionnel itératif sur les exportations et importations réelles.
  Seuls les principaux partenaires sont gardés (« partners » : exportations vers chaque partenaire, en Md$).

Usage : python tools/country_gen/generate_trade.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"
KIND_ORDER = ["customs_union", "free_trade", "partial"]

sys.path.insert(0, str(TOOL_DIR))
from country_lookup import CountryLookup, column, fetch_page_as_of, find_table  # noqa: E402
from wiki_tables import read_tables  # noqa: E402


def distance_km(a: tuple[float, float], b: tuple[float, float], width: float, height: float, radius: float) -> float:
    lat_a = math.radians(90.0 - a[1] / height * 180.0)
    lat_b = math.radians(90.0 - b[1] / height * 180.0)
    delta = math.radians((b[0] - a[0]) / width * 360.0)
    cosine = math.sin(lat_a) * math.sin(lat_b) + math.cos(lat_a) * math.cos(lat_b) * math.cos(delta)
    return radius * math.acos(max(-1.0, min(1.0, cosine)))


def pair_kinds(agreements: dict) -> dict[tuple[str, str], str]:
    kinds: dict[tuple[str, str], str] = {}
    for agreement in agreements.values():
        for a in agreement["members"]:
            for b in agreement["members"]:
                if a == b:
                    continue
                current = kinds.get((a, b))
                if current is None or KIND_ORDER.index(agreement["kind"]) < KIND_ORDER.index(current):
                    kinds[(a, b)] = agreement["kind"]
    return kinds


def land_borders(provinces: dict) -> set[tuple[str, str]]:
    borders = set()
    for province in provinces.values():
        owner = province.get("owner", "")
        for neighbor in province.get("neighbors", []):
            other = provinces.get(str(neighbor), {}).get("owner", "")
            if owner and other and other != owner:
                borders.add((owner, other))
    return borders


def fit_flows(tags: list[str], exports: dict, imports: dict, affinity: dict, iterations: int) -> dict:
    scale = sum(exports.values()) / sum(imports.values())
    a = {t: 1.0 for t in tags}
    b = {t: 1.0 for t in tags}
    for _ in range(iterations):
        for i in tags:
            total = sum(b[j] * affinity[i][j] for j in affinity[i])
            a[i] = exports[i] / total if total > 0 else 0.0
        for j in tags:
            total = sum(a[i] * affinity[i][j] for i in tags if j in affinity[i])
            b[j] = imports[j] * scale / total if total > 0 else 0.0
    return {i: {j: a[i] * b[j] * affinity[i][j] for j in affinity[i]} for i in tags}


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    cfg = json.loads((TOOL_DIR / "trade_config.json").read_text(encoding="utf-8"))
    countries: dict = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    provinces: dict = json.loads((DATA_DIR / "provinces" / "provinces.json").read_text(encoding="utf-8"))
    agreements: dict = json.loads((DATA_DIR / "trade_agreements" / "agreements.json").read_text(encoding="utf-8"))
    map_info = json.loads((DATA_DIR / "map" / "map.json").read_text(encoding="utf-8"))["map"]
    lookup = CountryLookup(countries, config["aliases"], config["dependency_owners"])
    table = find_table(read_tables(fetch_page_as_of(cfg["wikipedia_page"], cfg["as_of"])), ["Exports", "Imports"])
    export_share = lookup.values_by_tag(table, 0, column(table, ["Exports"]), "commerce")
    import_share = lookup.values_by_tag(table, 0, column(table, ["Imports"]), "commerce")
    fallback = cfg["fallback_openness"]
    surcharges = {tag: values for tag, values in cfg["surcharges"].items() if tag != "comment"}
    gravity = cfg["gravity"]

    tags = sorted(countries)
    estimated = []
    exports: dict[str, float] = {}
    imports: dict[str, float] = {}
    shares: dict[str, tuple[float, float]] = {}
    for tag in tags:
        gdp = max(countries[tag]["economy"]["gdp_billion_usd"], 0.1)
        guess = min(max(fallback["base"] - fallback["slope"] * math.log(gdp), fallback["min"]), fallback["max"]) / 2.0
        manual = cfg["manual_openness"].get(tag)
        if manual:
            ex, im = manual
        elif tag in export_share and tag in import_share:
            ex, im = export_share[tag], import_share[tag]
        else:
            ex, im = guess, guess
            estimated.append(tag)
        shares[tag] = (ex, im)
        exports[tag] = gdp * ex / 100.0
        imports[tag] = gdp * im / 100.0

    kinds = pair_kinds(agreements)
    borders = land_borders(provinces)
    capitals = {}
    for tag in tags:
        center = provinces[str(countries[tag]["capital"])]["center"]
        capitals[tag] = (center[0], center[1])
    affinity: dict[str, dict[str, float]] = {}
    for i in tags:
        row = {}
        for j in tags:
            if i == j:
                continue
            distance = max(distance_km(capitals[i], capitals[j], map_info["width"], map_info["height"],
                                       gravity["earth_radius_km"]), gravity["min_distance_km"])
            bonus = gravity["agreement_bonus"].get(kinds.get((i, j), ""), 0.0)
            if (i, j) in borders:
                bonus += gravity["border_bonus"]
            factor = gravity["pair_factors"].get(f"{i}-{j}", gravity["pair_factors"].get(f"{j}-{i}", 1.0))
            row[j] = factor * (1.0 + bonus) / distance ** gravity["distance_exponent"]
        affinity[i] = row
    flows = fit_flows(tags, exports, imports, affinity, gravity["fitting_iterations"])

    out = {}
    for tag in tags:
        trade = {"exports": round(shares[tag][0], 2), "imports": round(shares[tag][1], 2)}
        if tag in surcharges:
            trade["surcharges"] = surcharges[tag]
        row = sorted(flows[tag].items(), key=lambda kv: -kv[1])
        total = sum(v for _, v in row)
        kept = [(j, v) for j, v in row[:gravity["max_partners"]] if total > 0 and v / total >= gravity["min_partner_share"]]
        trade["partners"] = {j: round(v, 3) for j, v in kept}
        out[tag] = {"trade": trade}

    path = DATA_DIR / "countries" / "trade.json"
    lines = [f'  "{k}": {json.dumps(v, ensure_ascii=False, separators=(",", ": "))}' for k, v in out.items()]
    path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    print(f"{len(out)} pays ; ouverture estimée pour : {', '.join(estimated)}")
    for tag in ("USA", "CHN", "JPN", "IND", "DEU", "BRA", "RUS", "AUS", "KOR", "FRA"):
        partners = out[tag]["trade"]["partners"]
        total = sum(flows[tag].values())
        print(f"  {tag} : " + ", ".join(f"{j} {v / total * 100:.0f} %" for j, v in list(partners.items())[:6]))


if __name__ == "__main__":
    main()

"""Génère les relations diplomatiques de départ entre tous les pays : data/countries/relations.json.

Règles (relations_config.json) : organisations communes, poids du commerce bilatéral, proximité des régimes,
frontières communes, blocs opposés ; puis une centaine de paires saisies d'après la situation au 1er janvier
2026, qui remplacent le calcul.

Usage : python tools/country_gen/generate_relations.py
"""

from __future__ import annotations

import json
import math
from itertools import combinations
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"
LIMIT = 100


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def neighbours(provinces: dict) -> set[tuple[str, str]]:
    result: set[tuple[str, str]] = set()
    for province in provinces.values():
        owner = province.get("owner", "")
        for other_id in province.get("neighbors", []):
            other = provinces.get(str(other_id), {}).get("owner", "")
            if owner and other and owner != other:
                result.add(tuple(sorted((owner, other))))
    return result


def main() -> None:
    cfg = load(TOOL_DIR / "relations_config.json")
    countries: dict = load(DATA_DIR / "countries" / "countries.json")
    trade: dict = load(DATA_DIR / "countries" / "trade.json")
    regimes: dict = load(DATA_DIR / "regimes" / "regimes.json")
    organizations: dict = load(DATA_DIR / "names" / "organizations.json")["organizations"]
    borders = neighbours(load(DATA_DIR / "provinces" / "provinces.json"))
    tags = sorted(countries)
    for tag, data in load(DATA_DIR / "countries" / "politics.json").items():
        countries[tag].update(data)

    def trade_share(a: str, b: str) -> float:
        partners: dict = trade.get(a, {}).get("trade", {}).get("partners", {})
        total = sum(partners.values())
        return partners.get(b, 0.0) / total if total > 0 else 0.0

    bloc_of: dict[str, set[str]] = {}
    for name, members in cfg["blocs"].items():
        for tag in members:
            bloc_of.setdefault(tag, set()).add(name)

    values: dict[tuple[str, str], float] = {}
    for a, b in combinations(tags, 2):
        value = 0.0
        shared = set(countries[a].get("organizations", [])) & set(countries[b].get("organizations", []))
        for org in shared:
            value += cfg["organization_bonus"].get(organizations.get(org, {}).get("kind", ""), 0)
        share = max(trade_share(a, b), trade_share(b, a))
        value += min(cfg["trade_factor"] * math.sqrt(share), cfg["trade_cap"])
        dem_a = regimes.get(countries[a]["regime"], {}).get("democratic", False)
        dem_b = regimes.get(countries[b]["regime"], {}).get("democratic", False)
        value += cfg["regime"]["both_democratic" if dem_a and dem_b else "both_other" if not (dem_a or dem_b) else "mixed"]
        if (a, b) in borders:
            value += cfg["neighbor_bonus"]
        for first, second, points in cfg["bloc_relations"]:
            if (first in bloc_of.get(a, set()) and second in bloc_of.get(b, set())) or \
                    (second in bloc_of.get(a, set()) and first in bloc_of.get(b, set())):
                value += points
        values[(a, b)] = value
    unknown = []
    for a, b, points in cfg["pairs"]:
        if a not in countries or b not in countries:
            unknown.append(f"{a}-{b}")
            continue
        values[tuple(sorted((a, b)))] = float(points)
    if unknown:
        raise SystemExit("Pays inconnus : " + ", ".join(unknown))

    out: dict[str, dict] = {tag: {} for tag in tags}
    for (a, b), value in values.items():
        rounded = int(round(max(-LIMIT, min(LIMIT, value))))
        if abs(rounded) >= cfg["min_stored"]:
            out[a][b] = rounded
            out[b][a] = rounded
    path = DATA_DIR / "countries" / "relations.json"
    lines = [f'  "{tag}": {json.dumps({"relations": dict(sorted(out[tag].items()))}, separators=(",", ":"))}'
             for tag in tags]
    path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    pairs = sum(len(v) for v in out.values()) // 2
    print(f"{len(tags)} pays, {pairs} paires enregistrées, {len(cfg['pairs'])} paires saisies")
    for a, b in [("FRA", "DEU"), ("USA", "CHN"), ("FRA", "SEN"), ("BRA", "ARG"), ("NGA", "GHA"), ("JPN", "THA")]:
        print(a, b, out[a].get(b, 0))


if __name__ == "__main__":
    main()

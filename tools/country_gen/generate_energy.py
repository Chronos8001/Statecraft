"""Génère la production d'électricité par source de chaque pays : data/countries/energy.json.

Source : *List of countries by electricity production* (version du 1er janvier 2026), production en TWh
par source (dernière année connue). Pays absents : production estimée d'après le PIB (intensité
électrique par niveau de revenu) et mix par défaut (energy_config.json).

Usage : python tools/country_gen/generate_energy.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"
BILLION = 1.0e9

sys.path.insert(0, str(TOOL_DIR))
from country_lookup import CountryLookup, fetch_page_as_of, find_table  # noqa: E402
from wiki_tables import read_tables  # noqa: E402


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    cfg = json.loads((TOOL_DIR / "energy_config.json").read_text(encoding="utf-8"))
    countries: dict = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    lookup = CountryLookup(countries, config["aliases"], config["dependency_owners"])
    table = find_table(read_tables(fetch_page_as_of(cfg["wikipedia_page"], cfg["as_of"])), ["Total (TWh)"])
    columns = cfg["source_columns"]
    values = {source: lookup.values_by_tag(table, 0, index, "électricité") for source, index in columns.items()}

    out = {}
    estimated = []
    for tag in sorted(countries):
        generation = {source: round(values[source][tag], 3) for source in columns if tag in values[source]}
        if sum(generation.values()) <= 0:
            country = countries[tag]
            gdp_per_capita = country["economy"]["gdp_billion_usd"] * BILLION / max(country["population"], 1)
            group = "rich" if gdp_per_capita >= cfg["rich_gdp_per_capita"] else "other"
            total = country["economy"]["gdp_billion_usd"] * cfg["twh_per_billion_gdp"][group]
            generation = {source: round(total * share, 3) for source, share in cfg["default_mix"].items()}
            estimated.append(tag)
        out[tag] = {"energy": {"generation": {s: v for s, v in generation.items() if v > 0}}}

    path = DATA_DIR / "countries" / "energy.json"
    lines = [f'  "{k}": {json.dumps(v, ensure_ascii=False, separators=(",", ": "))}' for k, v in out.items()]
    path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    world = sum(sum(v["energy"]["generation"].values()) for v in out.values())
    print(f"{len(out)} pays, {world:.0f} TWh ; estimés : {', '.join(estimated)}")


if __name__ == "__main__":
    main()

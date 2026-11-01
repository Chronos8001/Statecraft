"""Génère la recherche de départ de chaque pays : data/countries/research.json.

- Dépense intérieure de R&D en % du PIB : tableau Wikipédia « List of countries by research and development
  spending » au 1er janvier 2026 (OECD, sinon UNECE, sinon Banque mondiale), corrections saisies, estimation selon
  le PIB par habitant pour les pays absents.
- Universités classées dans le top 200 mondial (saisies dans research_config.json).

Usage : python tools/country_gen/generate_research.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"
sys.path.insert(0, str(TOOL_DIR))

from country_lookup import CountryLookup, fetch_page_as_of, normalize  # noqa: E402
from wiki_tables import parse_number, read_tables  # noqa: E402

BILLION = 1.0e9
# Colonnes du tableau : pays, Banque mondiale (%), année, UNECE (%), année, OCDE (%), millions $ PPA, année.
NAME_COLUMN = 0
VALUE_COLUMNS = [5, 3, 1]


def clamp(value: float, low: float, high: float) -> float:
    return min(max(value, low), high)


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    cfg = json.loads((TOOL_DIR / "research_config.json").read_text(encoding="utf-8"))
    countries: dict = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    lookup = CountryLookup(countries, config["aliases"], config["dependency_owners"])
    tables = read_tables(fetch_page_as_of(cfg["page"], cfg["as_of"]))
    table = next(t for t in tables if len(t) > 100)
    measured: dict[str, float] = {}
    for row in table[3:]:
        if len(row) <= max(VALUE_COLUMNS):
            continue
        tag = lookup.tag_of(row[NAME_COLUMN])
        if tag is None:
            if normalize(row[NAME_COLUMN]) not in lookup.dependencies:
                lookup.unmatched.setdefault("R&D", []).append(row[NAME_COLUMN])
            continue
        for index in VALUE_COLUMNS:
            value = parse_number(row[index])
            if value is not None and value > 0.0:
                measured[tag] = value
                break
    rule = cfg["missing_rule"]
    out = {}
    estimated = 0
    for tag in sorted(countries):
        economy = countries[tag]["economy"]
        if tag in cfg["manual_rd"]:
            share = cfg["manual_rd"][tag]
        elif tag in measured:
            share = measured[tag]
        else:
            per_capita = economy["gdp_billion_usd"] * BILLION / max(countries[tag]["population"], 1)
            share = clamp(rule["base"] + rule["per_decade"] * math.log10(max(per_capita, 1.0) / rule["reference_gdp_per_capita"]),
                          rule["min"], rule["max"])
            estimated += 1
        out[tag] = {"research": {"rd_gdp_share": round(share, 2), "universities": int(cfg["universities"].get(tag, 0))}}
    (DATA_DIR / "countries" / "research.json").write_text(
        "{\n" + ",\n".join(f'  "{tag}": {json.dumps(value, ensure_ascii=False)}' for tag, value in out.items()) + "\n}\n",
        encoding="utf-8")
    print(f"{len(out)} pays, {len(measured)} mesurés, {estimated} estimés.")
    for label, names in lookup.unmatched.items():
        print(f"Non reconnus ({label}) : {', '.join(sorted(set(names)))}")


if __name__ == "__main__":
    main()

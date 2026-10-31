"""Génère la propriété publique, les investissements étrangers et les fonds souverains de départ :
data/countries/investment.json (fusionné avec countries.json).

- Part publique de chaque secteur : règles (régime, secteur, pays pétroliers) et valeurs saisies.
- IDE entrants en % du PIB : *List of countries by received FDI* (Banque mondiale), version du 1er janvier 2026.
- Fonds souverains : *List of sovereign wealth funds* (actifs cumulés par pays, en milliards de dollars).
- Politique d'ouverture aux IDE au départ : investment_config.json.

Usage : python tools/country_gen/generate_investment.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"

sys.path.insert(0, str(TOOL_DIR))
from country_lookup import CountryLookup, column, fetch_page_as_of, find_table, normalize  # noqa: E402
from wiki_tables import parse_number, read_tables  # noqa: E402


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    cfg = json.loads((TOOL_DIR / "investment_config.json").read_text(encoding="utf-8"))
    countries: dict = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    economy: dict = json.loads((DATA_DIR / "countries" / "economy.json").read_text(encoding="utf-8"))
    lookup = CountryLookup(countries, config["aliases"], config["dependency_owners"])
    pages = cfg["wikipedia_pages"]

    fdi_table = find_table(read_tables(fetch_page_as_of(pages["fdi"], cfg["as_of"])), ["Country", "WB"])
    fdi = lookup.values_by_tag(fdi_table, 0, cfg["fdi_percent_column"], "IDE")

    funds: dict[str, float] = {}
    fund_table = find_table(read_tables(fetch_page_as_of(pages["funds"], cfg["as_of"])), ["Assets"])
    assets_col = column(fund_table, ["Assets"])
    aliases = {normalize(k): v for k, v in cfg["fund_country_aliases"].items()}
    for row in fund_table[1:]:
        if len(row) <= assets_col:
            continue
        tag = aliases.get(normalize(row[0])) or lookup.tag_of(row[0])
        amount = parse_number(row[assets_col])
        if tag and amount:
            funds[tag] = funds.get(tag, 0.0) + amount
        elif amount:
            lookup.unmatched.setdefault("fonds", []).append(row[0])

    rules = cfg["ownership"]
    policy = cfg["fdi_policy"]
    low, high = cfg["fdi_bounds"]
    out = {}
    for tag in sorted(countries):
        base = rules["regime_base"].get(countries[tag]["regime"], 0.1)
        sectors = economy[tag]["economy"]["sectors"]
        ownership = {}
        for sector, multiplier in rules["sector_multipliers"].items():
            share = base * multiplier
            if sector == "energy" and sectors.get("energy", 0.0) >= rules["energy_rich_share"]:
                share += rules["energy_rich_bonus"]
            ownership[sector] = min(share, 1.0)
        ownership.update(rules["manual"].get(tag, {}))
        level = "restricted" if tag in policy["restricted"] else "screening" if tag in policy["screening"] else "open"
        entry = {"public_ownership": {k: round(v, 3) for k, v in ownership.items()},
                 "fdi_inflow": round(min(max(fdi.get(tag, cfg["default_fdi"]), low), high), 2),
                 "fdi_policy": level}
        if tag in funds:
            entry["sovereign_fund"] = round(funds[tag], 1)
        out[tag] = {"investment": entry}

    path = DATA_DIR / "countries" / "investment.json"
    lines = [f'  "{k}": {json.dumps(v, ensure_ascii=False, separators=(",", ": "))}' for k, v in out.items()]
    path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    top = sorted(funds.items(), key=lambda kv: -kv[1])[:8]
    print(f"{len(out)} pays ; IDE {len(fdi)} ; fonds : " + ", ".join(f"{t} {v:.0f}" for t, v in top))
    for label, names in lookup.unmatched.items():
        print(f"Non reconnus ({label}) : {', '.join(sorted(set(names)))[:500]}")


if __name__ == "__main__":
    main()

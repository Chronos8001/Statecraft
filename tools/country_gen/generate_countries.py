"""Complète data/countries/countries.json avec les données réelles des pays (source : Wikipédia).

Données ajoutées ou mises à jour pour chaque pays :
  population    tableau « List of countries and dependencies by population » (officiel ou ONU)
  economy       PIB nominal du FMI (2026) et dette publique brute du FMI (2025)
  military      effectifs actifs et de réserve (IISS)
  regime        config.json (situation au 1er janvier 2026)
  organizations config.json (membres au 1er janvier 2026)
Les autres champs (nom, couleur, capitale, dirigeants, partis…) ne sont pas modifiés.
Les valeurs manquantes sont estimées et listées à la fin.

Usage : python tools/country_gen/generate_countries.py
"""

from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"
MILLION = 1_000_000.0
THOUSAND = 1000.0
PERCENT = 100.0

sys.path.insert(0, str(TOOL_DIR))
from country_lookup import CountryLookup, column, fetch_page, find_table  # noqa: E402
from wiki_tables import read_tables  # noqa: E402


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    countries_path = DATA_DIR / "countries" / "countries.json"
    countries: dict = json.loads(countries_path.read_text(encoding="utf-8"))
    lookup = CountryLookup(countries, config["aliases"], config["dependency_owners"])
    values_by_tag = lookup.values_by_tag
    unmatched = lookup.unmatched

    pages = config["wikipedia_pages"]
    gdp_table = find_table(read_tables(fetch_page(pages["gdp"])), ["Country", "IMF"])
    gdp = values_by_tag(gdp_table, 0, column(gdp_table, ["IMF"]), "PIB", add_dependencies=True)
    gdp_fallback = values_by_tag(gdp_table, 0, column(gdp_table, ["World Bank"]), "PIB")
    population_table = find_table(read_tables(fetch_page(pages["population"])), ["Location", "Population"])
    population = values_by_tag(population_table, 0, 1, "population", add_dependencies=True)
    debt_table = find_table(read_tables(fetch_page(pages["debt"])), ["gross debt"])
    debt = values_by_tag(debt_table, 0, column(debt_table, ["gross"]), "dette")
    military_table = find_table(read_tables(fetch_page(pages["military"])), ["Active", "Reserve"])
    active = values_by_tag(military_table, 0, column(military_table, ["Active"]), "armée")
    reserve = values_by_tag(military_table, 0, column(military_table, ["Reserve"]), "armée")

    # Valeurs de repli : médianes des pays connus.
    debt_median = statistics.median(debt.values())
    active_ratio_median = statistics.median(active[t] / population[t] for t in active if population.get(t))
    members: dict[str, list[str]] = {tag: [] for tag in countries}
    for organization, tags in config["organization_members"].items():
        for tag in tags:
            if tag in members:
                members[tag].append(organization)

    estimated: dict[str, list[str]] = {}
    for tag, country in countries.items():
        row = lookup.natural_earth(tag)
        if tag in population:
            country["population"] = int(population[tag])
        else:
            country["population"] = int((row.get("POP_EST") or 0) * config["population_growth_fallback"])
            estimated.setdefault(tag, []).append("population")
        gdp_millions = gdp.get(tag, gdp_fallback.get(tag))
        if gdp_millions is None:
            gdp_millions = max(row.get("GDP_MD") or 0, 0) * 1.0
            estimated.setdefault(tag, []).append("PIB")
        economy = dict(country.get("economy", {}))
        economy["gdp_billion_usd"] = round(gdp_millions * THOUSAND / MILLION, 2)
        if tag in debt:
            economy["debt_to_gdp"] = round(debt[tag] / PERCENT, 3)
        else:
            economy["debt_to_gdp"] = round(debt_median / PERCENT, 3)
            estimated.setdefault(tag, []).append("dette")
        manual = config["manual_values"].get(tag, {})
        for field in ("gdp_billion_usd", "debt_to_gdp"):
            if field in manual:
                economy[field] = manual[field]
        country["economy"] = economy
        military = dict(country.get("military", {}))
        if tag in config["no_army"]:
            military["active_personnel"] = 0
            military["reserve_personnel"] = 0
        elif tag in active:
            military["active_personnel"] = int(active[tag])
            military["reserve_personnel"] = int(reserve.get(tag, 0))
        else:
            military["active_personnel"] = int(country["population"] * active_ratio_median)
            military["reserve_personnel"] = 0
            estimated.setdefault(tag, []).append("armée")
        country["military"] = military
        if tag not in config["regimes"]:
            raise SystemExit(f"Régime manquant dans config.json : {tag}")
        country["regime"] = config["regimes"][tag]
        organizations = [] if tag in config["not_un_members"] else ["un"]
        country["organizations"] = organizations + members[tag]

    lines = [f'  "{tag}": {json.dumps(countries[tag], ensure_ascii=False, separators=(",", ": "))}'
             for tag in sorted(countries)]
    countries_path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")

    print(f"{len(countries)} pays mis à jour.")
    print(f"Sources trouvées : population {len(population)}, PIB {len(gdp)}, dette {len(debt)}, armée {len(active)}.")
    for label, names in unmatched.items():
        print(f"Lignes non reconnues ({label}) : {', '.join(sorted(set(names)))}")
    for tag, fields in sorted(estimated.items()):
        print(f"  Estimé pour {tag} : {', '.join(fields)}")


if __name__ == "__main__":
    main()

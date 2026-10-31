"""Génère la société de départ de chaque pays : data/countries/society.json.

- Poids des 10 groupes sociaux (part de la population) : règles de society_config.json appliquées à
  l'âge médian, la part de l'agriculture, l'armée, la place de la religion, la diversité ethnique,
  les inégalités (Gini) et le niveau de revenu.
- Indicateurs : Fragile States Index 2024, indice de perception de la corruption 2024, Democracy Index,
  popularité du gouvernement (saisie pour les grands pays).
Pages Wikipédia dans leur version du 1er janvier 2026.

Usage : python tools/country_gen/generate_society.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"
BILLION = 1.0e9
PERCENT = 100.0

sys.path.insert(0, str(TOOL_DIR))
from country_lookup import CountryLookup, column, fetch_page_as_of, find_table  # noqa: E402
from wiki_tables import read_tables  # noqa: E402


def clamp(value: float, low: float, high: float) -> float:
    return min(max(value, low), high)


def group_shares(country: dict, economy: dict, values: dict, rules: dict) -> dict[str, float]:
    gdp_per_capita = country["economy"]["gdp_billion_usd"] * BILLION / max(country["population"], 1)
    median = values["median_age"]
    r = rules
    shares = {
        "retirees": clamp(r["retirees"]["slope"] * (median - r["retirees"]["per_year_over"]),
                          r["retirees"]["min"], r["retirees"]["max"]),
        "youth": clamp(r["youth"]["base"] - r["youth"]["slope"] * median, r["youth"]["min"], r["youth"]["max"]),
        "farmers": clamp(economy["sectors"]["agriculture"] * r["farmers"]["factor"], r["farmers"]["min"], r["farmers"]["max"]),
        "military": clamp((country["military"]["active_personnel"] + country["military"]["reserve_personnel"])
                          / max(country["population"], 1) * r["military"]["factor"], r["military"]["min"], r["military"]["max"]),
        "religious": values["religiosity"] * r["religious"]["factor"],
        "minorities": values["fractionalization"] * r["minorities"]["factor"],
        "ecologists": r["ecologists"]["rich" if gdp_per_capita >= r["rich_gdp_per_capita"] else
                                      "middle" if gdp_per_capita >= r["middle_gdp_per_capita"] else "poor"],
        "elites": clamp(r["elites"]["base"] + r["elites"]["per_gini_point"] * (values["gini"] - r["elites"]["gini_reference"]),
                        r["elites"]["min"], r["elites"]["max"]),
    }
    taken = sum(shares.values())
    if taken > 1.0 - r["min_remainder"]:
        scale = (1.0 - r["min_remainder"]) / taken
        shares = {k: v * scale for k, v in shares.items()}
    remainder = 1.0 - sum(shares.values())
    w = r["workers_share"]
    workers = clamp(w["base"] - w["slope"] * math.log(max(gdp_per_capita, 1.0) / 1000.0), w["min"], w["max"])
    shares["workers"] = remainder * workers
    shares["middle_class"] = remainder * (1.0 - workers)
    return {k: round(v, 4) for k, v in shares.items()}


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    cfg = json.loads((TOOL_DIR / "society_config.json").read_text(encoding="utf-8"))
    countries: dict = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    economy: dict = json.loads((DATA_DIR / "countries" / "economy.json").read_text(encoding="utf-8"))
    lookup = CountryLookup(countries, config["aliases"], config["dependency_owners"])
    pages = cfg["wikipedia_pages"]

    def tables(key: str) -> list[list[list[str]]]:
        return read_tables(fetch_page_as_of(pages[key], cfg["as_of"]))

    table = find_table(tables("fragility"), ["Country", "2024 score"])
    # Rangs ex æquo fusionnés (rowspan) : la ligne perd sa première cellule.
    table = [[""] + row if len(row) == len(table[0]) - 1 else row for row in table]
    fragility = lookup.values_by_tag(table, 1, 2, "fragilité")
    table = find_table(tables("corruption"), ["Nation", "Score"])
    corruption = lookup.values_by_tag(table, 1, 2, "corruption")
    table = find_table(tables("democracy"), ["Country", "Overall score"])
    democracy = lookup.values_by_tag(table, 2, column(table, ["Overall score"]), "démocratie")
    table = find_table(tables("median_age"), ["Country/Territory", "Median"])
    median_age = lookup.values_by_tag(table, 0, 2, "âge")
    table = find_table(tables("religion"), ["Country", "Yes, important"])
    religiosity = {t: v / PERCENT for t, v in lookup.values_by_tag(table, 0, 1, "religion").items()}
    table = find_table(tables("diversity"), ["Country", "Ethnic fractionalization"])
    fractionalization = lookup.values_by_tag(table, 0, 1, "diversité")
    inequality_tables = [t for t in tables("inequality") if len(t) > 150 and len(t[0]) == 0]
    gini = lookup.values_by_tag(inequality_tables[0], 0, 5, "gini") if inequality_tables else {}

    defaults = cfg["defaults"]
    approval_cfg = cfg["approval"]
    out = {}
    estimated: dict[str, list[str]] = {}
    for tag in sorted(countries):
        manual = cfg["manual"].get(tag, {})

        def pick(source: dict, key: str) -> float:
            if key in manual:
                return manual[key]
            if tag in source:
                return source[tag]
            estimated.setdefault(tag, []).append(key)
            return defaults[key]

        values = {
            "fragility": pick(fragility, "fragility"),
            "corruption_index": pick(corruption, "corruption_index"),
            "democracy": pick(democracy, "democracy"),
            "median_age": pick(median_age, "median_age"),
            "religiosity": pick(religiosity, "religiosity"),
            "fractionalization": pick(fractionalization, "fractionalization"),
            "gini": pick(gini, "gini"),
        }
        stability = clamp(PERCENT - values["fragility"], 0.0, PERCENT)
        approval = approval_cfg.get(tag, approval_cfg["default_base"] + approval_cfg["default_per_stability"] * stability)
        out[tag] = {"society": {
            "groups": group_shares(countries[tag], economy[tag]["economy"], values, cfg["group_rules"]),
            "stability": round(stability, 1),
            "corruption": round(PERCENT - values["corruption_index"], 1),
            "democracy": round(values["democracy"], 2),
            "approval": round(float(approval), 1),
        }}

    path = DATA_DIR / "countries" / "society.json"
    lines = [f'  "{k}": {json.dumps(v, ensure_ascii=False, separators=(",", ": "))}' for k, v in out.items()]
    path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    print(f"{len(out)} pays. Sources : fragilité {len(fragility)}, corruption {len(corruption)}, démocratie {len(democracy)}, "
          f"âge {len(median_age)}, religion {len(religiosity)}, diversité {len(fractionalization)}, Gini {len(gini)}")
    big = {t: f for t, f in estimated.items() if countries[t]["population"] >= 5_000_000}
    for tag, fields in sorted(big.items()):
        print(f"Estimé ({tag}) : {', '.join(fields)}")
    few = {t: f for t, f in estimated.items() if len(f) >= 3}
    print("Pays très estimés : " + ", ".join(f"{t} ({len(f)})" for t, f in sorted(few.items())))


if __name__ == "__main__":
    main()

"""Génère le budget de l'État de chaque pays au 1er janvier 2026 : data/countries/budget.json.

Recettes : total du FMI, réparti entre les impôts selon le niveau de revenu et les rentes des ressources ;
taux réels de l'impôt sur le revenu (plus bas et plus haut), de l'impôt sur les sociétés et de la TVA
(Wikipédia). Dépenses : total du FMI hors intérêts ; éducation et défense réelles, autres postes par
profils et valeurs saisies ; l'administration complète. Le jeu ajuste ensuite les dépenses pour
retrouver exactement le solde de départ.

Usage : python tools/country_gen/generate_budget.py
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
from country_lookup import CountryLookup, column, fetch_page_as_of, find_table  # noqa: E402
from wiki_tables import parse_number, read_tables  # noqa: E402

TAXES = ["income_tax", "corporate_tax", "vat", "carbon_tax", "customs", "social_contributions", "resource_taxes"]
SPENDING = ["health", "education", "pensions", "unemployment", "police", "justice", "defense", "research",
            "infrastructure", "environment", "culture", "foreign_aid", "intelligence", "administration"]


def income_group(gdp_per_capita: float, cfg: dict) -> str:
    if gdp_per_capita >= cfg["income_groups"]["rich"]:
        return "rich"
    return "middle" if gdp_per_capita >= cfg["income_groups"]["middle"] else "poor"


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    cfg = json.loads((TOOL_DIR / "budget_config.json").read_text(encoding="utf-8"))
    countries: dict = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    lookup = CountryLookup(countries, config["aliases"], config["dependency_owners"])
    pages = cfg["wikipedia_pages"]

    def tables(key: str) -> list[list[list[str]]]:
        return read_tables(fetch_page_as_of(pages[key], cfg["as_of"]))

    budget_table = find_table(tables("budget"), ["General net lending"])
    revenue = lookup.values_by_tag(budget_table, 0, column(budget_table, ["Revenue"], 1), "recettes")
    expenditure = lookup.values_by_tag(budget_table, 0, column(budget_table, ["Expenditure"], 1), "dépenses")

    rates_table = find_table(tables("tax_rates"), ["Corporate", "VAT"])
    corporate = lookup.values_by_tag(rates_table, 0, 1, "taux")
    income_low = lookup.values_by_tag(rates_table, 0, 2, "taux")
    income_high = lookup.values_by_tag(rates_table, 0, 3, "taux")
    vat = lookup.values_by_tag(rates_table, 0, column(rates_table, ["VAT"]), "taux")

    military: dict[str, float] = {}
    for table in tables("military"):
        if table and table[0][:2] == ["Rank", "Country"] and any("% of GDP" in h for h in table[0]):
            for tag, value in lookup.values_by_tag(table, 1, column(table, ["% of GDP"]), "défense").items():
                military.setdefault(tag, value)
    education_table = find_table(tables("education"), ["Country", "% of GDP"])
    education = lookup.values_by_tag(education_table, 0, 1, "éducation")

    rents_source = json.loads((DATA_DIR / "countries" / "economy.json").read_text(encoding="utf-8"))
    estimated: dict[str, list[str]] = {}
    out: dict[str, dict] = {}
    for tag in sorted(countries):
        country = countries[tag]
        gdp_per_capita = country["economy"]["gdp_billion_usd"] * BILLION / max(country["population"], 1)
        group = income_group(gdp_per_capita, cfg)
        total_revenue, total_spending = cfg["fallback_totals"][group]
        if tag in revenue and tag in expenditure:
            total_revenue, total_spending = revenue[tag], expenditure[tag]
        else:
            estimated.setdefault(tag, []).append("recettes et dépenses")

        # --- Recettes ---
        energy_share = rents_source[tag]["economy"]["sectors"]["energy"] * 100.0
        resource = min(energy_share * cfg["resource_capture"], total_revenue * cfg["max_resource_share_of_revenue"])
        carbon_rate = float(cfg["carbon_prices"].get(tag, 0.0))
        carbon = carbon_rate * cfg["carbon_revenue_per_point"]
        profile = dict(cfg["revenue_profiles"][group])
        profile.pop("resource_taxes")
        remaining = max(total_revenue - resource - carbon, 0.0)
        weight = sum(profile.values())
        shares = {tax: remaining * value / weight for tax, value in profile.items()}
        shares["resource_taxes"] = resource
        shares["carbon_tax"] = carbon

        manual = cfg["manual_rates"].get(tag, {})
        defaults = cfg["default_rates"]
        low = income_low.get(tag, defaults["income_low"])
        high = max(income_high.get(tag, defaults["income_high"]), low)
        brackets = [round(low + (high - low) * p, 1) for p in cfg["income_bracket_positions"]]
        customs = cfg["customs_rates"].get(tag, cfg["eu_customs_rate"] if tag in cfg["eu_members"]
                                           else cfg["default_customs"][group])
        rates = {
            "corporate_tax": manual.get("corporate_tax", corporate.get(tag, defaults["corporate_tax"])),
            "vat": manual.get("vat", vat.get(tag, defaults["vat"])),
            "carbon_tax": carbon_rate,
            "customs": customs,
            "social_contributions": cfg["contribution_rates"].get(tag, cfg["default_contributions"][group]),
            "resource_taxes": cfg["default_resource_rate"],
        }
        for key, source in (("corporate_tax", corporate), ("vat", vat)):
            if tag not in source and key not in manual:
                estimated.setdefault(tag, []).append(key)
        taxes = {"income_tax": {"brackets": brackets, "revenue": round(shares["income_tax"], 3)}}
        for tax in TAXES[1:]:
            taxes[tax] = {"rate": round(float(rates[tax]), 2), "revenue": round(shares[tax], 3)}

        # --- Dépenses (hors intérêts) ---
        target = total_spending * (1.0 - cfg["interest_share_of_expenditure"][group])
        spending = dict(cfg["spending"]["profiles"][group])
        spending.update({k: v for k, v in cfg["spending"]["manual"].get(tag, {}).items()})
        if tag in education:
            spending["education"] = education[tag]
        if tag in military:
            spending["defense"] = military[tag]
        fixed = sum(spending.values())
        administration = target - fixed
        minimum = cfg["spending"]["min_administration"]
        if administration < minimum:
            scale = (target - minimum) / fixed if fixed > 0 else 0.0
            spending = {k: v * max(scale, 0.0) for k, v in spending.items()}
            administration = minimum
        spending["administration"] = administration
        out[tag] = {"budget": {"taxes": taxes, "spending": {k: round(spending[k], 3) for k in SPENDING}}}

    path = DATA_DIR / "countries" / "budget.json"
    lines = [f'  "{tag}": {json.dumps(out[tag], ensure_ascii=False, separators=(",", ": "))}' for tag in out]
    path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    print(f"{len(out)} budgets écrits.")
    print(f"Sources : recettes {len(revenue)}, dépenses {len(expenditure)}, taux {len(corporate)}, "
          f"défense {len(military)}, éducation {len(education)}.")
    for label, names in lookup.unmatched.items():
        print(f"Lignes non reconnues ({label}) : {', '.join(sorted(set(names)))}")
    for tag, fields in sorted(estimated.items()):
        print(f"  Estimé pour {tag} : {', '.join(fields)}")


if __name__ == "__main__":
    main()

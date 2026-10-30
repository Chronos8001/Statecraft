"""Génère les données macroéconomiques de départ (1er janvier 2026).

Sorties :
  data/countries/economy.json      monnaie, croissance, inflation, chômage, solde budgétaire, note, secteurs
                                   (fusionné avec countries.json au chargement)
  data/currencies/currencies.json  monnaies : taux de change, taux directeur, cible d'inflation, ancrage

Sources : tableaux Wikipédia dans leur version du 1er janvier 2026 (FMI, Banque mondiale, S&P, Fitch,
Moody's), taux de change du 1er janvier 2026 (currency-api). Réglages et corrections : economy_config.json.

Usage : python tools/country_gen/generate_economy.py
"""

from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"
PERCENT = 100.0
BILLION = 1.0e9

sys.path.insert(0, str(TOOL_DIR))
from country_lookup import CACHE_DIR, CountryLookup, column, download, fetch_page_as_of, find_table  # noqa: E402
from wiki_tables import parse_number, read_tables  # noqa: E402

RATINGS = ["AAA", "AA+", "AA", "AA-", "A+", "A", "A-", "BBB+", "BBB", "BBB-", "BB+", "BB", "BB-", "B+", "B", "B-",
           "CCC+", "CCC", "CCC-", "CC", "C", "SD"]
MOODY = {"Aaa": "AAA", "Aa1": "AA+", "Aa2": "AA", "Aa3": "AA-", "A1": "A+", "A2": "A", "A3": "A-",
         "Baa1": "BBB+", "Baa2": "BBB", "Baa3": "BBB-", "Ba1": "BB+", "Ba2": "BB", "Ba3": "BB-", "B1": "B+",
         "B2": "B", "B3": "B-", "Caa1": "CCC+", "Caa2": "CCC", "Caa3": "CCC-", "Ca": "CC", "C": "C"}
DEFAULT_RATINGS = {"RD": "SD", "D": "SD", "SD": "SD"}
MAJOR_AGENCY_COUNT = 3
SECTORS = ["agriculture", "industry", "energy", "armament", "services", "tech", "finance", "tourism"]


def normalize_rating(text: str) -> str | None:
    text = text.replace("−", "-").replace("–", "-").split(" ")[0].strip()
    if text in MOODY:
        return MOODY[text]
    if text in DEFAULT_RATINGS:
        return DEFAULT_RATINGS[text]
    return text if text in RATINGS else None


def rating_tables(tables: list[list[list[str]]]) -> list[tuple[str, list[list[str]]]]:
    """Tableaux des trois grandes agences (les trois premiers de la page), avec l'agence devinée
    (Moody's a sa propre échelle)."""
    result = []
    for table in tables:
        if not table or table[0][:2] != ["Country/Territory", "Rating"]:
            continue
        values = [row[1].split(" ")[0] for row in table[1:] if len(row) > 1]
        agency = "Moody" if sum(v in MOODY and v not in RATINGS for v in values) > len(values) / 2 else "other"
        result.append((agency, table))
    return result[:MAJOR_AGENCY_COUNT]


def year_columns(table: list[list[str]]) -> list[int]:
    """Colonnes des années, de la plus récente à la plus ancienne."""
    years = [(int(h), i) for i, h in enumerate(table[0]) if h.strip().isdigit()]
    return [i for _, i in sorted(years, reverse=True)]


def split_sectors(tag: str, shares: dict[str, float], rents: float, gdp_per_capita: float, rules: dict) -> dict:
    """Répartit agriculture / industrie / services entre les 8 secteurs du jeu (fractions du PIB)."""
    total = shares["agriculture"] + shares["industry"] + shares["services"]
    agriculture = shares["agriculture"] / total * PERCENT
    industry = shares["industry"] / total * PERCENT
    services = shares["services"] / total * PERCENT

    energy = min(max(rents * rules["energy_rents_share"], industry * rules["min_energy_share_of_industry"]),
                 industry * rules["max_energy_share_of_industry"])
    armament = min(rules["arms"].get(tag, rules["default_arms"]), (industry - energy) * 0.5)
    industry -= energy + armament

    rich = gdp_per_capita >= rules["rich_gdp_per_capita"]
    finance = rules["finance"].get(tag, rules["default_finance_rich"] if rich else rules["default_finance"])
    tourism = min(rules["tourism"].get(tag, rules["default_tourism"]), services * rules["max_tourism_share_of_services"])
    tech = rules["tech"].get(tag)
    if tech is None:
        tech = next(value for threshold, value in rules["tech_by_income"] if gdp_per_capita >= threshold)
    floor = services * rules["min_services_share_of_services"]
    excess = finance + tourism + tech - (services - floor)
    if excess > 0:
        scale = (services - floor) / (finance + tourism + tech)
        finance, tourism, tech = finance * scale, tourism * scale, tech * scale
    services -= finance + tourism + tech

    values = {"agriculture": agriculture, "industry": industry, "energy": energy, "armament": armament,
              "services": services, "tech": tech, "finance": finance, "tourism": tourism}
    return {sector: round(values[sector] / PERCENT, 4) for sector in SECTORS}


def foreign_debt_share(tag: str, currency: str, gdp_per_capita: float, eco: dict) -> float:
    """Part de la dette en devises : saisie pour les pays connus, sinon selon la monnaie et le revenu."""
    rules = eco["foreign_debt"]
    if tag in rules["shares"]:
        return rules["shares"][tag]
    if currency in rules["reserve_currencies"]:
        return 0.0
    if gdp_per_capita >= eco["sectors"]["rich_gdp_per_capita"]:
        return rules["rich"]
    return rules["middle"] if gdp_per_capita >= rules["middle_gdp_per_capita"] else rules["poor"]


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    eco = json.loads((TOOL_DIR / "economy_config.json").read_text(encoding="utf-8"))
    countries: dict = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    lookup = CountryLookup(countries, config["aliases"], config["dependency_owners"])
    pages = eco["wikipedia_pages"]
    as_of = eco["as_of"]

    def tables(key: str) -> list[list[list[str]]]:
        return read_tables(fetch_page_as_of(pages[key], as_of))

    growth_table = find_table(tables("growth"), ["Country", "Rate"])
    growth = lookup.values_by_tag(growth_table, 0, 1, "croissance")

    inflation_table = find_table(tables("inflation"), ["Country", "2024"])
    inflation: dict[str, float] = {}
    for year_col in year_columns(inflation_table):  # dernière année connue de chaque pays
        for tag, value in lookup.values_by_tag(inflation_table, 0, year_col, "inflation").items():
            inflation.setdefault(tag, value)

    unemployment_table = find_table(tables("unemployment"), ["Country", "Unemployment"])
    unemployment: dict[str, float] = {}
    for source_col in (3, 2, 1):  # FMI, Banque mondiale, CIA
        for tag, value in lookup.values_by_tag(unemployment_table, 0, source_col, "chômage").items():
            unemployment.setdefault(tag, value)

    rate_table = find_table(tables("policy_rates"), ["Central bank interest rate"])
    rates_by_name = lookup.values_by_tag(rate_table, 0, 1, "taux directeur", extra_names=eco["union_rate_names"])

    budget_table = find_table(tables("budget"), ["General net lending"])
    budget = lookup.values_by_tag(budget_table, 0, column(budget_table, ["General net lending"], 1), "solde")

    sector_tables = tables("sectors")
    sector_table = find_table(sector_tables, ["Agriculture", "Industry", "Services"])
    agriculture = lookup.values_by_tag(sector_table, 0, column(sector_table, ["Agriculture"]), "secteurs")
    industry = lookup.values_by_tag(sector_table, 0, column(sector_table, ["Industry"]), "secteurs")
    services = lookup.values_by_tag(sector_table, 0, column(sector_table, ["Services"]), "secteurs")
    rents_table = find_table(sector_tables, ["Oil", "Natural Gas", "Coal"])
    oil = lookup.values_by_tag(rents_table, 0, column(rents_table, ["Oil"]), "rentes")
    gas = lookup.values_by_tag(rents_table, 0, column(rents_table, ["Natural Gas"]), "rentes")
    coal = lookup.values_by_tag(rents_table, 0, column(rents_table, ["Coal"]), "rentes")

    ratings: dict[str, str] = {}
    agencies = rating_tables(tables("ratings"))
    ordered = [t for a, t in agencies if a != "Moody"] + [t for a, t in agencies if a == "Moody"]
    for table in ordered:
        for tag, text in lookup.text_by_tag(table, 0, 1, "notes").items():
            rating = normalize_rating(text)
            if rating is not None:
                ratings.setdefault(tag, rating)

    usd_rates: dict[str, float] = json.loads(
        download(eco["exchange_rates_url"]).decode("utf-8"))["usd"] if not (CACHE_DIR / "usd_rates.json").exists() \
        else json.loads((CACHE_DIR / "usd_rates.json").read_text(encoding="utf-8"))
    (CACHE_DIR / "usd_rates.json").write_text(json.dumps(usd_rates), encoding="utf-8")
    usd_rates.update(eco["manual_usd_rates"])

    estimated: dict[str, list[str]] = {}
    medians = {
        "growth": statistics.median(growth.values()),
        "inflation": statistics.median(inflation.values()),
        "unemployment": statistics.median(unemployment.values()),
        "budget": statistics.median(budget.values()),
    }

    # --- Pays ---
    out_countries: dict[str, dict] = {}
    for tag in sorted(countries):
        country = countries[tag]
        currency = eco["currencies"][tag]
        population = max(int(country["population"]), 1)
        gdp_per_capita = float(country["economy"]["gdp_billion_usd"]) * BILLION / population

        def pick(values: dict[str, float], key: str, label: str) -> float:
            if tag in values:
                return values[tag]
            estimated.setdefault(tag, []).append(label)
            return medians[key]

        economy: dict = {
            "growth": round(pick(growth, "growth", "croissance"), 2),
            "inflation": round(eco["manual_inflation"][tag] if tag in eco["manual_inflation"]
                               else pick(inflation, "inflation", "inflation"), 2),
            "unemployment": round(pick(unemployment, "unemployment", "chômage"), 2),
            "budget_balance": round(pick(budget, "budget", "solde"), 2),
        }
        if tag in ratings:
            economy["rating"] = ratings[tag]
        if tag in agriculture and tag in industry and tag in services:
            shares = {"agriculture": agriculture[tag], "industry": industry[tag], "services": services[tag]}
        else:
            shares = dict(eco["sectors"]["fallback_shares"])
            estimated.setdefault(tag, []).append("secteurs")
        rents = oil.get(tag, 0.0) + gas.get(tag, 0.0) + coal.get(tag, 0.0)
        economy["sectors"] = split_sectors(tag, shares, rents, gdp_per_capita, eco["sectors"])
        economy["foreign_debt_share"] = foreign_debt_share(tag, currency, gdp_per_capita, eco)
        economy.update(eco["manual_values"].get(tag, {}))
        out_countries[tag] = {"currency": currency, "economy": economy}

    # --- Monnaies ---
    users: dict[str, list[str]] = {}
    for tag, currency in eco["currencies"].items():
        users.setdefault(currency, []).append(tag)
    out_currencies: dict[str, dict] = {}
    for currency in sorted(users):
        members = sorted(users[currency])
        issuer = eco["currency_issuers"].get(currency, members[0] if len(members) == 1 else "")
        rate = rates_by_name.get(currency) if currency in eco["union_rate_names"].values() else None
        if rate is None and issuer:
            rate = rates_by_name.get(issuer)
        member_inflation = statistics.median(out_countries[t]["economy"]["inflation"] for t in members)
        target = eco["inflation_targets"].get(currency)
        if target is None:
            target = eco["high_inflation_target"] if member_inflation > eco["high_inflation_threshold"] \
                else eco["default_inflation_target"]
        peg = eco["pegs"].get(currency, "")
        entry = {
            "code": currency.upper(),
            "usd_rate": round(1.0 if currency == "usd" else usd_rates[currency], 6),
            "inflation_target": target,
            "peg": peg,
            "issuer": issuer,
        }
        if rate is None:
            # Taux inconnu : inflation (au moins la cible) + taux réel neutre.
            rate = max(member_inflation, target) + eco["neutral_real_rate_estimate"]
            estimated.setdefault(currency, []).append("taux directeur")
        entry["policy_rate"] = round(rate, 2)
        regime = countries[issuer]["regime"] if issuer else ""
        independent = currency in eco["independent_central_banks"] or (
            currency not in eco["dependent_central_banks"] and regime not in eco["dependent_regimes"])
        entry["independent"] = independent
        out_currencies[currency] = entry

    def write(path: Path, table: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        lines = [f'  "{key}": {json.dumps(table[key], ensure_ascii=False, separators=(",", ": "))}' for key in table]
        path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")

    write(DATA_DIR / "countries" / "economy.json", out_countries)
    write(DATA_DIR / "currencies" / "currencies.json", out_currencies)

    print(f"{len(out_countries)} pays, {len(out_currencies)} monnaies.")
    print(f"Sources : croissance {len(growth)}, inflation {len(inflation)}, chômage {len(unemployment)}, "
          f"taux {len(rates_by_name)}, solde {len(budget)}, notes {len(ratings)}, secteurs {len(services)}.")
    for label, names in lookup.unmatched.items():
        print(f"Lignes non reconnues ({label}) : {', '.join(sorted(set(names)))}")
    for key, fields in sorted(estimated.items()):
        print(f"  Estimé pour {key} : {', '.join(fields)}")


if __name__ == "__main__":
    main()

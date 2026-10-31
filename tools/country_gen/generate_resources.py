"""Génère la production et la consommation des ressources stratégiques au 1er janvier 2026.

Sorties :
  data/countries/resources.json   production et consommation par pays (unités de data/resources),
                                  eau renouvelable et taux de prélèvement (fusionné avec countries.json)
  data/provinces/resources.json   richesse (1 à 10) des provinces productrices (fusionné avec provinces.json)

Sources : tableaux Wikipédia dans leur version du 1er janvier 2026 (pétrole, gaz, charbon, uranium,
nucléaire, acier, blé, eau), producteurs saisis pour les terres rares, le lithium, le cobalt et les
semi-conducteurs (resources_config.json). La consommation mondiale de chaque ressource est ramenée
à sa production mondiale (marché équilibré au départ).

Usage : python tools/country_gen/generate_resources.py
"""

from __future__ import annotations

import csv
import json
import math
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"
BARRELS_PER_MILLION = 1.0e6
CUBIC_METERS_PER_BILLION = 1.0e3  # tableaux du gaz en millions de m³
RICHNESS_SCALE = 1.5
MAX_RICHNESS = 10

sys.path.insert(0, str(TOOL_DIR))
from country_lookup import CountryLookup, column, fetch_page_as_of, find_table  # noqa: E402
from wiki_tables import parse_number, read_tables  # noqa: E402


def industrial_weights(countries: dict, economy: dict) -> dict[str, float]:
    """PIB industriel (industrie, énergie, armement, tech) de chaque pays, en milliards de dollars."""
    weights = {}
    for tag, country in countries.items():
        sectors = economy[tag]["economy"]["sectors"]
        share = sectors["industry"] + sectors["energy"] + sectors["armament"] + sectors["tech"]
        weights[tag] = country["economy"]["gdp_billion_usd"] * share
    return weights


def spread_shares(total: float, shares: dict[str, float], weights: dict[str, float]) -> dict[str, float]:
    """Parts saisies pour les grands consommateurs, le reste au prorata des poids."""
    result = {tag: total * share for tag, share in shares.items()}
    rest = total * max(1.0 - sum(shares.values()), 0.0)
    others = {tag: w for tag, w in weights.items() if tag not in shares}
    weight_sum = sum(others.values())
    for tag, weight in others.items():
        result[tag] = rest * weight / weight_sum if weight_sum > 0 else 0.0
    return result


def normalize(values: dict[str, float], target: float) -> dict[str, float]:
    total = sum(values.values())
    return {tag: value * target / total for tag, value in values.items()} if total > 0 else values


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    cfg = json.loads((TOOL_DIR / "resources_config.json").read_text(encoding="utf-8"))
    countries: dict = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    economy: dict = json.loads((DATA_DIR / "countries" / "economy.json").read_text(encoding="utf-8"))
    resources: dict = json.loads((DATA_DIR / "resources" / "resources.json").read_text(encoding="utf-8"))
    provinces: dict = json.loads((DATA_DIR / "provinces" / "provinces.json").read_text(encoding="utf-8"))
    lookup = CountryLookup(countries, config["aliases"], config["dependency_owners"])
    pages = cfg["wikipedia_pages"]

    def tables(key: str) -> list[list[list[str]]]:
        return read_tables(fetch_page_as_of(pages[key], cfg["as_of"]))

    production: dict[str, dict[str, float]] = {}
    consumption: dict[str, dict[str, float]] = {}

    # Pétrole (barils/jour → millions de barils/jour).
    table = find_table(tables("oil_production"), ["Country", "bbl/day"])
    production["oil"] = {t: v / BARRELS_PER_MILLION for t, v in lookup.values_by_tag(table, 0, 1, "pétrole").items()}
    table = find_table(tables("oil_consumption"), ["Country", "consumption"])
    consumption["oil"] = {t: v / BARRELS_PER_MILLION for t, v in lookup.values_by_tag(table, 1, 2, "pétrole").items()}

    # Gaz (millions de m³ → milliards de m³) ; le tableau de consommation a son en-tête en deuxième ligne.
    table = find_table(tables("gas_production"), ["Country", "production"])
    production["gas"] = {t: v / CUBIC_METERS_PER_BILLION for t, v in
                         lookup.values_by_tag(table, 0, column(table, ["production"]), "gaz").items()}
    table = max(tables("gas_consumption"), key=len)
    consumption["gas"] = {t: v / CUBIC_METERS_PER_BILLION for t, v in
                          lookup.values_by_tag(table[1:], 0, 1, "gaz").items()}

    # Charbon (millions de tonnes, dernière année).
    table = find_table(tables("coal_production"), ["Country", "2023"])
    production["coal"] = lookup.values_by_tag(table, 0, 1, "charbon")

    # Uranium (tonnes) ; besoins des réacteurs selon la production nucléaire.
    uranium_tables = [t for t in tables("uranium_production") if t and "tonnes U" in " ".join(t[0])]
    latest = max(uranium_tables, key=lambda t: max(int(w) for h in t[0] for w in h.replace("(", " ").replace(")", " ").split() if w.isdigit() and len(w) == 4))
    production["uranium"] = lookup.values_by_tag(latest, 1, 2, "uranium")
    table = find_table(tables("nuclear"), ["Country", "Generation"])
    consumption["uranium"] = {t: v * cfg["uranium_per_gwh"] for t, v in
                              lookup.values_by_tag(table, 0, column(table, ["Generation"]), "nucléaire").items()}

    # Acier (millions de tonnes) ; consommation = production - exportations nettes.
    steel_tables = tables("steel")
    table = find_table(steel_tables, ["Country", "2024"])
    production["steel"] = lookup.values_by_tag(table, 0, 1, "acier")
    trade = find_table(steel_tables, ["Net exports"])
    net_exports = lookup.values_by_tag(trade, 0, column(trade, ["Net exports"]), "acier")
    net_imports = lookup.values_by_tag(trade, 0, column(trade, ["Net imports"]), "acier")

    # Blé (millions de tonnes ; le tableau est en tonnes ou en milliers selon les pages).
    table = find_table(tables("wheat"), ["Country", "2022"])
    wheat = lookup.values_by_tag(table, 0, 1, "blé")
    scale = 1.0e6 if max(wheat.values()) > 1.0e5 else 1.0
    production["wheat"] = {t: v / scale for t, v in wheat.items()}

    # Ressources saisies.
    for resource_id, values in cfg["production"].items():
        if resource_id != "comment":
            production[resource_id] = {t: float(v) for t, v in values.items()}

    # Consommations estimées, puis ramenées à la production mondiale.
    weights = industrial_weights(countries, economy)
    totals = {r: sum(production[r].values()) for r in production}
    consumption["coal"] = spread_shares(totals["coal"], cfg["consumption_shares"]["coal"], weights)
    for resource_id in ("rare_earths", "lithium", "cobalt", "semiconductors"):
        consumption[resource_id] = spread_shares(totals[resource_id], cfg["consumption_shares"][resource_id], weights)
    steel = {}
    for tag in countries:
        made = production["steel"].get(tag, 0.0)
        steel[tag] = max(made - net_exports.get(tag, 0.0) + net_imports.get(tag, 0.0), 0.0) if made > 0 else None
    known = {t: v for t, v in steel.items() if v is not None}
    unknown_total = max(totals["steel"] - sum(known.values()), 0.0)
    unknown_weights = {t: weights[t] for t, v in steel.items() if v is None}
    weight_sum = sum(unknown_weights.values())
    for tag, weight in unknown_weights.items():
        known[tag] = unknown_total * weight / weight_sum if weight_sum > 0 else 0.0
    consumption["steel"] = known
    wheat_cfg = cfg["wheat_per_capita"]
    consumption["wheat"] = {t: c["population"] * wheat_cfg["values"].get(t, wheat_cfg["default"]) / 1.0e6
                            for t, c in countries.items()}
    for resource_id in production:
        consumption[resource_id] = normalize(consumption.get(resource_id, {}), totals[resource_id])

    # Eau : ressources renouvelables (km³) et taux de prélèvement.
    water_table = find_table(tables("water"), ["Total renewable water"])
    renewable = lookup.values_by_tag(water_table, 0, column(water_table, ["Total renewable water resources (bln"]),
                                     "eau")
    withdrawal = lookup.values_by_tag(water_table, 0, column(water_table, ["Freshwater withdrawal"]), "eau")

    out: dict[str, dict] = {}
    for tag in sorted(countries):
        entry = {}
        for resource_id in production:
            made = round(production[resource_id].get(tag, 0.0), 4)
            used = round(consumption[resource_id].get(tag, 0.0), 4)
            if made > 0 or used > 0:
                entry[resource_id] = {"production": made, "consumption": used}
        out[tag] = {"resources": entry, "water": {"renewable": round(renewable.get(tag, 0.0), 2),
                                                 "withdrawal_ratio": round(withdrawal.get(tag, 0.0) / 100.0, 4)}}

    province_out = distribute(production, provinces, cfg, resources)
    write(DATA_DIR / "countries" / "resources.json", out)
    write(DATA_DIR / "provinces" / "resources.json", province_out)
    print(f"{len(out)} pays, {len(province_out)} provinces productrices.")
    for resource_id in production:
        top = sorted(production[resource_id].items(), key=lambda kv: -kv[1])[:4]
        print(f"  {resource_id}: total {totals[resource_id]:.1f} ; " + ", ".join(f"{t} {v:.1f}" for t, v in top))
    for label, names in lookup.unmatched.items():
        print(f"Lignes non reconnues ({label}) : {', '.join(sorted(set(names)))[:400]}")


def distribute(production: dict, provinces: dict, cfg: dict, resources: dict) -> dict[str, dict]:
    """Répartit la production nationale entre les provinces : régions saisies, sinon terrain et surface."""
    names = {}
    with open(DATA_DIR / "localization" / "provinces.csv", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            names[row["keys"]] = row["en"]
    by_owner: dict[str, list[tuple[str, dict]]] = {}
    for pid, province in provinces.items():
        by_owner.setdefault(province.get("owner", ""), []).append((pid, province))
    out: dict[str, dict] = {}
    missing: list[str] = []
    for resource_id, values in production.items():
        unit_value = resources[resource_id]["market"]["unit_value"]
        terrain_weights = cfg["province_terrain_weights"].get(resource_id, {})
        for tag, amount in values.items():
            owned = by_owner.get(tag, [])
            if amount <= 0 or not owned:
                continue
            shares: dict[str, float] = {}
            regions = cfg["regions"].get(tag, {}).get(resource_id, {})
            for region, share in regions.items():
                matches = [pid for pid, p in owned if region.lower() in names.get(p["name_key"], "").lower()]
                if not matches:
                    missing.append(f"{tag}/{region}")
                for pid in matches:
                    shares[pid] = shares.get(pid, 0.0) + share / len(matches)
            if not shares:
                basis = "population" if cfg["province_weight_basis"].get(resource_id) == "population" else "area_km2"
                weights = {pid: p.get(basis, 0.0) * terrain_weights.get(p.get("terrain", ""), 0.1)
                           for pid, p in owned}
                best = sorted(weights.items(), key=lambda kv: -kv[1])[:max(1, len(owned) // 4)]
                total = sum(w for _, w in best)
                shares = {pid: w / total for pid, w in best} if total > 0 else {owned[0][0]: 1.0}
            total_share = sum(shares.values())
            for pid, share in shares.items():
                value = amount * share / total_share * unit_value
                richness = max(1, min(MAX_RICHNESS, round(RICHNESS_SCALE * math.log(1.0 + value))))
                out.setdefault(pid, {"resources": {}})["resources"][resource_id] = richness
    if missing:
        print("Régions introuvables : " + ", ".join(missing))
    return dict(sorted(out.items(), key=lambda kv: int(kv[0])))


def write(path: Path, table: dict) -> None:
    lines = [f'  "{key}": {json.dumps(table[key], ensure_ascii=False, separators=(",", ": "))}' for key in table]
    path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()

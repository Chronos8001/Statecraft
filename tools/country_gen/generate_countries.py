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
import unicodedata
import urllib.request
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
CACHE_DIR = TOOL_DIR / "cache"
DATA_DIR = ROOT / "data"
ADMIN0_PATH = ROOT / "tools" / "map_gen" / "cache" / "ne_10m_admin_0_countries.geojson"
WIKIPEDIA_REST = "https://en.wikipedia.org/api/rest_v1/page/html/{page}"
USER_AGENT = "StatecraftCountryGen/1.0 (https://github.com/Chronos8001/Statecraft)"
MILLION = 1_000_000.0
THOUSAND = 1000.0
PERCENT = 100.0

sys.path.insert(0, str(TOOL_DIR))
from wiki_tables import parse_number, read_tables  # noqa: E402


def normalize(name: str) -> str:
    """Nom comparable : sans accents, notes, parenthèses, astérisques ni ponctuation."""
    name = name.split("[")[0].split("(")[0].replace("*", "")
    name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    name = "".join(c if c.isalnum() else " " for c in name.lower())
    words = [w for w in name.split() if w != "the"]
    return " ".join(words)


def fetch_page(page: str) -> str:
    path = CACHE_DIR / (page.replace("(", "").replace(")", "") + ".html")
    if not path.exists():
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(WIKIPEDIA_REST.format(page=page), headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=60) as response:
            path.write_bytes(response.read())
    return path.read_text(encoding="utf-8")


def find_table(tables: list[list[list[str]]], header_words: list[str]) -> list[list[str]]:
    """Plus grand tableau dont l'en-tête contient tous les mots demandés."""
    candidates = [t for t in tables if t and all(any(w.lower() in h.lower() for h in t[0]) for w in header_words)]
    if not candidates:
        raise SystemExit(f"Tableau introuvable : {header_words}")
    return max(candidates, key=len)


def column(table: list[list[str]], words: list[str]) -> int:
    for index, header in enumerate(table[0]):
        if all(w.lower() in header.lower() for w in words):
            return index
    raise SystemExit(f"Colonne introuvable : {words} dans {table[0]}")


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    countries_path = DATA_DIR / "countries" / "countries.json"
    countries: dict = json.loads(countries_path.read_text(encoding="utf-8"))
    admin0 = {f["properties"]["ADM0_A3"]: f["properties"]
              for f in json.loads(ADMIN0_PATH.read_text(encoding="utf-8"))["features"]}
    renames = {"SSD": "SDS", "PSE": "PSX"}

    # Noms reconnus pour chaque pays : Natural Earth + alias.
    # Les alias explicites passent avant les noms Natural Earth.
    lookup: dict[str, str] = {}
    for tag, aliases in config["aliases"].items():
        for name in aliases:
            lookup[normalize(name)] = tag
    for tag in countries:
        row = admin0.get(renames.get(tag, tag), {})
        for key in ("NAME", "NAME_LONG", "ADMIN", "FORMAL_EN", "NAME_EN", "BRK_NAME", "NAME_SORT", "GEOUNIT",
                    "SOVEREIGNT"):
            if row.get(key):
                lookup.setdefault(normalize(row[key]), tag)

    unmatched: dict[str, list[str]] = {}
    dependencies = {normalize(name): owner for name, owner in config["dependency_owners"].items()}
    ignored = {"world"}

    def values_by_tag(table: list[list[str]], name_col: int, value_col: int, label: str,
                      add_dependencies: bool = False) -> dict[str, float]:
        """Valeur par pays ; les territoires rattachés (Hong Kong, Groenland…) s'ajoutent à leur pays si demandé."""
        result: dict[str, float] = {}
        extra: dict[str, float] = {}
        for row in table[1:]:
            if len(row) <= max(name_col, value_col):
                continue
            name = normalize(row[name_col])
            tag = lookup.get(name)
            value = parse_number(row[value_col])
            if value is None:
                continue
            if tag is None:
                if name in dependencies:
                    extra[dependencies[name]] = extra.get(dependencies[name], 0.0) + value
                elif name not in ignored:
                    unmatched.setdefault(label, []).append(row[name_col])
                continue
            if tag not in result:
                result[tag] = value
        if add_dependencies:
            for tag, value in extra.items():
                if tag in result:
                    result[tag] += value
        return result

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
        row = admin0.get(renames.get(tag, tag), {})
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

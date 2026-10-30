"""Outils communs aux générateurs de données des pays : pages Wikipédia, noms de pays → codes."""

from __future__ import annotations

import json
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

from wiki_tables import parse_number

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
CACHE_DIR = TOOL_DIR / "cache"
ADMIN0_PATH = ROOT / "tools" / "map_gen" / "cache" / "ne_10m_admin_0_countries.geojson"
WIKIPEDIA_REST = "https://en.wikipedia.org/api/rest_v1/page/html/{page}"
WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
USER_AGENT = "StatecraftCountryGen/1.0 (https://github.com/Chronos8001/Statecraft)"
RETRIES = 4
RETRY_SECONDS = 5
# Codes Natural Earth différents des codes du jeu.
NATURAL_EARTH_RENAMES = {"SSD": "SDS", "PSE": "PSX"}
IGNORED_NAMES = {"world"}


def normalize(name: str) -> str:
    """Nom comparable : sans accents, notes, parenthèses, astérisques ni ponctuation."""
    name = name.split("[")[0].split("(")[0].replace("*", "")
    name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    name = "".join(c if c.isalnum() else " " for c in name.lower())
    words = [w for w in name.split() if w != "the"]
    return " ".join(words)


def download(url: str) -> bytes:
    for attempt in range(RETRIES):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=90) as response:
                return response.read()
        except OSError:
            if attempt == RETRIES - 1:
                raise
            time.sleep(RETRY_SECONDS)
    raise RuntimeError(url)


def fetch_page(page: str) -> str:
    """Version actuelle d'une page Wikipédia (mise en cache)."""
    path = CACHE_DIR / (page.replace("(", "").replace(")", "") + ".html")
    if not path.exists():
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        path.write_bytes(download(WIKIPEDIA_REST.format(page=page)))
    return path.read_text(encoding="utf-8")


def fetch_page_as_of(page: str, timestamp: str) -> str:
    """Version d'une page Wikipédia telle qu'elle était à une date (ex. « 2026-01-01T00:00:00Z »)."""
    stamp = timestamp[:10]
    path = CACHE_DIR / f"{page.replace('(', '').replace(')', '')}@{stamp}.html"
    if not path.exists():
        query = urllib.parse.urlencode({
            "action": "query", "prop": "revisions", "titles": page.replace("_", " "), "rvlimit": 1,
            "rvstart": timestamp, "rvdir": "older", "rvprop": "ids", "format": "json", "redirects": 1,
        })
        pages = json.loads(download(f"{WIKIPEDIA_API}?{query}"))["query"]["pages"]
        entry = next(iter(pages.values()))
        if "revisions" not in entry:
            raise SystemExit(f"Page introuvable : {page}")
        title = urllib.parse.quote(entry["title"].replace(" ", "_"))
        revision = entry["revisions"][0]["revid"]
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        path.write_bytes(download(f"{WIKIPEDIA_REST.format(page=title)}/{revision}"))
    return path.read_text(encoding="utf-8")


def find_table(tables: list[list[list[str]]], header_words: list[str]) -> list[list[str]]:
    """Plus grand tableau dont l'en-tête contient tous les mots demandés."""
    candidates = [t for t in tables if t and all(any(w.lower() in h.lower() for h in t[0]) for w in header_words)]
    if not candidates:
        raise SystemExit(f"Tableau introuvable : {header_words}")
    return max(candidates, key=len)


def column(table: list[list[str]], words: list[str], occurrence: int = 0) -> int:
    """Indice de la n-ième colonne dont l'en-tête contient tous les mots demandés."""
    found = [i for i, header in enumerate(table[0]) if all(w.lower() in header.lower() for w in words)]
    if len(found) <= occurrence:
        raise SystemExit(f"Colonne introuvable : {words} dans {table[0]}")
    return found[occurrence]


class CountryLookup:
    """Retrouve le code d'un pays à partir des noms utilisés par Wikipédia."""

    def __init__(self, countries: dict, aliases: dict, dependency_owners: dict) -> None:
        self.admin0 = {f["properties"]["ADM0_A3"]: f["properties"]
                       for f in json.loads(ADMIN0_PATH.read_text(encoding="utf-8"))["features"]}
        self.names: dict[str, str] = {}
        # Les alias explicites passent avant les noms Natural Earth.
        for tag, names in aliases.items():
            for name in names:
                self.names[normalize(name)] = tag
        for tag in countries:
            row = self.natural_earth(tag)
            for key in ("NAME", "NAME_LONG", "ADMIN", "FORMAL_EN", "NAME_EN", "BRK_NAME", "NAME_SORT", "GEOUNIT",
                        "SOVEREIGNT"):
                if row.get(key):
                    self.names.setdefault(normalize(row[key]), tag)
        self.dependencies = {normalize(name): owner for name, owner in dependency_owners.items()}
        self.unmatched: dict[str, list[str]] = {}

    def natural_earth(self, tag: str) -> dict:
        return self.admin0.get(NATURAL_EARTH_RENAMES.get(tag, tag), {})

    def tag_of(self, name: str) -> str | None:
        return self.names.get(normalize(name))

    def values_by_tag(self, table: list[list[str]], name_col: int, value_col: int, label: str,
                      add_dependencies: bool = False, extra_names: dict[str, str] | None = None) -> dict[str, float]:
        """Valeur par pays ; les territoires rattachés (Hong Kong, Groenland…) s'ajoutent à leur pays si demandé.
        extra_names : noms propres à ce tableau (unions monétaires…) → clé du résultat."""
        result: dict[str, float] = {}
        extra: dict[str, float] = {}
        specials = {normalize(k): v for k, v in (extra_names or {}).items()}
        for row in table[1:]:
            if len(row) <= max(name_col, value_col):
                continue
            name = normalize(row[name_col])
            tag = specials.get(name) or self.names.get(name)
            value = parse_number(row[value_col])
            if value is None:
                continue
            if tag is None:
                if name in self.dependencies:
                    owner = self.dependencies[name]
                    extra[owner] = extra.get(owner, 0.0) + value
                elif name not in IGNORED_NAMES:
                    self.unmatched.setdefault(label, []).append(row[name_col])
                continue
            if tag not in result:
                result[tag] = value
        if add_dependencies:
            for tag, value in extra.items():
                if tag in result:
                    result[tag] += value
        return result

    def text_by_tag(self, table: list[list[str]], name_col: int, value_col: int, label: str) -> dict[str, str]:
        """Texte brut par pays (notes de crédit…) ; les lignes marquées « withdrawn » sont ignorées."""
        result: dict[str, str] = {}
        for row in table[1:]:
            if len(row) <= max(name_col, value_col):
                continue
            if any("withdrawn" in cell.lower() for cell in row):
                continue
            tag = self.names.get(normalize(row[name_col]))
            if tag is None:
                if normalize(row[name_col]) not in IGNORED_NAMES | set(self.dependencies):
                    self.unmatched.setdefault(label, []).append(row[name_col])
                continue
            result.setdefault(tag, row[value_col].split("[")[0].strip())
        return result

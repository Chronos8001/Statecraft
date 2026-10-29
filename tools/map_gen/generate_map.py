"""Génère la carte des provinces de Statecraft à partir des données Natural Earth.

Sorties :
  data/map/provinces.png             image des provinces (couleur = identifiant : R + G * 256)
  data/map/map.json                  métadonnées de la carte
  data/provinces/provinces.json      provinces (propriétaire, terrain, population, voisins…)
  data/countries/countries.json      pays : les entrées existantes sont conservées, seule la
                                     capitale est recalculée ; les pays manquants sont ajoutés
  data/localization/provinces.csv    noms des provinces (en, fr)
  data/localization/countries.csv    noms des pays (en, fr)
  tools/map_gen/out/preview_*.png    aperçus (non versionnés)

Usage : python tools/map_gen/generate_map.py
"""

from __future__ import annotations

import csv
import json
import math
import urllib.parse
import urllib.request
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
CACHE_DIR = TOOL_DIR / "cache"
OUT_DIR = TOOL_DIR / "out"
DATA_DIR = ROOT / "data"

NE_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/{version}/geojson/{name}.geojson"
LAYERS = {
    "admin1": "ne_10m_admin_1_states_provinces",
    "admin0": "ne_10m_admin_0_countries",
    "places": "ne_10m_populated_places",
    "lakes": "ne_10m_lakes",
    "regions": "ne_10m_geography_regions_polys",
}
EARTH_CIRCUMFERENCE_KM = 40075.0
MERIDIAN_LENGTH_KM = 20004.0
ROW_CHUNK = 512


# --------------------------------------------------------------------------- données sources

def load_layer(name: str, version: str) -> list[dict]:
    path = CACHE_DIR / f"{LAYERS[name]}.geojson"
    if not path.exists():
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        url = NE_URL.format(version=version, name=LAYERS[name])
        print(f"Téléchargement de {url}")
        urllib.request.urlretrieve(url, path)
    with path.open(encoding="utf-8") as file:
        return json.load(file)["features"]


def polygons_of(geometry: dict) -> list[list[list[list[float]]]]:
    if geometry is None:
        return []
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    return []


WIKIDATA_SPARQL = "https://query.wikidata.org/sparql"
WIKIDATA_BATCH = 300
WIKIDATA_USER_AGENT = "StatecraftMapGen/1.0 (https://github.com/Chronos8001/Statecraft)"


def wikidata_populations(qids: set[str]) -> dict[str, float]:
    """Population la plus récente (propriété P1082) de chaque élément Wikidata, mise en cache."""
    cache_path = CACHE_DIR / "wikidata_population.json"
    cache: dict[str, float | None] = {}
    if cache_path.exists():
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
    missing = sorted(q for q in qids if q not in cache)
    for start in range(0, len(missing), WIKIDATA_BATCH):
        batch = missing[start:start + WIKIDATA_BATCH]
        print(f"Wikidata : populations {start + 1}-{start + len(batch)} / {len(missing)}")
        query = ("SELECT ?item ?pop ?date WHERE { VALUES ?item { " + " ".join(f"wd:{q}" for q in batch)
                 + " } ?item p:P1082 ?statement . ?statement ps:P1082 ?pop . "
                 + "OPTIONAL { ?statement pq:P585 ?date } }")
        request = urllib.request.Request(
            WIKIDATA_SPARQL + "?" + urllib.parse.urlencode({"query": query, "format": "json"}),
            headers={"User-Agent": WIKIDATA_USER_AGENT, "Accept": "application/sparql-results+json"})
        with urllib.request.urlopen(request, timeout=120) as response:
            results = json.load(response)["results"]["bindings"]
        best: dict[str, tuple[str, float]] = {}
        for row in results:
            qid = row["item"]["value"].rsplit("/", 1)[-1]
            date = row.get("date", {}).get("value", "")
            value = float(row["pop"]["value"])
            if qid not in best or date > best[qid][0]:
                best[qid] = (date, value)
        for qid in batch:
            cache[qid] = best[qid][1] if qid in best else None
        cache_path.write_text(json.dumps(cache), encoding="utf-8")
    return {q: v for q, v in cache.items() if q in qids and v}


# --------------------------------------------------------------------------- projection et dessin

class Projection:
    """Projection équirectangulaire : longitude -180..180 → x 0..W, latitude 90..-90 → y 0..H."""

    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height

    def ring(self, ring: list[list[float]]) -> np.ndarray:
        coords = np.asarray(ring, dtype=np.float64)[:, :2]
        x = (coords[:, 0] + 180.0) / 360.0 * self.width
        y = (90.0 - coords[:, 1]) / 180.0 * self.height
        return np.column_stack((x, y))

    def point(self, lon: float, lat: float) -> tuple[int, int]:
        x = int((lon + 180.0) / 360.0 * self.width) % self.width
        y = min(max(int((90.0 - lat) / 180.0 * self.height), 0), self.height - 1)
        return x, y

    def latitude(self, y: float) -> float:
        return 90.0 - y / self.height * 180.0


def ring_area(points: np.ndarray) -> float:
    x, y = points[:, 0], points[:, 1]
    return abs(float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))) / 2.0


def rasterize(items: list[tuple[int, list]], projection: Projection, mode: str, scale: int = 1) -> np.ndarray:
    """Dessine des polygones (valeur, géométrie). Chaque partie est dessinée de la plus grande à la
    plus petite, ses trous effacés juste après : une enclave est toujours dessinée après son contenant."""
    size = (projection.width // scale, projection.height // scale)
    image = Image.new(mode, size, 0)
    draw = ImageDraw.Draw(image)
    parts = []
    for value, geometry in items:
        for polygon in polygons_of(geometry):
            rings = [projection.ring(ring) / scale for ring in polygon]
            if len(rings[0]) >= 3:
                parts.append((ring_area(rings[0]), value, rings))
    parts.sort(key=lambda part: -part[0])
    for _, value, rings in parts:
        draw.polygon(rings[0].ravel().tolist(), fill=value)
        for hole in rings[1:]:
            if len(hole) >= 3:
                draw.polygon(hole.ravel().tolist(), fill=0)
    return np.asarray(image)


# --------------------------------------------------------------------------- pays et propriétaires

def resolve_unit_owners(admin0: list[dict], config: dict) -> dict[str, str | None]:
    """Associe chaque unité Natural Earth (ADM0_A3) au tag du pays qui la possède."""
    rows = {feature["properties"]["ADM0_A3"]: feature["properties"] for feature in admin0}
    main_by_sovereignty: dict[str, str] = {}
    for tag, row in rows.items():
        if row["HOMEPART"] == 1 and row["TYPE"] != "Indeterminate":
            main_by_sovereignty.setdefault(row["SOV_A3"], tag)
    owners: dict[str, str | None] = {}
    for tag, row in rows.items():
        if tag in config["unowned_units"]:
            owners[tag] = None
        elif tag in config["unit_owners"]:
            owners[tag] = config["unit_owners"][tag]
        elif row["TYPE"] == "Sovereign country" or row["HOMEPART"] == 1:
            owners[tag] = tag
        else:
            owners[tag] = main_by_sovereignty.get(row["SOV_A3"], tag)
    renames = config["tag_renames"]
    return {unit: (renames.get(owner, owner) if owner else None) for unit, owner in owners.items()}


def country_color(index: int, tag: str, config: dict, used: set[str]) -> str:
    """Couleur de la palette (les voisins ont des indices différents), éclaircie ou assombrie selon
    le tag, et toujours unique."""
    palette = config["political_palette"]
    base = palette[(index - 1) % len(palette)].lstrip("#")
    rgb = [int(base[i:i + 2], 16) for i in (0, 2, 4)]
    seed = zlib.crc32(tag.encode())
    while True:
        shift = ((seed % 1000) / 1000.0 - 0.5) * 2.0 * config["political_variation"]
        colour = "#{:02X}{:02X}{:02X}".format(*[min(255, max(0, round(c * (1.0 + shift)))) for c in rgb])
        if colour not in used:
            used.add(colour)
            return colour
        seed = zlib.crc32(colour.encode(), seed)


def id_to_color(province_id: int) -> str:
    return "#{:02X}{:02X}00".format(province_id & 0xFF, (province_id >> 8) & 0xFF)


# --------------------------------------------------------------------------- génération

def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    version = config["natural_earth_version"]
    width, height = config["width"], config["height"]
    projection = Projection(width, height)

    admin1 = load_layer("admin1", version)
    admin0 = load_layer("admin0", version)
    places = load_layer("places", version)
    lakes = load_layer("lakes", version)
    regions = load_layer("regions", version)

    unit_rows = {feature["properties"]["ADM0_A3"]: feature["properties"] for feature in admin0}
    unit_owner = resolve_unit_owners(admin0, config)

    # Identifiants stables : triés par code Natural Earth.
    admin1.sort(key=lambda feature: feature["properties"]["adm1_code"])
    province_count = len(admin1)
    sources = [feature["properties"] for feature in admin1]
    print(f"{province_count} provinces terrestres")

    # 1. Image des provinces.
    print("Dessin des provinces…")
    ids = rasterize([(i + 1, f["geometry"]) for i, f in enumerate(admin1)], projection, "I").astype(np.int32)
    print("Dessin du masque des terres…")
    land = rasterize([(1, f["geometry"]) for f in admin0], projection, "L").astype(bool)

    # 2. Bouche les interstices de quelques pixels entre provinces voisines.
    for _ in range(config["gap_fill_passes"]):
        for axis, shift in ((1, 1), (1, -1), (0, 1), (0, -1)):
            gaps = (ids == 0) & land
            if not gaps.any():
                break
            neighbour = np.roll(ids, shift, axis=axis)
            fill = gaps & (neighbour > 0)
            ids[fill] = neighbour[fill]

    # 3. Grands lacs : eau intérieure.
    big_lakes = [(1, f["geometry"]) for f in lakes if f["properties"]["scalerank"] <= config["max_lake_scalerank"]]
    lake_mask = rasterize(big_lakes, projection, "L").astype(bool)
    ids[lake_mask] = 0

    # 4. Provinces trop petites (micro-États, îlots) : disque minimal autour de leur point d'étiquette.
    # Un pixel déjà attribué à une autre micro-province n'est jamais repris ; si tout le disque est pris,
    # on cherche le pixel libre le plus proche en spirale.
    counts = np.bincount(ids.ravel(), minlength=province_count + 1)
    radius = config["micro_province_radius"]
    small = [i + 1 for i in range(province_count) if counts[i + 1] < config["min_province_pixels"]]
    small.sort(key=lambda p: counts[p])
    protected: set[tuple[int, int]] = set()
    offsets = sorted(((dx, dy) for dx in range(-radius, radius + 1) for dy in range(-radius, radius + 1)
                      if dx * dx + dy * dy <= radius * radius + 1), key=lambda o: o[0] ** 2 + o[1] ** 2)
    search = sorted(((dx, dy) for dx in range(-12, 13) for dy in range(-12, 13)), key=lambda o: o[0] ** 2 + o[1] ** 2)
    for province_id in small:
        source = sources[province_id - 1]
        cx, cy = projection.point(source["longitude"], source["latitude"])
        placed = 0
        for dx, dy in offsets:
            pixel = (min(max(cy + dy, 0), height - 1), (cx + dx) % width)
            if pixel not in protected:
                ids[pixel] = province_id
                land[pixel] = True
                protected.add(pixel)
                placed += 1
        if placed == 0:
            for dx, dy in search:
                pixel = (min(max(cy + dy, 0), height - 1), (cx + dx) % width)
                if pixel not in protected:
                    ids[pixel] = province_id
                    land[pixel] = True
                    protected.add(pixel)
                    break
    print(f"{len(small)} provinces agrandies à la taille minimale")

    # 5. Statistiques par province, par bandes de lignes : taille, centre, surface, voisins, côtes.
    print("Analyse des pixels…")
    n = province_count + 1
    count = np.zeros(n)
    sum_cos = np.zeros(n)
    sum_sin = np.zeros(n)
    sum_y = np.zeros(n)
    sum_area = np.zeros(n)
    coastal = np.zeros(n, dtype=bool)
    pair_keys: list[np.ndarray] = []
    angles = 2.0 * math.pi * (np.arange(width) + 0.5) / width
    cos_x, sin_x = np.cos(angles), np.sin(angles)
    pixel_km2 = (EARTH_CIRCUMFERENCE_KM / width) * (MERIDIAN_LENGTH_KM / height)
    ocean = ~land

    def add_pairs(a: np.ndarray, b: np.ndarray) -> None:
        mask = (a != b) & (a > 0) & (b > 0)
        low, high = np.minimum(a[mask], b[mask]), np.maximum(a[mask], b[mask])
        pair_keys.append(np.unique(low.astype(np.int64) * 65536 + high))

    for y0 in range(0, height, ROW_CHUNK):
        y1 = min(y0 + ROW_CHUNK, height)
        block = ids[y0:y1]
        rows = block.shape[0]
        flat = block.ravel()
        row_centres = np.arange(y0, y1) + 0.5
        latitudes = np.radians(90.0 - row_centres / height * 180.0)
        count += np.bincount(flat, minlength=n)
        sum_cos += np.bincount(flat, weights=np.tile(cos_x, rows), minlength=n)
        sum_sin += np.bincount(flat, weights=np.tile(sin_x, rows), minlength=n)
        sum_y += np.bincount(flat, weights=np.repeat(row_centres, width), minlength=n)
        sum_area += np.bincount(flat, weights=np.repeat(np.cos(latitudes) * pixel_km2, width), minlength=n)
        # Voisins horizontaux (avec bouclage est-ouest) et verticaux.
        right = np.roll(block, -1, axis=1)
        add_pairs(block, right)
        below_end = min(y1 + 1, height)
        extended = ids[y0:below_end]
        add_pairs(extended[:-1], extended[1:])
        # Côtes : pixel de province touchant un pixel d'océan.
        ocean_block = ocean[y0:below_end]
        for neighbour_ocean, own in (
            (np.roll(ocean[y0:y1], -1, axis=1), block),
            (np.roll(ocean[y0:y1], 1, axis=1), block),
            (ocean_block[1:], extended[:-1]),
            (ocean_block[:-1], extended[1:]),
        ):
            coastal[np.unique(own[neighbour_ocean & (own > 0)])] = True

    pairs = np.unique(np.concatenate(pair_keys)) if pair_keys else np.array([], dtype=np.int64)
    neighbours: list[set[int]] = [set() for _ in range(n)]
    for key in pairs.tolist():
        a, b = divmod(key, 65536)
        neighbours[a].add(b)
        neighbours[b].add(a)

    safe_count = np.maximum(count, 1)
    centre_x = (np.arctan2(sum_sin, sum_cos) / (2.0 * math.pi) * width) % width
    centre_y = sum_y / safe_count

    # 6. Terrain : régions géographiques Natural Earth, puis climat selon la latitude.
    print("Terrain…")
    terrain_names = sorted({terrain for _, terrain in config["terrain_regions"]})
    class_index = {name: i + 1 for i, name in enumerate(terrain_names)}
    priority = {feature_class: rank for rank, (feature_class, _) in enumerate(config["terrain_regions"])}
    region_items = []
    for feature in regions:
        feature_class = feature["properties"]["FEATURECLA"]
        if feature_class in priority:
            terrain = dict(config["terrain_regions"])[feature_class]
            region_items.append((priority[feature_class], class_index[terrain], feature["geometry"]))
    region_items.sort(key=lambda item: item[0])
    scale = config["terrain_downscale"]
    terrain_map = np.zeros((height // scale, width // scale), dtype=np.uint8)
    for _, value, geometry in region_items:  # du moins précis au plus précis
        layer = rasterize([(value, geometry)], projection, "L", scale)
        terrain_map[layer > 0] = value
    small_ids = ids[::scale, ::scale][: terrain_map.shape[0], : terrain_map.shape[1]]
    classes = len(terrain_names) + 1
    histogram = np.bincount(small_ids.ravel().astype(np.int64) * classes + terrain_map.ravel(),
                            minlength=n * classes).reshape(n, classes)
    climate = config["climate_latitudes"]

    def terrain_for(province_id: int) -> str:
        row = histogram[province_id]
        total = row.sum()
        if total > 0 and row[1:].max() / total >= config["terrain_min_share"]:
            return terrain_names[int(row[1:].argmax())]
        latitude = abs(projection.latitude(centre_y[province_id]))
        if latitude >= climate["tundra"]:
            return "tundra"
        if latitude >= climate["forest"]:
            return "forest"
        if latitude <= climate["jungle"]:
            return "jungle"
        if latitude <= climate["savanna"]:
            return "savanna"
        return "plains"

    terrain = ["" for _ in range(n)]
    for province_id in range(1, n):
        terrain[province_id] = terrain_for(province_id)

    # 7. Population : population de chaque unité Natural Earth répartie entre villes et campagnes.
    print("Population…")
    city_population = np.zeros(n)
    for feature in places:
        props = feature["properties"]
        x, y = projection.point(props["LONGITUDE"], props["LATITUDE"])
        province_id = int(ids[y, x])
        if province_id == 0:
            window = ids[max(y - 3, 0): y + 4, max(x - 3, 0): x + 4]
            found = window[window > 0]
            province_id = int(found[0]) if found.size else 0
        if province_id:
            pop_max, pop_min = max(props["POP_MAX"] or 0, 0), max(props["POP_MIN"] or 0, 0)
            city_population[province_id] += min(pop_max, max(pop_min, config["city_core_share"] * pop_max))

    existing_countries = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    factors = config["terrain_population_factor"]
    population = np.zeros(n)
    provinces_by_unit: dict[str, list[int]] = {}
    for index, source in enumerate(sources):
        provinces_by_unit.setdefault(source["adm0_a3"], []).append(index + 1)
    for unit, members in provinces_by_unit.items():
        unit_population = max(unit_rows.get(unit, {}).get("POP_EST") or 0, 0) * config["population_scale"]
        rural = np.array([sum_area[p] * factors[terrain[p]] for p in members])
        cities = np.array([city_population[p] for p in members])
        rural_share = rural / rural.sum() if rural.sum() > 0 else np.full(len(members), 1.0 / len(members))
        if cities.sum() > 0:
            city_share = config["population_city_share"]
            share = city_share * cities / cities.sum() + (1.0 - city_share) * rural_share
        else:
            share = rural_share
        for province_id, value in zip(members, share):
            population[province_id] = unit_population * value

    # 8. Propriétaires et contrôleurs.
    owner: list[str | None] = [None] * n
    controller: list[str | None] = [None] * n
    for index, source in enumerate(sources):
        province_id = index + 1
        unit = source["adm0_a3"]
        owner[province_id] = unit_owner.get(unit)
        controller[province_id] = config["unit_controllers"].get(unit, owner[province_id])
        override = config["province_overrides"].get(source["adm1_code"], {})
        if "owner" in override:
            owner[province_id] = override["owner"]
            controller[province_id] = override["owner"]
        if "controller" in override:
            controller[province_id] = override["controller"]

    # Population réelle (Wikipédia / Wikidata) quand elle existe, estimation sinon ; puis chaque pays
    # est ramené à son total : celui de countries.json s'il est renseigné, sinon celui de Wikidata.
    renames = config["tag_renames"]
    tag_to_unit = {renames.get(unit, unit): unit for unit in unit_rows}
    province_qids = {p: sources[p - 1].get("wikidataid") for p in range(1, n)}
    country_qids = {tag: unit_rows.get(tag_to_unit.get(tag, tag), {}).get("WIKIDATAID")
                    for tag in {t for t in owner[1:] if t}}
    known = wikidata_populations({q for q in list(province_qids.values()) + list(country_qids.values()) if q})
    from_wikidata = 0
    for p in range(1, n):
        value = known.get(province_qids[p] or "")
        if value:
            population[p] = value
            from_wikidata += 1
    print(f"{from_wikidata} / {n - 1} populations de provinces issues de Wikidata")
    for tag, qid in country_qids.items():
        target = existing_countries.get(tag, {}).get("population") or known.get(qid or "")
        members = [p for p in range(1, n) if owner[p] == tag]
        total = sum(population[p] for p in members)
        if target and total > 0:
            for p in members:
                population[p] *= target / total

    density = population / np.maximum(sum_area, 1.0)
    for province_id in range(1, n):
        if density[province_id] >= config["urban_density_km2"]:
            terrain[province_id] = "urban"

    # 9. Pays : entrées existantes conservées, capitales recalculées, pays manquants ajoutés.
    print("Pays…")
    owner_tags = sorted({tag for tag in owner[1:] if tag} | {tag for tag in controller[1:] if tag})
    capitals_by_unit: dict[str, list[dict]] = {}
    for feature in places:
        props = feature["properties"]
        if props["FEATURECLA"] == "Admin-0 capital":
            capitals_by_unit.setdefault(props["ADM0_A3"], []).append(props)

    def find_capital(tag: str) -> int:
        owned = [p for p in range(1, n) if owner[p] == tag]
        candidates = sorted(capitals_by_unit.get(tag_to_unit.get(tag, tag), []), key=lambda c: -(c["POP_MAX"] or 0))
        for capital in candidates:
            x, y = projection.point(capital["LONGITUDE"], capital["LATITUDE"])
            if owner[int(ids[y, x])] == tag:
                return int(ids[y, x])
            nearest = min(owned, key=lambda p: (min(abs(centre_x[p] - x), width - abs(centre_x[p] - x))) ** 2
                          + (centre_y[p] - y) ** 2)
            return nearest
        return max(owned, key=lambda p: population[p])

    countries: dict[str, dict] = {}
    used_colours = {str(c["color"]).upper() for c in existing_countries.values() if "color" in c}
    for tag in owner_tags:
        unit = tag_to_unit.get(tag, tag)
        row = unit_rows.get(unit, {})
        entry = dict(existing_countries.get(tag, {}))
        entry.setdefault("name_key", f"COUNTRY_{tag}")
        if "color" not in entry:
            entry["color"] = country_color(int(row.get("MAPCOLOR9") or 1), tag, config, used_colours)
        entry["capital"] = find_capital(tag) if any(owner[p] == tag for p in range(1, n)) else entry.get("capital")
        if entry["capital"] is None:
            raise SystemExit(f"Pays sans province ni capitale : {tag}")
        countries[tag] = entry

    # 10. Écriture des fichiers.
    print("Écriture…")
    income = config["income_infrastructure"]
    provinces_out: list[str] = []
    for index, source in enumerate(sources):
        province_id = index + 1
        unit_row = unit_rows.get(source["adm0_a3"], {})
        infrastructure = income.get(unit_row.get("INCOME_GRP"), config["default_infrastructure"])
        if terrain[province_id] == "urban":
            infrastructure += config["urban_infrastructure_bonus"]
        entry: dict = {"name_key": f"PROV_{province_id}", "color": id_to_color(province_id)}
        if owner[province_id]:
            entry["owner"] = owner[province_id]
            entry["controller"] = controller[province_id]
        entry.update({
            "terrain": terrain[province_id],
            "population": int(round(population[province_id])),
            "resources": {},
            "infrastructure": int(min(max(infrastructure, 0), 10)),
            "coastal": bool(coastal[province_id]),
            "area_km2": round(float(sum_area[province_id]), 1),
            "size": int(count[province_id]),
            "center": [round(float(centre_x[province_id]), 1), round(float(centre_y[province_id]), 1)],
            "neighbors": sorted(neighbours[province_id]),
            "source_id": source["adm1_code"],
        })
        provinces_out.append(f'  "{province_id}": {json.dumps(entry, ensure_ascii=False, separators=(",", ": "))}')
    (DATA_DIR / "provinces").mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "provinces" / "provinces.json").write_text(
        "{\n" + ",\n".join(provinces_out) + "\n}\n", encoding="utf-8", newline="\n")

    with (DATA_DIR / "countries" / "countries.json").open("w", encoding="utf-8", newline="\n") as file:
        file.write("{\n")
        lines = [f'  "{tag}": {json.dumps(entry, ensure_ascii=False, separators=(",", ": "))}'
                 for tag, entry in countries.items()]
        file.write(",\n".join(lines) + "\n}\n")

    (DATA_DIR / "map").mkdir(parents=True, exist_ok=True)
    rgb = np.zeros((height, width, 3), dtype=np.uint8)
    rgb[..., 0] = (ids & 0xFF).astype(np.uint8)
    rgb[..., 1] = ((ids >> 8) & 0xFF).astype(np.uint8)
    Image.fromarray(rgb, "RGB").save(DATA_DIR / "map" / "provinces.png", optimize=False, compress_level=9)
    map_info = {
        "map": {
            "width": width,
            "height": height,
            "projection": "equirectangular",
            "provinces_image": "res://data/map/provinces.png",
            "province_count": province_count,
            "source": f"Natural Earth {version} (domaine public)",
        }
    }
    (DATA_DIR / "map" / "map.json").write_text(json.dumps(map_info, ensure_ascii=False, indent=2) + "\n",
                                                encoding="utf-8", newline="\n")

    def write_csv(path: Path, rows: list[tuple[str, str, str]]) -> None:
        with path.open("w", encoding="utf-8", newline="") as file:
            writer = csv.writer(file, lineterminator="\n")
            writer.writerow(["keys", "en", "fr"])
            writer.writerows(rows)

    province_names = config["province_name_overrides"]
    province_rows = []
    for i, s in enumerate(sources):
        unit_row = unit_rows.get(s["adm0_a3"], {})
        fallback_en = s["name_en"] or s["name"] or unit_row.get("NAME_EN") or s["admin"]
        fallback_fr = s["name_fr"] or unit_row.get("NAME_FR") or fallback_en
        names = province_names.get(s["adm1_code"], {"en": fallback_en, "fr": fallback_fr})
        province_rows.append((f"PROV_{i + 1}", names["en"], names["fr"]))
    write_csv(DATA_DIR / "localization" / "provinces.csv", province_rows)
    name_overrides = config["country_name_overrides"]
    country_rows = []
    for tag in countries:
        row = unit_rows.get(tag_to_unit.get(tag, tag), {})
        names = name_overrides.get(tag, {"en": row.get("NAME_EN") or row.get("NAME") or tag,
                                         "fr": row.get("NAME_FR") or row.get("NAME_EN") or tag})
        country_rows.append((f"COUNTRY_{tag}", names["en"], names["fr"]))
    write_csv(DATA_DIR / "localization" / "countries.csv", country_rows)

    # Aperçu politique (non versionné).
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    lut = np.zeros((n, 3), dtype=np.uint8)
    lut[0] = (40, 70, 110)
    for province_id in range(1, n):
        tag = owner[province_id]
        colour = countries[tag]["color"] if tag else "#B0B0B0"
        lut[province_id] = [int(colour[i:i + 2], 16) for i in (1, 3, 5)]
    preview = lut[ids[::4, ::4]]
    Image.fromarray(preview, "RGB").save(OUT_DIR / "preview_political.png")
    unowned = sum(1 for p in range(1, n) if not owner[p])
    print(f"Terminé : {province_count} provinces, {len(countries)} pays, {unowned} provinces sans propriétaire.")


if __name__ == "__main__":
    main()

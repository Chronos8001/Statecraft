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
    "marine": "ne_10m_geography_marine_polys",
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


# --------------------------------------------------------------------------- zones maritimes

def pixel_vectors(xs: np.ndarray, ys: np.ndarray, projection: Projection) -> np.ndarray:
    """Vecteurs unitaires 3D des centres de pixels (calculs sur la sphère, sans souci de bouclage)."""
    lon = np.radians((xs + 0.5) / projection.width * 360.0 - 180.0)
    lat = np.radians(90.0 - (ys + 0.5) / projection.height * 180.0)
    return np.column_stack((np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat))).astype(np.float32)


def zone_areas(labels: np.ndarray, count: int, projection: Projection) -> np.ndarray:
    pixel_km2 = (EARTH_CIRCUMFERENCE_KM / projection.width) * (MERIDIAN_LENGTH_KM / projection.height)
    areas = np.zeros(count)
    for y0 in range(0, projection.height, ROW_CHUNK):
        y1 = min(y0 + ROW_CHUNK, projection.height)
        weights = np.cos(np.radians(90.0 - (np.arange(y0, y1) + 0.5) / projection.height * 180.0)) * pixel_km2
        areas += np.bincount(labels[y0:y1].ravel(), weights=np.repeat(weights, projection.width), minlength=count)
    return areas


def zone_adjacency(labels: np.ndarray) -> dict[tuple[int, int], int]:
    """Longueur de frontière commune (en pixels) entre étiquettes non nulles."""
    counts: dict[tuple[int, int], int] = {}
    height = labels.shape[0]
    for y0 in range(0, height, ROW_CHUNK):
        y1 = min(y0 + ROW_CHUNK, height)
        block = labels[y0:min(y1 + 1, height)]
        for a, b in ((labels[y0:y1], np.roll(labels[y0:y1], -1, axis=1)), (block[:-1], block[1:])):
            mask = (a != b) & (a > 0) & (b > 0)
            keys = np.minimum(a[mask], b[mask]).astype(np.int64) * 1_000_000 + np.maximum(a[mask], b[mask])
            unique, occurrences = np.unique(keys, return_counts=True)
            for key, occurrence in zip(unique.tolist(), occurrences.tolist()):
                pair = divmod(key, 1_000_000)
                counts[pair] = counts.get(pair, 0) + occurrence
    return counts


def compass_direction(offset: np.ndarray, centre: np.ndarray, config: dict) -> tuple[str, str]:
    lon0 = math.atan2(float(centre[1]), float(centre[0]))
    norm = float(np.linalg.norm(centre))
    lat0 = math.asin(max(-1.0, min(1.0, float(centre[2]) / max(norm, 1e-9))))
    east = np.array([-math.sin(lon0), math.cos(lon0), 0.0])
    north = np.array([-math.sin(lat0) * math.cos(lon0), -math.sin(lat0) * math.sin(lon0), math.cos(lat0)])
    angle = math.degrees(math.atan2(float(np.dot(offset, north)), float(np.dot(offset, east))))
    sector = int(round(((90.0 - angle) % 360.0) / 45.0)) % 8
    return config["compass_en"][sector], config["compass_fr"][sector]


def build_sea_zones(ids: np.ndarray, lakes: list[dict], marine_features: list[dict], projection: Projection,
                    config: dict, first_id: int) -> list[dict]:
    """Découpe l'eau (pixels à 0) en zones maritimes et lacs, écrit leurs ids dans ids et renvoie leur liste."""
    height = projection.height
    water = ids == 0

    big_lakes = [f for f in lakes if f["properties"]["scalerank"] <= config["max_lake_scalerank"]]
    lake_labels = rasterize([(i + 1, f["geometry"]) for i, f in enumerate(big_lakes)], projection, "I").astype(np.int32)
    lake_labels[~water] = 0

    protected = set(config["protected_sea_names"])
    kept = [f for f in marine_features
            if f["properties"].get("name") in protected
            or (f["properties"]["scalerank"] <= config["max_marine_scalerank"]
                and f["properties"]["featurecla"] in config["marine_classes"])]
    print(f"Zones maritimes : {len(kept)} mers et golfes retenus, {len(big_lakes)} lacs")
    labels = rasterize([(i + 1, f["geometry"]) for i, f in enumerate(kept)], projection, "I").astype(np.int32)
    labels[~water | (lake_labels > 0)] = 0

    # Eau non couverte : zone la plus proche (calcul à résolution réduite).
    missing = water & (lake_labels == 0) & (labels == 0)
    if missing.any():
        from scipy import ndimage
        step = config["sea_fill_downscale"]
        small = labels[::step, ::step]
        nearest = ndimage.distance_transform_edt(small == 0, return_distances=False, return_indices=True)
        filled = small[nearest[0], nearest[1]]
        ys, xs = np.nonzero(missing)
        labels[ys, xs] = filled[np.minimum(ys // step, filled.shape[0] - 1), np.minimum(xs // step, filled.shape[1] - 1)]

    # Petites zones fusionnées avec la voisine qui partage la plus longue frontière.
    label_count = len(kept) + 1
    areas = zone_areas(labels, label_count, projection)
    neighbours: dict[int, dict[int, int]] = {}
    for (a, b), length in zone_adjacency(labels).items():
        neighbours.setdefault(a, {})[b] = length
        neighbours.setdefault(b, {})[a] = length
    parent = list(range(label_count))

    def find(label: int) -> int:
        while parent[label] != label:
            parent[label] = parent[parent[label]]
            label = parent[label]
        return label

    mergeable = [l for l in range(1, label_count) if 0 < areas[l] < config["min_sea_zone_km2"]
                 and kept[l - 1]["properties"].get("name") not in protected]
    for label in sorted(mergeable, key=lambda l: areas[l]):
        root = find(label)
        candidates: dict[int, int] = {}
        for other, length in neighbours.get(label, {}).items():
            other_root = find(other)
            if other_root != root:
                candidates[other_root] = candidates.get(other_root, 0) + length
        if candidates:
            target = max(candidates, key=lambda c: (candidates[c], -c))
            parent[root] = target
            areas[target] += areas[root]
            areas[root] = 0.0
    lut = np.array([find(l) for l in range(label_count)], dtype=np.int32)
    labels = lut[labels]
    areas = zone_areas(labels, label_count, projection)

    # Grandes zones découpées en secteurs (k-moyennes sur la sphère).
    zones: list[dict] = []
    final_labels = labels.copy()
    next_label = label_count
    sample_step = config["sea_split_sample_step"]
    for label in range(1, label_count):
        if areas[label] <= 0:
            continue
        props = kept[label - 1]["properties"]
        name_en = props.get("name_en") or props.get("name") or ""
        name_fr = props.get("name_fr") or name_en
        sectors = int(math.ceil(areas[label] / config["max_sea_zone_km2"]))
        if sectors <= 1:
            zones.append({"label": label, "name_en": name_en, "name_fr": name_fr, "source": props.get("name")})
            continue
        ys, xs = np.nonzero(labels[::sample_step, ::sample_step] == label)
        vectors = pixel_vectors(xs * sample_step, ys * sample_step, projection)
        sectors = min(sectors, len(vectors))
        rng = np.random.default_rng(label)
        centroids = vectors[rng.choice(len(vectors), size=sectors, replace=False)]
        for _ in range(config["sea_split_iterations"]):
            assignment = np.argmax(vectors @ centroids.T, axis=1)
            for k in range(sectors):
                members = vectors[assignment == k]
                if len(members):
                    mean = members.mean(axis=0)
                    centroids[k] = mean / max(float(np.linalg.norm(mean)), 1e-9)
        sector_labels = np.arange(next_label, next_label + sectors, dtype=np.int32)
        next_label += sectors
        for y0 in range(0, height, ROW_CHUNK):
            y1 = min(y0 + ROW_CHUNK, height)
            block_ys, block_xs = np.nonzero(labels[y0:y1] == label)
            if block_ys.size == 0:
                continue
            block_vectors = pixel_vectors(block_xs, block_ys + y0, projection)
            final_labels[block_ys + y0, block_xs] = sector_labels[np.argmax(block_vectors @ centroids.T, axis=1)]
        zone_centre = vectors.mean(axis=0)
        used: dict[str, int] = {}
        for k in range(sectors):
            direction_en, direction_fr = compass_direction(centroids[k] - zone_centre, zone_centre, config)
            used[direction_en] = used.get(direction_en, 0) + 1
            suffix = "" if used[direction_en] == 1 else f" {used[direction_en]}"
            zones.append({"label": int(sector_labels[k]), "name_en": f"{name_en} ({direction_en}{suffix})",
                          "name_fr": f"{name_fr} ({direction_fr}{suffix})", "source": props.get("name")})

    # Identifiants définitifs : mers dans l'ordre de leurs étiquettes, puis lacs.
    zones.sort(key=lambda zone: zone["label"])
    id_of_label = np.zeros(next_label, dtype=np.int32)
    result: list[dict] = []
    next_id = first_id
    for zone in zones:
        id_of_label[zone["label"]] = next_id
        result.append({"id": next_id, "kind": "sea", "name_en": zone["name_en"], "name_fr": zone["name_fr"],
                       "source": zone["source"]})
        next_id += 1
    sea_pixels = water & (lake_labels == 0)
    ids[sea_pixels] = id_of_label[final_labels[sea_pixels]]
    lake_ids = np.zeros(len(big_lakes) + 1, dtype=np.int32)
    present = set(np.unique(lake_labels).tolist())
    for i, feature in enumerate(big_lakes):
        if i + 1 not in present:
            continue
        props = feature["properties"]
        name_en = props.get("name_en") or props.get("name") or ""
        lake_ids[i + 1] = next_id
        result.append({"id": next_id, "kind": "lake", "name_en": name_en, "name_fr": props.get("name_fr") or name_en,
                       "source": props.get("name")})
        next_id += 1
    lake_pixels = lake_labels > 0
    ids[lake_pixels] = lake_ids[lake_labels[lake_pixels]]
    return result


def resolve_straits(straits: dict, ids: np.ndarray, projection: Projection, province_count: int,
                    config: dict) -> dict:
    """Pour chaque détroit ou canal : zones maritimes à ses extrémités et provinces qui le bordent."""
    reach = config["strait_sea_search_px"]
    search = sorted(((dx, dy) for dx in range(-reach, reach + 1) for dy in range(-reach, reach + 1)),
                    key=lambda o: o[0] ** 2 + o[1] ** 2)
    result = {}
    for strait_id, strait in straits.items():
        radius = strait.get("province_radius_px", config["strait_province_radius_px"])
        ends = [projection.point(lon, lat) for lon, lat in strait["ends"]]
        # Zone la plus proche de chaque extrémité ; la seconde doit être différente de la première.
        zones: list[int] = []
        for x, y in ends:
            for dx, dy in search:
                value = int(ids[min(max(y + dy, 0), projection.height - 1), (x + dx) % projection.width])
                if value > province_count and value not in zones:
                    zones.append(value)
                    break
        provinces: set[int] = set()
        (x0, y0), (x1, y1) = ends
        dx_wrapped = (x1 - x0 + projection.width // 2) % projection.width - projection.width // 2
        for k in range(21):
            x = int(round(x0 + dx_wrapped * k / 20)) % projection.width
            y = int(round(y0 + (y1 - y0) * k / 20))
            rows = slice(max(y - radius, 0), y + radius + 1)
            window = ids[rows][:, np.arange(x - radius, x + radius + 1) % projection.width]
            provinces.update(int(v) for v in np.unique(window) if 0 < v <= province_count)
        result[strait_id] = {
            "name_key": f"STRAIT_{strait_id.upper()}",
            "kind": strait["kind"],
            "ends": [[float(x), float(y)] for x, y in ends],
            "sea_zones": zones,
            "provinces": sorted(provinces),
        }
    return result


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
    marine = load_layer("marine", version)

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

    # 4 bis. Zones maritimes et lacs, numérotés à la suite des provinces.
    sea_zones = build_sea_zones(ids, lakes, marine, projection, config, province_count + 1)
    sea_kind = {zone["id"]: zone["kind"] for zone in sea_zones}
    total_ids = province_count + len(sea_zones)
    print(f"{len(sea_zones)} zones maritimes et lacs")

    # 5. Statistiques par province, par bandes de lignes : taille, centre, surface, voisins, côtes.
    print("Analyse des pixels…")
    n = province_count + 1
    n_all = total_ids + 1
    count = np.zeros(n_all)
    sum_cos = np.zeros(n_all)
    sum_sin = np.zeros(n_all)
    sum_y = np.zeros(n_all)
    sum_area = np.zeros(n_all)
    pair_keys: list[np.ndarray] = []
    angles = 2.0 * math.pi * (np.arange(width) + 0.5) / width
    cos_x, sin_x = np.cos(angles), np.sin(angles)
    pixel_km2 = (EARTH_CIRCUMFERENCE_KM / width) * (MERIDIAN_LENGTH_KM / height)

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
        count += np.bincount(flat, minlength=n_all)
        sum_cos += np.bincount(flat, weights=np.tile(cos_x, rows), minlength=n_all)
        sum_sin += np.bincount(flat, weights=np.tile(sin_x, rows), minlength=n_all)
        sum_y += np.bincount(flat, weights=np.repeat(row_centres, width), minlength=n_all)
        sum_area += np.bincount(flat, weights=np.repeat(np.cos(latitudes) * pixel_km2, width), minlength=n_all)
        # Voisins horizontaux (avec bouclage est-ouest) et verticaux.
        right = np.roll(block, -1, axis=1)
        add_pairs(block, right)
        below_end = min(y1 + 1, height)
        extended = ids[y0:below_end]
        add_pairs(extended[:-1], extended[1:])

    pairs = np.unique(np.concatenate(pair_keys)) if pair_keys else np.array([], dtype=np.int64)
    neighbours: list[set[int]] = [set() for _ in range(n_all)]
    for key in pairs.tolist():
        a, b = divmod(key, 65536)
        neighbours[a].add(b)
        neighbours[b].add(a)

    safe_count = np.maximum(count, 1)
    centre_x = (np.arctan2(sum_sin, sum_cos) / (2.0 * math.pi) * width) % width
    centre_y = sum_y / safe_count
    # Côtière : province voisine d'une zone maritime (les lacs ne comptent pas).
    coastal = np.zeros(n, dtype=bool)
    for province_id in range(1, n):
        coastal[province_id] = any(sea_kind.get(other) == "sea" for other in neighbours[province_id])

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
    small_ids = np.where(small_ids < n, small_ids, 0)
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
        if province_id == 0 or province_id >= n:
            window = ids[max(y - 3, 0): y + 4, max(x - 3, 0): x + 4]
            found = window[(window > 0) & (window < n)]
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

    density = population / np.maximum(sum_area[:n], 1.0)
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
            found = int(ids[y, x])
            if found < n and owner[found] == tag:
                return found
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
            "neighbors": sorted(p for p in neighbours[province_id] if p < n),
            "sea_neighbors": sorted(p for p in neighbours[province_id] if sea_kind.get(p) == "sea"),
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
            "sea_zone_count": len(sea_zones),
            "max_id": total_ids,
            "source": f"Natural Earth {version} (domaine public)",
        }
    }
    (DATA_DIR / "map" / "map.json").write_text(json.dumps(map_info, ensure_ascii=False, indent=2) + "\n",
                                                encoding="utf-8", newline="\n")

    # Zones maritimes et détroits.
    sea_out: list[str] = []
    for zone in sea_zones:
        zone_id = zone["id"]
        entry = {
            "name_key": f"SEA_{zone_id}",
            "color": id_to_color(zone_id),
            "kind": zone["kind"],
            "area_km2": round(float(sum_area[zone_id]), 1),
            "size": int(count[zone_id]),
            "center": [round(float(centre_x[zone_id]), 1), round(float(centre_y[zone_id]), 1)],
            "neighbors": sorted(p for p in neighbours[zone_id] if p >= n),
            "coasts": sorted(p for p in neighbours[zone_id] if p < n),
            "source_name": zone["source"] or "",
        }
        sea_out.append(f'  "{zone_id}": {json.dumps(entry, ensure_ascii=False, separators=(",", ": "))}')
    (DATA_DIR / "sea_zones").mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "sea_zones" / "sea_zones.json").write_text(
        "{\n" + ",\n".join(sea_out) + "\n}\n", encoding="utf-8", newline="\n")
    straits = resolve_straits(config["straits"], ids, projection, province_count, config)
    (DATA_DIR / "straits").mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "straits" / "straits.json").write_text(
        json.dumps(straits, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

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
    sea_rows = [(f"SEA_{zone['id']}", zone["name_en"], zone["name_fr"]) for zone in sea_zones]
    sea_rows += [(f"STRAIT_{strait_id.upper()}", strait["name"]["en"], strait["name"]["fr"])
                 for strait_id, strait in config["straits"].items()]
    write_csv(DATA_DIR / "localization" / "sea_zones.csv", sea_rows)

    # Aperçu politique (non versionné).
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    lut = np.zeros((n_all, 3), dtype=np.uint8)
    lut[0] = (40, 70, 110)
    for zone in sea_zones:
        shade = zlib.crc32(str(zone["id"]).encode()) % 60
        lut[zone["id"]] = (20 + shade // 3, 50 + shade // 2, 90 + shade) if zone["kind"] == "sea" else (60, 120, 170)
    for province_id in range(1, n):
        tag = owner[province_id]
        colour = countries[tag]["color"] if tag else "#B0B0B0"
        lut[province_id] = [int(colour[i:i + 2], 16) for i in (1, 3, 5)]
    preview = lut[ids[::4, ::4]]
    Image.fromarray(preview, "RGB").save(OUT_DIR / "preview_political.png")
    unowned = sum(1 for p in range(1, n) if not owner[p])
    print(f"Terminé : {province_count} provinces, {len(sea_zones)} zones maritimes, {len(straits)} détroits, "
          f"{len(countries)} pays, {unowned} provinces sans propriétaire.")
    for strait_id, strait in straits.items():
        if len(strait["sea_zones"]) < 2:
            print(f"  Attention : le passage « {strait_id} » ne relie qu'une zone maritime ({strait['sea_zones']}).")


if __name__ == "__main__":
    main()

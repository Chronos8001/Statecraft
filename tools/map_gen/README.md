# Générateur de carte

Produit la carte des provinces du jeu à partir de données géographiques libres.

## Sources

- **Natural Earth** v5.1.2 (domaine public) : régions de premier niveau (états, provinces, départements…), pays, villes, lacs, régions géographiques, mers et océans.
- **Wikidata** (CC0), les données structurées de Wikipédia : population de chaque région et de chaque pays.

Les fichiers téléchargés sont mis en cache dans `tools/map_gen/cache/` (non versionné).

## Lancer

```sh
pip install -r tools/map_gen/requirements.txt
python tools/map_gen/generate_map.py
```

Durée : environ 2 minutes, plus le téléchargement des sources au premier lancement.

## Fichiers produits

| Fichier | Contenu |
|---|---|
| `data/map/provinces.png` | 16384 × 8192, projection équirectangulaire. Couleur d'un pixel = identifiant de sa province : `id = R + G × 256` (B = 0). Noir = eau. |
| `data/map/map.json` | Dimensions et métadonnées de la carte. |
| `data/provinces/provinces.json` | Une entrée par province : propriétaire, contrôleur, terrain, population, infrastructures, côtière, surface, taille en pixels, centre, voisins. |
| `data/countries/countries.json` | Les entrées existantes sont conservées ; seule la capitale est recalculée. Les pays manquants sont ajoutés (nom, couleur, capitale). |
| `data/sea_zones/sea_zones.json` | Zones maritimes et lacs (ids à la suite des provinces) : type, surface, centre, zones voisines, côtes. |
| `data/straits/straits.json` | Détroits et canaux : extrémités, les deux zones maritimes reliées, provinces riveraines. |
| `data/localization/provinces.csv`, `countries.csv`, `sea_zones.csv` | Noms en anglais et en français. |
| `tools/map_gen/out/preview_political.png` | Aperçu politique (non versionné). |

## Réglages

Tout est dans `config.json` :

- `unit_owners`, `tag_renames`, `unowned_units` : rattachement des territoires (dépendances, zones contestées) à un pays.
- `province_merges` : régions regroupées en une seule province (ex. les arrondissements de Londres).
- `marine_name_overrides` : noms corrigés de mers et d'océans.
- `province_overrides` : propriétaire ou contrôleur forcé pour une région (ex. territoires occupés au 1er janvier 2026).
- `country_name_overrides`, `province_name_overrides` : noms corrigés.
- `min_province_pixels`, `micro_province_radius` : taille minimale des micro-États et îlots pour qu'ils restent cliquables.
- `terrain_regions`, `climate_latitudes` : règles de terrain.
- `urban_density_km2` : densité à partir de laquelle une province devient urbaine.
- `max_marine_scalerank`, `min_sea_zone_km2`, `max_sea_zone_km2`, `protected_sea_names` : découpage des mers (fusion des petites, secteurs dans les océans).
- `straits` : détroits et canaux (nom, type, coordonnées des deux extrémités, rayon de recherche des rives).

Les identifiants de provinces suivent l'ordre des codes Natural Earth (`source_id`) : ils restent stables tant que les sources ne changent pas.

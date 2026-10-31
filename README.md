# Statecraft

**Statecraft** est un jeu de grande stratégie géopolitique en temps réel pausable. La partie commence le **1er janvier 2026**, dans le monde réel de cette date : vrais pays, frontières, régimes, économies, alliances et conflits en cours.

Le joueur dirige un pays parmi les quelque 195 États et s'appuie sur trois piliers :

- **Gouverner** : budget ligne par ligne, impôts, lois, élections, partis, ministres, dette, stabilité.
- **Négocier** : diplomatie, traités, ONU, sanctions, sphères d'influence, renseignement.
- **Combattre** : une guerre stratégique (budgets, postures, fronts, buts de guerre) plutôt que tactique.

Il n'y a pas de condition de victoire unique : objectifs nationaux, score de puissance, scénarios de crise et mode bac à sable. On peut gagner sans presque jamais faire la guerre.

Les pays, institutions et organisations internationales portent leurs vrais noms. Les personnes, partis, entreprises, médias et groupes armés ont des noms inventés, fidèles à leurs équivalents réels (idéologie, poids, position).

## Prérequis

- **Godot 4.7 ou plus récent** (version standard, GDScript), développé avec Godot 4.7.2 : <https://godotengine.org/download>
- **GUT 9.7** (Godot Unit Test) pour les tests, déjà inclus dans `addons/gut/`.

## Lancer le projet

1. Ouvrir Godot, cliquer sur **Importer**, puis sélectionner le fichier `project.godot` à la racine du dépôt.
2. Appuyer sur **F5** (ou le bouton ▶) pour lancer le jeu.

En ligne de commande :

```sh
godot --path .
```

## Lancer les tests

Depuis l'éditeur : panneau **GUT** en bas de l'écran, puis **Run All**.

En ligne de commande :

```sh
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd
```

La configuration des tests est dans `.gutconfig.json`. La première commande n'est nécessaire qu'après un clonage ou l'ajout de nouveaux fichiers.

## Arborescence

```
core/     autoloads : horloge, bus d'événements, sauvegarde, mods
sim/      simulation : économie, politique, diplomatie, militaire, IA
map/      rendu de la carte, shaders, sélection des provinces
ui/       scènes et scripts d'interface
data/     données de jeu en JSON (pays, provinces, lois, technologies…)
assets/   textures, icônes, sons, polices
tests/    tests unitaires GUT
docs/     suivi du projet
```

## Modding

Toutes les données de jeu sont dans `data/`, en JSON, validées par les schémas de `data/schemas/`. Les textes affichés sont dans `data/localization/*.csv` (colonnes `keys,en,fr`).

> Les mods utilisateur sont **désactivés pour l'instant** : le jeu ne lit pas `user://mods/`. Le format ci-dessous est prévu pour leur réactivation.

Un mod est un dossier dans `user://mods/` (sous Windows : `%APPDATA%\Godot\app_userdata\Statecraft\mods\`) :

```
mods/mon_mod/
  mod.json          {"id": "mon_mod", "name": "Mon mod", "version": "1.0.0", "load_order": 0}
  data/             mêmes chemins que data/ du jeu
    countries/mon_fichier.json
    localization/mon_mod.csv
```

Les fichiers d'un mod sont fusionnés par-dessus les données du jeu, entrée par entrée :

- une valeur remplace la valeur d'origine (les tableaux sont remplacés en entier) ;
- `null` supprime une entrée ou un champ ;
- `"__replace": true` dans un objet le remplace entièrement au lieu de le fusionner.

Exemple : `{"FRA": {"population": 70000000}}` ne change que la population de la France.

## Carte et sources des données

La carte des provinces est générée par `tools/map_gen/` (voir son [README](tools/map_gen/README.md)) à partir de **Natural Earth** (domaine public) et des populations de **Wikidata / Wikipédia** (CC0). Les données des pays (population, PIB, dette, armées) et leur situation économique au 1er janvier 2026 (croissance, inflation, chômage, taux directeurs, notes souveraines, secteurs, taux de change, impôts et dépenses publiques, production et consommation des ressources, commerce extérieur, production d'électricité par source, entreprises publiques, investissements étrangers et fonds souverains) viennent des tableaux de **Wikipédia** et de **currency-api** via `tools/country_gen/` (voir son [README](tools/country_gen/README.md)). Les dirigeants et partis, tous fictifs, sont écrits à la main pour les 30 pays majeurs et générés par `tools/leader_gen/` pour les autres (voir son [README](tools/leader_gen/README.md)). Les drapeaux viennent de **flag-icons** (licence MIT) et de **Wikimedia Commons** (domaine public) via `tools/flag_gen/` (voir son [README](tools/flag_gen/README.md)). Les images de carte sont stockées avec **Git LFS** : installer Git LFS avant de cloner le dépôt.

## Suivi du projet

- [docs/PROGRESS.md](docs/PROGRESS.md) : avancement des étapes de développement.
- [docs/DECISIONS.md](docs/DECISIONS.md) : choix techniques.
- [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) : bugs connus et dette technique.
- [CHANGELOG.md](CHANGELOG.md) : historique des versions.

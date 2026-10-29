# Statecraft

**Statecraft** est un jeu de grande stratégie géopolitique en temps réel pausable. La partie commence le **1er janvier 2026**, dans le monde réel de cette date : vrais pays, frontières, régimes, économies, alliances et conflits en cours.

Le joueur dirige un pays parmi les quelque 195 États et s'appuie sur trois piliers :

- **Gouverner** : budget ligne par ligne, impôts, lois, élections, partis, ministres, dette, stabilité.
- **Négocier** : diplomatie, traités, ONU, sanctions, sphères d'influence, renseignement.
- **Combattre** : une guerre stratégique (budgets, postures, fronts, buts de guerre) plutôt que tactique.

Il n'y a pas de condition de victoire unique : objectifs nationaux, score de puissance, scénarios de crise et mode bac à sable. On peut gagner sans presque jamais faire la guerre.

Les pays, institutions et organisations internationales portent leurs vrais noms. Les personnes, partis, entreprises, médias et groupes armés ont des noms inventés, fidèles à leurs équivalents réels (idéologie, poids, position).

## Prérequis

- **Godot 4.3 ou plus récent** (version standard, GDScript) : <https://godotengine.org/download>
- **GUT** (Godot Unit Test) pour les tests, inclus dans `addons/gut/` une fois le projet initialisé.

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
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

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

Toutes les données de jeu sont dans `data/`. Un dossier `user://mods/` peut surcharger ou compléter n'importe quel fichier de `data/` sans toucher au code.

## Suivi du projet

- [docs/PROGRESS.md](docs/PROGRESS.md) : avancement des étapes de développement.
- [docs/DECISIONS.md](docs/DECISIONS.md) : choix techniques.
- [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) : bugs connus et dette technique.
- [CHANGELOG.md](CHANGELOG.md) : historique des versions.

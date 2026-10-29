# Journal des modifications

Toutes les modifications notables du projet sont consignées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le projet respecte le [versionnage sémantique](https://semver.org/lang/fr/).

## [Unreleased]

### Ajouté
- Carte du monde générée : 4 596 provinces réelles (16384 × 8192), avec propriétaire, contrôleur, terrain, population (Wikidata), infrastructures, côtes, surface, centre et voisins.
- Les 199 pays du monde en version minimale (nom FR / EN, couleur, capitale).
- Territoires occupés au 1er janvier 2026 : Crimée, Sébastopol, Donetsk et Louhansk sous contrôle russe.
- Outil de génération de la carte (`tools/map_gen/`).
- Affichage de la carte en jeu par shader (mode politique), chargée en arrière-plan.
- Caméra : zoom vers le curseur (molette, Page préc. / Page suiv.), déplacement au clavier (WASD / ZQSD selon le clavier, flèches), glisser avec le clic droit ou la molette, défilement au bord de l'écran, carte qui boucle d'est en ouest.
- « Nouvelle partie » ouvre l'écran de jeu ; Échap revient à l'écran titre.
- Clic sur une province : mise en évidence sur la carte et panneau d'information (pays, occupation, capitale, population, superficie, terrain, infrastructures, côte, ressources, voisins). Échap ou ✕ ferme le panneau.
- 11 modes de carte décrits dans `data/map_modes/` : politique, terrain, population (densité), PIB/hab., idéologie, alliances, relations, ressources, infrastructures, contrôle militaire (territoires occupés teintés), stabilité. Barre de choix en bas de l'écran, Tab / Maj+Tab pour changer, légende en bas à gauche.
- Couleurs des organisations internationales et des ressources.
- Nombres affichés selon la langue (« 2 138 259 » / « 2,138,259 »).

### Modifié
- Mer plus sombre et bleu des États-Unis plus clair pour mieux les distinguer.
- Les pays n'exigent plus que leur nom, leur couleur et leur capitale ; les données politiques et économiques restent facultatives jusqu'à l'étape des pays.

## [0.0.0] - 2026-10-29

### Ajouté
- Projet Godot 4.7 avec l'arborescence `core/`, `sim/`, `map/`, `ui/`, `data/`, `assets/`, `tests/`.
- Autoloads : `EventBus`, `SystemRegistry`, `ModManager`, `DataLoader`, `Localization`, `GameState`, `GameClock`, `SaveManager`.
- Chargement des données JSON par catégorie, fusion des DLC, validation par schémas avec contrôle des références entre fichiers.
- Données d'exemple au 1er janvier 2026 : États-Unis, Chine, France, Allemagne, Brésil, 10 provinces, dirigeants et partis aux noms fictifs, organisations internationales, idéologies, régimes, terrains, ressources.
- Localisation français / anglais depuis des fichiers CSV, langue choisie dans les options et mémorisée.
- Écran titre : Nouvelle partie, Charger, Options (langue), Quitter, avec le nombre de fichiers de données chargés.
- Date de jeu (calendrier grégorien, heure par heure), file de commandes et état de simulation à graine aléatoire unique.
- Tests unitaires GUT (54 tests).
- Mods utilisateur prévus mais désactivés pour l'instant (activation dans une mise à jour ultérieure).
- README avec présentation du jeu, prérequis, lancement, tests et modding.
- Suivi du projet : `docs/PROGRESS.md`, `docs/DECISIONS.md`, `docs/KNOWN_ISSUES.md`.
- Configuration Git : `.gitignore` et `.gitattributes` (fins de ligne LF, fichiers binaires).

[Unreleased]: https://github.com/Chronos8001/Statecraft/compare/v0.0.0...HEAD
[0.0.0]: https://github.com/Chronos8001/Statecraft/releases/tag/v0.0.0

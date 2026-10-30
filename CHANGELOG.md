# Journal des modifications

Toutes les modifications notables du projet sont consignées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le projet respecte le [versionnage sémantique](https://semver.org/lang/fr/).

## [Unreleased]

### Ajouté
- Simulation macroéconomique mensuelle des 199 pays : croissance, inflation, chômage, PIB par secteur (8 secteurs), dette publique, note souveraine.
- Situation économique réelle au 1er janvier 2026 (FMI, Banque mondiale, S&P, Fitch, Moody's, taux de change du jour) ; notes estimées pour les pays non notés.
- 143 monnaies réelles : taux de change face au dollar, unions monétaires (euro, francs CFA, dollar des Caraïbes orientales), ancrages (dollar, euro, roupie indienne, rand).
- Banques centrales : taux directeur fixé par la règle de Taylor ; quand la banque centrale dépend du gouvernement, le joueur fixe lui-même le taux.
- Dette en monnaie locale et en devises, taux d'emprunt selon la note, crises de la dette (défaut, restructuration, chute de la monnaie) et programmes du FMI.
- Panneau Économie (bouton dans la barre supérieure) : chiffres clés, banque centrale, dette, note, secteurs ; fixer le taux directeur, demander l'aide du FMI.
- Notifications des changements de note, des défauts de paiement et des programmes du FMI du pays joué.
- Outil de génération des données macroéconomiques (`tools/country_gen/generate_economy.py`).

- Budget de l'État : 7 impôts (dont l'impôt sur le revenu en 4 tranches) et 14 postes de dépense, aux taux et montants réels de 2026.
- Effets de chaque impôt et de chaque dépense : croissance, chômage, inflation, et effets attendus sur la stabilité, la recherche, l'armée, l'influence et 10 groupes sociaux.
- Création monétaire pour les pays dont le gouvernement contrôle la banque centrale.
- Les pays de l'IA ajustent leurs dépenses selon l'évolution de leur dette.
- Panneau Budget (bouton dans la barre supérieure) : réglage des impôts et des dépenses, aperçu des recettes, du solde et des effets avant d'appliquer.
- Outil de génération des budgets (`tools/country_gen/generate_budget.py`).

### Modifié
- Le solde budgétaire dépend désormais du budget ; la relance budgétaire soutient la croissance à court terme.
- Barre supérieure : la trésorerie affiche le solde budgétaire annuel du pays joué.
- La fiche du pays et le résumé de l'écran de sélection affichent la croissance, l'inflation, la monnaie et la note du pays en cours de partie.

## [0.3.0] - 2026-10-30

### Ajouté
- Données réelles des 199 pays (source Wikipédia) : population, PIB nominal (FMI 2026), dette publique (FMI 2025), effectifs militaires actifs et de réserve.
- Régimes et appartenance aux organisations internationales au 1er janvier 2026 ; 8 nouvelles organisations (Union africaine, Ligue arabe, ASEAN, OPEP, OTSC, Mercosur, CCG, UEEA).
- Outil de génération des données des pays (`tools/country_gen/`).
- Dirigeants fictifs (chef de l'État, chef du gouvernement), partis au pouvoir, coalitions et idéologie dominante des 199 pays, calqués sur la situation au 1er janvier 2026 (âge, sexe, idéologie, coalitions) : 30 pays majeurs écrits à la main, les autres générés.
- Générateur de noms par culture (56 cultures) et de noms de partis (17 langues), réutilisable en cours de partie.
- Traits de personnage : tempérament, style de gouvernement, parcours, orientation.
- Outil de génération des dirigeants et partis (`tools/leader_gen/`).
- Drapeaux des 199 pays, affichés dans la fiche du pays et dans la barre supérieure ; drapeaux en usage de fait au 1er janvier 2026 (Afghanistan, Syrie).
- Outil de génération des drapeaux (`tools/flag_gen/`).
- Écran de sélection du pays : liste avec drapeaux, recherche, filtre par difficulté (très facile à très difficile), résumé du pays et défis de départ ; clic sur la carte ou dans la liste.
- Défis de départ : écrits pour les grandes puissances et les pays en crise, déduits des données pour les autres (dette, pauvreté, occupation, coalition, enclavement…).
- Mode avancé : Chypre du Nord et le Somaliland jouables en cochant « Entités non reconnues ».

### Modifié
- La population des provinces correspond désormais exactement au total de leur pays.
- Fiche du pays : âge des dirigeants, noms dans l'ordre de leur culture (« Wei Jianguo »), chef du gouvernement masqué quand il s'agit du chef de l'État.
- Le mode de carte « idéologie » couvre désormais tous les pays.
- Fiche du pays : le drapeau remplace le carré de couleur.
- « Nouvelle partie » ouvre l'écran de sélection ; la partie démarre sur le pays choisi, caméra centrée sur sa capitale.

### Corrigé
- Fiche du pays : l'âge des dirigeants (« 49 ans ») n'est plus coupé en fin de ligne.

## [0.2.0] - 2026-10-29

### Ajouté
- Écoulement du temps à la manière de HOI4 et CK3 : 1 tick = 1 heure de jeu, pause et 5 vitesses (2 s, 0,5 s, 0,2 s et 0,1 s par heure, puis sans limite), raccourcis Espace, + / - et 1 à 5.
- Ordonnanceur de la simulation : systèmes abonnés aux heures, jours, semaines, mois et années, appelés dans un ordre fixe.
- Barre supérieure : date localisée, pause, vitesse, pays joué et ressources clés (en attente des systèmes qui les calculent).
- Notification à chaque nouveau mois et nouvelle année.

## [0.1.0] - 2026-10-29

### Ajouté
- Carte du monde générée : 4 564 provinces réelles (arrondissements de Londres regroupés en une province) (16384 × 8192), avec propriétaire, contrôleur, terrain, population (Wikidata), infrastructures, côtes, surface, centre et voisins.
- Les 199 pays du monde en version minimale (nom FR / EN, couleur, capitale).
- Territoires occupés au 1er janvier 2026 : Crimée, Sébastopol, Donetsk et Louhansk sous contrôle russe.
- Outil de génération de la carte (`tools/map_gen/`).
- Affichage de la carte en jeu par shader (mode politique), chargée en arrière-plan.
- Caméra : zoom vers le curseur (molette, Page préc. / Page suiv.), déplacement au clavier (WASD / ZQSD selon le clavier, flèches), glisser avec le clic droit ou la molette, défilement au bord de l'écran, carte qui boucle d'est en ouest.
- « Nouvelle partie » ouvre l'écran de jeu ; Échap revient à l'écran titre.
- Clic sur une province : fiche du pays propriétaire (capitale, régime, dirigeants, parti, idéologie, population, superficie, PIB, dette, armée, organisations, territoires occupés), le pays est mis en évidence sur la carte.
- Double-clic sur une province : sa fiche (pays, occupation, capitale, population, superficie, terrain, infrastructures, côte, ressources, voisins, détroits). Échap ou ✕ ferme les fiches.
- 11 modes de carte décrits dans `data/map_modes/` : politique, terrain, population (densité), PIB/hab., idéologie, alliances, relations, ressources, infrastructures, contrôle militaire (territoires occupés teintés), stabilité. Barre de choix en bas de l'écran, Tab / Maj+Tab pour changer, légende en bas à gauche.
- Couleurs des organisations internationales et des ressources.
- Frontières de pays et côtes (épaisses) et de provinces (fines, estompées en zoom arrière), d'épaisseur constante à l'écran.
- Contours lissés en zoom rapproché : la carte n'apparaît plus en escalier de pixels.
- 184 zones maritimes et lacs générés (mers nommées de Natural Earth, océans découpés en grands secteurs d'environ 8 millions de km²), avec leurs voisines et leurs côtes ; les provinces côtières connaissent leurs zones maritimes.
- 17 détroits et canaux stratégiques (Suez, Panama, Kiel, Ormuz, Malacca, Bosphore, Dardanelles, Gibraltar, Bab-el-Mandeb, Øresund, Pas de Calais, Taïwan, Béring, Kertch, Sonde, Lombok, Magellan) reliant deux zones maritimes, affichés sur la carte avec leur nom.
- Clic sur une mer ou un lac : superficie, zones voisines, provinces côtières, détroits.
- Noms des pays écrits en courbe selon la forme de leur territoire principal, affichés seulement quand ils sont lisibles.
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

[Unreleased]: https://github.com/Chronos8001/Statecraft/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Chronos8001/Statecraft/releases/tag/v0.3.0
[0.2.0]: https://github.com/Chronos8001/Statecraft/releases/tag/v0.2.0
[0.1.0]: https://github.com/Chronos8001/Statecraft/releases/tag/v0.1.0
[0.0.0]: https://github.com/Chronos8001/Statecraft/releases/tag/v0.0.0

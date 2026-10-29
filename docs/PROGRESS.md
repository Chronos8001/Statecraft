# Avancement du jeu de base

Légende : ⬜ à faire · 🟨 en cours · ✅ validée

| Étape | Nom | Statut | Version cible | Validée le | Tag |
|---|---|---|---|---|---|
| 0 | Fondations du projet | ✅ | v0.0.0 | 2026-10-29 | v0.0.0 |
| 1 | La carte du monde | 🟨 | v0.1.0 | | |
| 2 | Temps et boucle de simulation | ⬜ | v0.2.0 | | |
| 3 | Les pays en 2026 | ⬜ | v0.3.0 | | |
| 4 | Économie | ⬜ | v0.4.0 | | |
| 5 | Politique intérieure | ⬜ | v0.5.0 | | |
| 6 | Diplomatie | ⬜ | v0.6.0 | | |
| 7 | Militaire (version simplifiée) | ⬜ | v0.7.0 | | |
| 8 | Recherche et technologie | ⬜ | v0.8.0 | | |
| 9 | Arbres de décisions nationales et événements | ⬜ | v0.9.0 | | |
| 10 | Société, démographie, climat | ⬜ | v0.10.0 | | |
| 11 | Renseignement et opérations clandestines | ⬜ | v0.11.0 | | |
| 12 | Intelligence artificielle des pays | ⬜ | v0.12.0 | | |
| 13 | Interface utilisateur | ⬜ | v0.13.0 | | |
| 14 | Sauvegarde et modding | ⬜ | v0.14.0 | | |
| 15 | Équilibrage, scénarios et finitions | ⬜ | v1.0.0 | | |

---

## Étape 0 — Fondations du projet ✅ (validée le 2026-10-29, v0.0.0)
- [x] Création du projet Godot et arborescence (`core/`, `sim/`, `map/`, `ui/`, `data/`, `assets/`, `tests/`)
- [x] Autoloads vides mais fonctionnels : `GameClock`, `GameState`, `DataLoader`, `EventBus`, `SaveManager`, `ModManager`, `Localization`
- [x] `DataLoader` : chargement de tous les JSON de `data/`, validation des schémas, journal des erreurs
- [x] `ModManager` : fusion des fichiers de `user://mods/` par-dessus `data/` (désactivée pour l'instant, activation dans une mise à jour ultérieure)
- [x] `EventBus` : signaux globaux (`day_passed`, `month_passed`, `war_declared`, `election_held`…)
- [x] Points d'extension pour les futurs modules (`SystemRegistry`, DLC dans `res://dlc/`)
- [x] Localisation FR / EN en place
- [x] Schémas JSON d'un pays et d'une province, 5 pays d'exemple
- [x] Écran titre minimal : Nouvelle partie / Charger / Options / Quitter
- [x] GUT installé et premiers tests
- [x] Validation : le jeu démarre, la console affiche le nombre de fichiers chargés

## Étape 1 — La carte du monde 🟨
**1a. Génération de la carte**
- [x] Outil `tools/map_gen/` : Natural Earth + populations Wikidata → `provinces.png` (16384 × 8192) + `provinces.json`
- [x] 4 596 provinces réelles (régions de premier niveau), 199 pays en version minimale
- [x] Propriétaire / contrôleur, terrain, population, infrastructures, côtière, surface, centre, voisins
- [x] Micro-États et îlots agrandis à une taille minimale
- [x] Noms FR / EN des provinces et des pays

**1b. Rendu et caméra**
- [ ] Rendu via shader avec texture de lookup (recoloration sans regénérer la carte)
- [ ] Caméra : zoom molette, déplacement clavier / souris / bord d'écran, limites, wrap est-ouest

**1c. Sélection**
- [ ] Picking : clic → couleur → id de province
- [ ] Panneau d'info de la province

**1d. Modes de carte**
- [ ] Politique, terrain, population, PIB/hab., idéologie, alliances, relations, ressources, infrastructures, contrôle militaire, stabilité

**1e. Frontières et noms**
- [ ] Frontières de pays (épaisses) et de provinces (fines)
- [ ] Noms de pays affichés en courbe selon la forme

**1f. Mers**
- [ ] Zones maritimes
- [ ] Détroits et canaux stratégiques (Suez, Panama, Ormuz, Malacca, Bosphore…)

- [ ] Validation : clic sur une province → panneau d'info

## Étape 2 — Temps et boucle de simulation ⬜
- [ ] `GameClock` : date, heure, pause, 5 vitesses, raccourcis (Espace, +, -)
- [ ] Ordonnanceur : abonnements `hourly`, `daily`, `weekly`, `monthly`, `yearly`
- [ ] Barre supérieure : date, vitesse, trésorerie, stabilité, soutien populaire, puissance militaire, influence
- [ ] Validation : le temps défile, les événements mensuels se déclenchent

## Étape 3 — Les pays en 2026 ⬜
- [ ] `countries.json` : nom, tag, drapeau, capitale, couleur, régime, dirigeants (id fictifs), parti au pouvoir, idéologie, PIB, dette/PIB, population, armée, organisations
- [ ] Données réalistes de janvier 2026 (précises pour les grandes puissances, approchées pour les autres)
- [ ] `characters.json` : personnages fictifs équivalents aux vrais
- [ ] Fichiers de noms (`data/names/*.json`) et générateur de noms par culture
- [ ] `organizations.json` pour les organisations internationales
- [ ] Écran de sélection du pays : carte, filtres par difficulté, résumé, défis de départ
- [ ] Validation : choisir n'importe quel pays et démarrer la partie

## Étape 4 — Économie ⬜
**4a. Macroéconomie**
- [ ] PIB par secteur (agriculture, industrie, énergie, services, tech, finance, tourisme, armement)
- [ ] Croissance, inflation, chômage, taux directeur, banque centrale indépendante ou non
- [ ] Monnaie et taux de change
- [ ] Dette publique, notation souveraine (AAA → défaut), taux d'emprunt, crise de la dette, FMI

**4b. Budget de l'État**
- [ ] Recettes : impôt sur le revenu (tranches), IS, TVA, taxe carbone, douanes, cotisations, taxes sur ressources
- [ ] Dépenses : santé, éducation, retraites, chômage, police, justice, défense, recherche, infrastructures, environnement, culture, aide internationale, renseignement, administration
- [ ] Effets de chaque ligne (groupes sociaux, croissance, stabilité, recherche, armée)
- [ ] Déficit → dette ; création monétaire → inflation

**4c. Ressources et commerce**
- [ ] Ressources stratégiques (pétrole, gaz, uranium, charbon, terres rares, lithium, cobalt, semi-conducteurs, blé, acier, eau)
- [ ] Marché mondial à prix dynamiques et chocs (fermeture de détroit)
- [ ] Accords commerciaux, zones de libre-échange, douanes, embargos, dépendances visibles
- [ ] Chaînes d'approvisionnement simplifiées

**4d. Entreprises et investissements**
- [ ] Entreprises publiques et privées par secteur ; nationalisation / privatisation
- [ ] IDE, fonds souverains, construction de bâtiments (usines, centrales, ports, data centers, raffineries, mines)
- [ ] Énergie : mix énergétique, production vs consommation, coupures

## Étape 5 — Politique intérieure ⬜
- [ ] Régimes (parlementaire, présidentiel, monarchies, autoritaire, parti unique, théocratie, junte, État failli)
- [ ] Partis fictifs calqués sur le paysage réel de 2026, coalitions
- [ ] Élections : calendrier réel, campagnes, sondages mensuels, résultats par région, fraude
- [ ] Groupes sociaux / lobbies avec attentes et poids
- [ ] Catalogue de 80+ lois, vote au parlement
- [ ] Constitution : réformes, référendums, limites de mandats, état d'urgence
- [ ] Gouvernement : ministres, remaniements, scandales
- [ ] Stabilité, corruption, soutien populaire, légitimité ; grèves, émeutes, coups d'État, guerre civile
- [ ] Médias et opinion : contrôle, propagande, désinformation, réseaux sociaux

## Étape 6 — Diplomatie ⬜
- [ ] Relations bilatérales (-100 à +100), opinion publique étrangère, confiance
- [ ] Actions : relations, visites d'État, ambassades, traités, reconnaissance, garanties, ultimatums
- [ ] Organisations internationales : ONU (Assemblée, Conseil de sécurité, veto), alliances, unions, cartels ; adhésion, exclusion, création
- [ ] Sanctions, gel d'avoirs, exclusion des systèmes de paiement
- [ ] Aide économique, humanitaire, militaire, prêts, conseillers
- [ ] Sphères d'influence et points d'influence
- [ ] Revendications territoriales et jauge de tension mondiale

## Étape 7 — Militaire (version simplifiée) ⬜
**7a. Forces armées**
- [ ] Branches terre / air / mer + jauges spéciales (forces spéciales, missiles, cyber, nucléaire)
- [ ] Effectifs, niveau d'équipement (1 à 5), entraînement, moral, budget par branche
- [ ] Production simplifiée par points d'équipement ; accords de vente d'armes
- [ ] Armée professionnelle / conscription, réservistes, mobilisation générale
- [ ] Pions « groupe d'armées » par région sur la carte

**7b. Guerre**
- [ ] Déclaration de guerre, justification, buts de guerre, coût diplomatique
- [ ] Fronts automatiques, répartition des forces, postures par front
- [ ] Résolution quotidienne par front (puissance, terrain, équipement, air, ravitaillement, moral)
- [ ] Marine : contrôle des zones maritimes, blocus, débarquements
- [ ] Actions ponctuelles : frappes de missiles, opérations spéciales, cyberattaques
- [ ] Nucléaire : arsenal, niveau d'alerte, programmes secrets, conséquences
- [ ] Fatigue de guerre, pertes, cessez-le-feu, conférence de paix, occupation, gouvernements fantoches

**7c. Préparer le module avancé**
- [ ] Interfaces remplaçables `MilitaryModel`, `WarResolver`, `MilitaryAI`, `MilitaryUI` dans un registre
- [ ] Conversion des données militaires de base vers un modèle détaillé

## Étape 8 — Recherche et technologie ⬜
- [ ] Arbres : économie, industrie, énergie, militaire terre/air/mer, cyber, IA, spatial, biotech, santé, social
- [ ] Technologies 2026 → 2050
- [ ] Vitesse liée au budget, aux universités, aux coopérations, à l'espionnage industriel
- [ ] Course à l'IA (gains économiques, risques sociaux)

## Étape 9 — Arbres de décisions nationales et événements ⬜
- [ ] Arbre de décisions générique + arbres uniques pour ~30 pays majeurs
- [ ] Décisions ponctuelles conditionnées
- [ ] Événements scriptés en JSON : déclencheurs, MTTH, choix, effets, chaînes
- [ ] Langage de conditions / effets lisible
- [ ] Événements mondiaux (pandémie, krach, catastrophes, attentats, morts de dirigeants…)
- [ ] Éditeur d'événements intégré

## Étape 10 — Société, démographie, climat ⬜
- [ ] Démographie : natalité, mortalité, vieillissement, pyramide des âges, urbanisation
- [ ] Migrations et politiques d'accueil
- [ ] Santé, éducation, criminalité, inégalités (Gini), IDH
- [ ] Climat : émissions, accords, réchauffement, événements extrêmes, montée des eaux
- [ ] Religions et ethnies par province, séparatismes, référendums d'indépendance

## Étape 11 — Renseignement et opérations clandestines ⬜
- [ ] Agence de renseignement, budget, réseaux d'agents par pays
- [ ] Brouillard diplomatique (chiffres approximatifs sans renseignement)
- [ ] Opérations : sabotage, vol de technologies, assassinat, financement d'opposition, ingérence électorale, coup d'État, contre-espionnage
- [ ] Chance de réussite, risque de découverte, incidents diplomatiques

## Étape 12 — Intelligence artificielle des pays ⬜
- [ ] Architecture Utility AI pondérée par la personnalité
- [ ] Couches économique, politique, diplomatique, militaire
- [ ] Mémoire diplomatique, doctrines cohérentes avec 2026
- [ ] Niveaux de difficulté
- [ ] Calcul étalé sur plusieurs ticks

## Étape 13 — Interface utilisateur ⬜
- [ ] Thème sombre « salle de crise »
- [ ] Panneaux : pays, économie, budget, lois, gouvernement, partis, diplomatie, ONU, commerce, militaire, production, recherche, renseignement, décisions
- [ ] Fil d'actualités défilant, journal, notifications filtrables
- [ ] Graphiques historiques, tooltips explicatifs sur chaque chiffre
- [ ] Recherche rapide, raccourcis clavier, mise à l'échelle de l'UI
- [ ] Tutoriel interactif et encyclopédie

## Étape 14 — Sauvegarde et modding ⬜
- [ ] Sauvegarde / chargement complet, autosave, compression, versionnage
- [ ] Simulation déterministe (graine unique, indépendance du framerate, commandes)
- [ ] Documentation des fichiers JSON, rechargement à chaud en mode dev, support Workshop prévu

## Étape 15 — Équilibrage, scénarios et finitions ⬜
- [ ] Scénario « Monde 2026 » + 4 à 6 scénarios de crise avec objectifs
- [ ] Succès, statistiques de fin de partie, timelapse de la carte
- [ ] Musique dynamique et sons d'interface
- [ ] Optimisation et tests de partie IA seule sur 25 ans

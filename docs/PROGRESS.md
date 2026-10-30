# Avancement du jeu de base

Légende : ⬜ à faire · 🟨 en cours · ✅ validée

| Étape | Nom | Statut | Version cible | Validée le | Tag |
|---|---|---|---|---|---|
| 0 | Fondations du projet | ✅ | v0.0.0 | 2026-10-29 | v0.0.0 |
| 1 | La carte du monde | ✅ | v0.1.0 | 2026-10-29 | v0.1.0 |
| 2 | Temps et boucle de simulation | ✅ | v0.2.0 | 2026-10-29 | v0.2.0 |
| 3 | Les pays en 2026 | ✅ | v0.3.0 | 2026-10-30 | v0.3.0 |
| 4 | Économie | 🟨 | v0.4.0 | | |
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

## Étape 1 — La carte du monde ✅ (validée le 2026-10-29, v0.1.0)
**1a. Génération de la carte**
- [x] Outil `tools/map_gen/` : Natural Earth + populations Wikidata → `provinces.png` (16384 × 8192) + `provinces.json`
- [x] 4 564 provinces réelles (régions de premier niveau, arrondissements de Londres regroupés), 199 pays en version minimale
- [x] Propriétaire / contrôleur, terrain, population, infrastructures, côtière, surface, centre, voisins
- [x] Micro-États et îlots agrandis à une taille minimale
- [x] Noms FR / EN des provinces et des pays

**1b. Rendu et caméra**
- [x] Rendu via shader avec texture de lookup (recoloration sans regénérer la carte)
- [x] Caméra : zoom molette, déplacement clavier / souris / bord d'écran, limites, wrap est-ouest

**1c. Sélection**
- [x] Picking : clic → couleur → id de province
- [x] Fiche du pays au clic, fiche de la province au double-clic

**1d. Modes de carte**
- [x] Politique, terrain, population, PIB/hab., idéologie, alliances, relations, ressources, infrastructures, contrôle militaire, stabilité

**1e. Frontières et noms**
- [x] Frontières de pays (épaisses) et de provinces (fines)
- [x] Noms de pays affichés en courbe selon la forme

**1f. Mers**
- [x] Zones maritimes (155 mers et secteurs d'océan, 29 lacs)
- [x] Détroits et canaux stratégiques (Suez, Panama, Ormuz, Malacca, Bosphore…)

- [x] Validation : clic sur une province → panneau d'info

## Étape 2 — Temps et boucle de simulation ✅ (validée le 2026-10-29, v0.2.0)
- [x] `GameClock` : date, heure, pause, 5 vitesses, raccourcis (Espace, +, -)
- [x] Ordonnanceur : abonnements `hourly`, `daily`, `weekly`, `monthly`, `yearly`
- [x] Barre supérieure : date, vitesse, trésorerie, stabilité, soutien populaire, puissance militaire, influence (valeurs « — » en attendant les systèmes)
- [x] Validation : le temps défile, les événements mensuels se déclenchent

## Étape 3 — Les pays en 2026 ✅ (validée le 2026-10-30, v0.3.0)
**3a. Données réelles**
- [x] Population, PIB (FMI 2026), dette (FMI 2025), effectifs militaires (IISS) pour les 199 pays, depuis Wikipédia
- [x] Régimes et organisations au 1er janvier 2026 (ONU, OTAN, UE, G7, G20, BRICS, OCS, UA, Ligue arabe, ASEAN, OPEP, OTSC, Mercosur, CCG, UEEA)
- [x] Population des provinces ajustée au total de chaque pays

**3b. Dirigeants et partis fictifs** (validée le 2026-10-30)
- [x] Générateur de noms par culture (`data/names/cultures/*.json`, 56 cultures) et de noms de partis (`data/names/party_styles/*.json`, 17 langues)
- [x] Dirigeants des 30 pays majeurs écrits à la main, 169 autres générés (même âge, sexe, idéologie) par `tools/leader_gen/`
- [x] Partis au pouvoir et coalitions fictifs, idéologie dominante
- [x] Traits de personnage (tempérament, style, parcours, orientation)
- [x] Fiche du pays : âge des dirigeants, ordre des noms selon la culture

**3c. Drapeaux** (validée le 2026-10-30)
- [x] Drapeaux des 199 pays (SVG au format 4:3) générés par `tools/flag_gen/`
- [x] Drapeau dans la fiche du pays et dans la barre supérieure

**3d. Sélection du pays** (validée le 2026-10-30)
- [x] Écran de sélection sur la carte : liste avec drapeaux, recherche, filtre par difficulté, résumé du pays, défis de départ
- [x] Difficulté calculée (puissance économique et militaire, défis) avec retouches possibles ; 5 niveaux
- [x] Défis écrits pour les 30 pays majeurs (et le Myanmar, le Soudan), défis génériques déduits des données pour les autres
- [x] Entités non reconnues (Chypre du Nord, Somaliland) proposées en mode avancé
- [x] La partie démarre sur le pays choisi, caméra centrée sur sa capitale

- [x] Validation : choisir n'importe quel pays et démarrer la partie

## Étape 4 — Économie 🟨
**4a. Macroéconomie** (validée le 2026-10-30)
- [x] Situation économique réelle au 1er janvier 2026 pour les 199 pays et 143 monnaies (`tools/country_gen/generate_economy.py`)
- [x] PIB par secteur (agriculture, industrie, énergie, services, tech, finance, tourisme, armement)
- [x] Croissance, inflation, chômage, taux directeur (règle de Taylor), banque centrale indépendante ou sous contrôle du joueur
- [x] Monnaie et taux de change, unions monétaires et ancrages
- [x] Dette publique (locale et en devises), notation souveraine (AAA → défaut), taux d'emprunt, crise de la dette, FMI
- [x] Panneau Économie et économie en cours de partie dans la fiche des pays

**4b. Budget de l'État**
- [x] Recettes : impôt sur le revenu (4 tranches), IS, TVA, taxe carbone, douanes, cotisations, taxes sur ressources (taux réels, `tools/country_gen/generate_budget.py`)
- [x] Dépenses : santé, éducation, retraites, chômage, police, justice, défense, recherche, infrastructures, environnement, culture, aide internationale, renseignement, administration
- [x] Effets de chaque ligne en données : croissance, chômage et inflation appliqués ; groupes sociaux, stabilité, recherche, armée et influence calculés, en attente de leurs systèmes
- [x] Déficit → dette ; création monétaire → inflation (banque centrale sous contrôle du gouvernement)
- [x] Règle provisoire de l'IA : dépenses ajustées selon l'évolution de la dette
- [x] Panneau Budget avec aperçu en direct, solde annuel dans la barre supérieure

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

# Bugs connus et dette technique

Priorités : 🔴 bloquant · 🟠 important · 🟢 mineur

| Priorité | Description | Étape | Statut |
|---|---|---|---|
| 🟢 | Échap quitte la partie sans confirmation. | 13 | Ouvert |
| 🟢 | « Charger » reste désactivé tant que la sauvegarde n'existe pas. | 14 | Ouvert |
| 🟢 | Le chargement des JSON et CSV dans un jeu exporté (fichier `.pck`) n'a pas encore été vérifié. | 14 | Ouvert |
| 🟠 | Découpage déséquilibré : 250 provinces au Royaume-Uni (Londres déjà regroupée), 193 en Slovénie, 68 à Malte, contre 51 en Chine. D'autres regroupements possibles via `province_merges`. | 1 | Ouvert |
| 🟠 | Contrôle partiel impossible à la province : Zaporijjia et Kherson restent sous contrôle ukrainien. Les autres conflits de 2026 (Soudan, Myanmar, Yémen, Sahel…) ne sont pas encore représentés. | 3 / 7 | Ouvert |
| 🟢 | Terrain estimé (régions géographiques + latitude). | 1 | Ouvert |
| 🟢 | Quelques noms français de Natural Earth sont approximatifs ; corrections possibles dans `tools/map_gen/config.json`. | 1 | Ouvert |
| 🟢 | La carte demande une carte graphique acceptant les textures 16384 px et ~270 Mo de mémoire vidéo ; chargement ~3 s, rechargée à chaque nouvelle partie. | 1 | Ouvert |
| 🟢 | Les noms de pays voisins peuvent se chevaucher (pas encore d'évitement des collisions). | 13 | Ouvert |
| 🟢 | En zoom maximal, les contours suivent la précision de l'image (~2 km par pixel) : lissés mais encore un peu anguleux. | 1 | Ouvert |
| 🟢 | Secteurs d'océan de tailles inégales ; rives du détroit de Taïwan trop larges (provinces de l'intérieur incluses). | 1 | Ouvert |
| 🟢 | Puissance militaire et influence masquées dans la barre supérieure jusqu'aux étapes militaire et diplomatie. | 6–7 | Ouvert |
| 🟢 | Population de l'Ukraine (28,7 millions, territoire contrôlé) répartie aussi sur les provinces occupées ; PIB et dette estimés pour quelques pays sans source (Corée du Nord, Somaliland, Chypre du Nord, Syrie…). | 3 | Ouvert |
| 🟢 | Pas encore de portraits des personnages (portraits génériques prévus avec l'interface). | 13 | Ouvert |
| 🟢 | Une seule culture de noms par pays : les pays multilingues (Belgique, Suisse, Bosnie-Herzégovine…) ont des noms d'une seule langue. Les noms de partis génériques (style international) se répètent d'un pays à l'autre. | 3 | Ouvert |
| 🟢 | Années de naissance approximatives pour quelques dirigeants peu documentés (Tonga, Saint-Marin, Burundi, Guinée-Bissau…) ; gouvernements de transition au 1er janvier 2026 (Pays-Bas, Bulgarie, Thaïlande, Kosovo) à revérifier. | 3 | Ouvert |
| 🟢 | Drapeaux tous au format 4:3 : les proportions officielles (Suisse carrée, Qatar allongé, Népal) ne sont pas respectées. Un nouveau drapeau demande d'activer les mipmaps dans son fichier `.import`. | 3 | Ouvert |
| 🟢 | Difficulté approchée : elle ne tient compte que du PIB, de l'armée et des défis ; beaucoup de petits pays sont « difficiles ». À revoir avec l'économie, la stabilité et la diplomatie. | 4–6 | Ouvert |
| 🟢 | Les défis de départ sont descriptifs : ils n'ont pas encore d'effet en jeu. | 4–9 | Ouvert |
| 🟢 | Charge d'intérêts de départ plafonnée à 6 % du PIB (Brésil, Égypte, pays à taux très élevés) : moins lourde que la réalité pour quelques pays. | 4a | Ouvert |
| 🟢 | Les pays de l'IA appellent le FMI dès qu'ils font défaut (règle provisoire en attendant l'IA de l'étape 12). | 12 | Ouvert |
| 🟢 | Le mode de carte PIB/hab. utilise encore les chiffres de départ, pas ceux de la simulation. | 13 | Ouvert |
| 🟢 | Inflation de départ : dernière année connue sur Wikipédia (2024) sauf corrections fin 2025 ; taux du shilling du Somaliland saisi à la main ; 56 pays sans note officielle (note estimée). | 4a | Ouvert |
| 🟢 | Budgets en partie estimés : la répartition des recettes entre impôts, la santé, les retraites et les petits postes suivent des profils par niveau de revenu (valeurs saisies pour les grands pays) ; « administration et autres » regroupe le reste (prestations familiales, logement…). | 4b | Ouvert |
| 🟢 | La dette de l'Ukraine approche encore 190 % du PIB en 2035 (déficit de guerre financé par emprunt ; l'aide étrangère n'existe pas encore). | 6 | Ouvert |
| 🟢 | Les champs du panneau Budget affichent les décimales avec un point, même en français. | 13 | Ouvert |
| 🟢 | Ressources : consommations estimées pour le charbon, les métaux et les semi-conducteurs (grands consommateurs saisis, reste selon le PIB industriel) ; blé par habitant ; données de quelques années (pétrole 2023, blé 2022, uranium 2022). Hors des régions saisies, la place des ressources dans les provinces est approchée. | 4c1 | Ouvert |
| 🟢 | Routes des détroits estimées ; la fermeture de Malacca bloque des exportations au lieu de les rallonger. | 4c1 | Ouvert |
| 🟢 | La fermeture des détroits n'est possible qu'en version de développement (blocus militaires à l'étape 7, événements à l'étape 9). | 7 / 9 | Ouvert |
| 🟢 | Échanges estimés par un modèle gravitaire : des écarts avec la réalité subsistent (ex. la Russie fait encore 46 % de son commerce avec la Chine, l'Allemagne achète son gaz surtout aux États-Unis). Le commerce de services n'est pas distingué. | 4c2 | Ouvert |
| 🟢 | Les pays de l'IA ne prennent encore aucune mesure commerciale (ni riposte aux surtaxes) : étape 12. | 12 | Ouvert |
| 🟢 | Parc de départ placé selon la population et le relief : des centrales peuvent se retrouver dans une capitale (deux centrales nucléaires à Paris). Seuls les centrales, les mines et un port par pays sont placés au départ. | 4d1 | Ouvert |
| 🟢 | Le charbon se stabilise environ 25 % au-dessus de son prix de départ (forte demande d'électricité de la Chine et de l'Inde). | 4d1 | Ouvert |
| 🟠 | Un mois de simulation prend environ 340 ms (marché des ressources, budget, électricité) : à-coup sensible en vitesse maximale ; calculs à étaler sur plusieurs images ou fils de calcul. | 15 | Ouvert |
| 🟢 | Parts publiques en partie estimées par des règles ; les pays de l'IA ne nationalisent ni ne privatisent (étape 12). Les effets sur les groupes sociaux sont décrits mais appliqués à l'étape 5. | 4d2 | Ouvert |
| 🟢 | Fonds souverains : rendement fixe, pas encore de placements ciblés par pays (diplomatie, étape 6). | 6 | Ouvert |
| 🟢 | Société estimée : parts des groupes calculées par règles ; popularité saisie pour 30 grands pays seulement ; place de la religion estimée pour une quarantaine de pays absents de l'enquête Gallup ; micro-États souvent sur valeurs par défaut. | 5a | Ouvert |
| 🟢 | Sans action du joueur, la stabilité dérive encore jusqu'à ±14 points en 10 ans dans quelques pays (Timor oriental, Angola, Palestine) sous l'effet de l'économie. | 5a | Ouvert |
| 🟢 | Le panneau Société recouvre la légende de la carte. | 13 | Ouvert |
| 🟢 | Parlements : 132 pays sur règles (taille, majorité, opposition et date du dernier scrutin estimées) ; pour les 67 pays saisis, sièges arrondis et petits partis regroupés ; sondages de janvier 2026 saisis pour une vingtaine de pays seulement. Pas encore de chambre haute. | 5b | Ouvert |
| 🟢 | Les sondages incluant des indécis sont ramenés à 100 % (au Japon, le parti au pouvoir part à 44 %). | 5b | Ouvert |
| 🟢 | Le Chili garde sa chambre et son gouvernement sortants (élections de novembre et décembre 2025 non reprises). | 5c1 | Ouvert |
| 🟢 | Scrutin à deux tours (France) traité comme un scrutin majoritaire à un tour : pas de front républicain, le premier parti peut obtenir une large majorité. | 5c1 | Ouvert |
| 🟢 | Peu d'alternances (une cinquantaine en 10 ans dans le monde) : les sondages bougent peu sans action du joueur ; à revoir avec la campagne (5c2) et les crises (5g). | 5c1 | Ouvert |
| 🟢 | En régime présidentiel, le nouveau président gouverne avec son seul parti (pas de coalition présidentielle). | 5c1 | Ouvert |
| 🟢 | Fraude découverte : scandale sur la stabilité et la légitimité, mais pas encore de manifestations ni de contestation des résultats (5g). | 5c2 | Ouvert |
| 🟢 | Situation des lois en 2026 approchée par règles : listes de pays pour les cas connus (peine de mort, mariage homosexuel, cannabis, service militaire…), valeur par défaut ailleurs. Les pays de l'IA ne changent pas encore de lois (étape 12). | 5d | Ouvert |
| 🟢 | La barre supérieure est pleine à 1600 px de large : elle déborde sur les écrans plus étroits (refonte prévue à l'étape 13). | 13 | Ouvert |
| 🟢 | Les ministres de l'IA ne sont jamais remaniés volontairement (seulement après scandale ou démission). | 12 | Ouvert |
| 🟢 | Les guerres civiles n'ont pas encore de fronts ni de provinces tenues par les rebelles (étape 7) ; elles finissent par une chance mensuelle quand la stabilité remonte. | 7 | Ouvert |
| 🟢 | Une désinformation démasquée contre un pays étranger ne dégrade pas encore les relations (diplomatie, étape 6) ; les pays de l'IA n'utilisent ni propagande ni désinformation (étape 12). | 6 / 12 | Ouvert |
| 🟢 | Relations de départ estimées par règles hors des 183 paires saisies ; quelques valeurs peuvent surprendre entre petits pays éloignés. | 6a | Ouvert |
| 🟢 | Seul le traité de libre-échange a un effet économique ; défense mutuelle, accès et coopération militaires, renseignement et frontière ouverte ne jouent que sur les relations jusqu'aux étapes 7, 10 et 11. Les pays de l'IA ne proposent pas encore de traités (étape 12). | 6b | Ouvert |

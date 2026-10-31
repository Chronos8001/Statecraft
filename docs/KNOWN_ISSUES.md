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
| 🟢 | Modes relations et stabilité neutres ; ressources vides. Ils se rempliront avec les étapes 4c, 5 et 6. | 4–6 | Ouvert |
| 🟢 | Les noms de pays voisins peuvent se chevaucher (pas encore d'évitement des collisions). | 13 | Ouvert |
| 🟢 | En zoom maximal, les contours suivent la précision de l'image (~2 km par pixel) : lissés mais encore un peu anguleux. | 1 | Ouvert |
| 🟢 | Secteurs d'océan de tailles inégales ; rives du détroit de Taïwan trop larges (provinces de l'intérieur incluses). | 1 | Ouvert |
| 🟢 | Les ressources de la barre supérieure (trésorerie, stabilité, soutien, puissance militaire, influence) affichent « — » jusqu'aux étapes économie, politique, militaire et diplomatie. | 4–7 | Ouvert |
| 🟢 | Population de l'Ukraine (28,7 millions, territoire contrôlé) répartie aussi sur les provinces occupées ; PIB et dette estimés pour quelques pays sans source (Corée du Nord, Somaliland, Chypre du Nord, Syrie…). | 3 | Ouvert |
| 🟢 | Pas encore de portraits des personnages (portraits génériques prévus avec l'interface). | 13 | Ouvert |
| 🟢 | Seuls les partis au pouvoir et leurs partenaires existent ; l'opposition, les scores et les sondages arrivent avec la politique intérieure. | 5 | Ouvert |
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

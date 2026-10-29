# Bugs connus et dette technique

Priorités : 🔴 bloquant · 🟠 important · 🟢 mineur

| Priorité | Description | Étape | Statut |
|---|---|---|---|
| 🟢 | Les drapeaux référencés dans `countries.json` (`flags/*.png`) n'existent pas encore. | 3 | Ouvert |
| 🟢 | « Nouvelle partie » ouvre directement la carte, sans choix du pays. Échap quitte la partie sans confirmation. | 3 / 13 | Ouvert |
| 🟢 | « Charger » reste désactivé tant que la sauvegarde n'existe pas. | 14 | Ouvert |
| 🟢 | Le chargement des JSON et CSV dans un jeu exporté (fichier `.pck`) n'a pas encore été vérifié. | 14 | Ouvert |
| 🟠 | Découpage déséquilibré : 250 provinces au Royaume-Uni (Londres déjà regroupée), 193 en Slovénie, 68 à Malte, contre 51 en Chine. D'autres regroupements possibles via `province_merges`. | 1 | Ouvert |
| 🟠 | Contrôle partiel impossible à la province : Zaporijjia et Kherson restent sous contrôle ukrainien. Les autres conflits de 2026 (Soudan, Myanmar, Yémen, Sahel…) ne sont pas encore représentés. | 3 / 7 | Ouvert |
| 🟢 | Population totale de certains pays issue de valeurs Wikidata anciennes (ex. Inde ~1,33 milliard) ; total mondial ~7,9 milliards. | 3 | Ouvert |
| 🟢 | Terrain estimé (régions géographiques + latitude) ; ressources vides jusqu'au commerce. | 4c | Ouvert |
| 🟢 | Quelques noms français de Natural Earth sont approximatifs ; corrections possibles dans `tools/map_gen/config.json`. | 1 | Ouvert |
| 🟢 | La carte demande une carte graphique acceptant les textures 16384 px et ~270 Mo de mémoire vidéo ; chargement ~3 s, rechargée à chaque nouvelle partie. | 1 | Ouvert |
| 🟢 | Modes PIB/hab., idéologie et alliances limités aux 5 pays détaillés ; relations et stabilité neutres ; ressources vides. Ils se rempliront avec les étapes 3, 4c, 5 et 6. | 3–6 | Ouvert |
| 🟢 | Les noms de pays voisins peuvent se chevaucher (pas encore d'évitement des collisions). | 13 | Ouvert |
| 🟢 | En zoom maximal, les contours suivent la précision de l'image (~2 km par pixel) : lissés mais encore un peu anguleux. | 1 | Ouvert |
| 🟢 | Secteurs d'océan de tailles inégales ; rives du détroit de Taïwan trop larges (provinces de l'intérieur incluses). | 1 | Ouvert |

# Bugs connus et dette technique

Priorités : 🔴 bloquant · 🟠 important · 🟢 mineur

| Priorité | Description | Étape | Statut |
|---|---|---|---|
| 🟢 | Les drapeaux référencés dans `countries.json` (`flags/*.png`) n'existent pas encore. | 3 | Ouvert |
| 🟢 | « Nouvelle partie » ouvre directement la carte, sans choix du pays. Échap quitte la partie sans confirmation. | 3 / 13 | Ouvert |
| 🟢 | « Charger » reste désactivé tant que la sauvegarde n'existe pas. | 14 | Ouvert |
| 🟢 | Le chargement des JSON et CSV dans un jeu exporté (fichier `.pck`) n'a pas encore été vérifié. | 14 | Ouvert |
| 🟠 | Découpage déséquilibré : 282 provinces au Royaume-Uni, 193 en Slovénie, 68 à Malte, contre 51 en Chine. Envisager de regrouper les plus petites unités. | 1 | Ouvert |
| 🟠 | Contrôle partiel impossible à la province : Zaporijjia et Kherson restent sous contrôle ukrainien. Les autres conflits de 2026 (Soudan, Myanmar, Yémen, Sahel…) ne sont pas encore représentés. | 3 / 7 | Ouvert |
| 🟢 | Population totale de certains pays issue de valeurs Wikidata anciennes (ex. Inde ~1,33 milliard) ; total mondial ~7,9 milliards. | 3 | Ouvert |
| 🟢 | Terrain estimé (régions géographiques + latitude) ; ressources vides jusqu'au commerce. | 4c | Ouvert |
| 🟢 | Quelques noms français de Natural Earth sont approximatifs ; corrections possibles dans `tools/map_gen/config.json`. | 1 | Ouvert |
| 🟢 | Carte crénelée en zoom arrière (pas de mipmaps) et pixelisée en zoom maximal ; les frontières lissées arrivent avec l'étape 1e. | 1e | Ouvert |
| 🟢 | La carte demande une carte graphique acceptant les textures 16384 px et ~270 Mo de mémoire vidéo ; chargement ~3 s, rechargée à chaque nouvelle partie. | 1 | Ouvert |

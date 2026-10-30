# Générateur des drapeaux

Écrit le drapeau de chaque pays de `data/countries/countries.json` dans `assets/flags/<TAG>.svg`.

## Sources

| Source | Licence | Pays |
|---|---|---|
| Paquet npm [flag-icons](https://github.com/lipis/flag-icons), version fixée dans `config.json` | MIT (notice copiée dans `assets/flags/LICENSE-flag-icons.txt`) | Tous, sauf ci-dessous |
| [Wikimedia Commons](https://commons.wikimedia.org/) | Domaine public | Afghanistan (drapeau de l'Émirat islamique, en usage de fait au 1er janvier 2026), Chypre du Nord, Somaliland |

## Fichiers

| Fichier | Rôle |
|---|---|
| `config.json` | Version du paquet, taille de sortie, correspondance code du pays → code ISO 3166-1 alpha-2 (`iso2`), drapeaux pris sur Wikimedia Commons (`commons`). |
| `cache/` | Téléchargements (non versionné, ignoré par Godot). |
| `assets/flags/<TAG>.svg` | Sortie : un drapeau par pays. Les fichiers des pays disparus sont supprimés. |

## Lancer

```sh
python tools/flag_gen/generate_flags.py
godot --headless --path . --import
```

## Format

Tous les drapeaux sont au format 4:3, rendus en 320 × 240 à l'import. Ceux qui n'ont pas ces proportions sont recadrés au centre. Si le recadrage couperait une inscription, on indique une couleur de fond dans `commons` et le cadre est agrandi avec cette couleur au lieu d'être recadré :

```json
"AFG": {"file": "Flag_of_the_Taliban.svg", "background": "#ffffff"}
```

Les mipmaps sont activées dans les fichiers `.import` des drapeaux pour qu'ils restent nets en petit. Pour un nouveau pays, après le premier import, passer `mipmaps/generate` à `true` dans son `.svg.import`.

## Ajouter ou remplacer un drapeau

- Nouveau pays reconnu par l'ISO : ajouter son code dans `iso2`.
- Pays absent de flag-icons ou drapeau différent de la situation de fait : ajouter le nom du fichier Wikimedia Commons dans `commons`.
- Un pays peut aussi indiquer son propre fichier dans les données (`"flag": "res://…"`, `.svg` ou `.png`), ce qui sert aux mods.

# Générateur des dirigeants et partis

Crée les dirigeants et partis fictifs des pays qui ne sont pas écrits à la main, avec le générateur de noms du jeu (`sim/names/name_generator.gd`).

## Fichiers

| Fichier | Rôle |
|---|---|
| `config.json` | Situation réelle au 1er janvier 2026 de chaque pays généré : culture, idéologie dominante, chef de l'État, chef du gouvernement, partis au pouvoir. Aucun vrai nom. |
| `data/countries/politics.json` | Les 30 pays majeurs, écrits à la main (avec `data/names/characters.json` et `data/names/parties.json`). Ne pas les mettre dans `config.json`. |
| `data/countries/politics_generated.json` | Sortie : champs politiques des pays générés (fusionnés avec `countries.json` au chargement). |
| `data/names/generated.json` | Sortie : personnages et partis générés. |

## Lancer

```sh
godot --headless --path . --import
godot --headless --path . -s tools/leader_gen/generate_leaders.gd
```

Le résultat est stable : la graine dépend uniquement du pays (`seed_salt` + code du pays). Modifier un pays ne change pas les autres, sauf si un nom de parti ou de personne devient pris.

## Décrire un pays

```json
"NLD": {"culture": "dutch", "ideology": "liberal",
        "head_of_state": [1967, "male", "monarchist", "royal"],
        "head_of_government": [1957, "male", "centrist", "np", "security_services"],
        "parties": ["liberal", "christian_democrat", "conservative"]}
```

- Dirigeant : `[année de naissance, sexe, idéologie, options…]`, ou `"@GBR"` pour reprendre le chef de l'État d'un autre pays (royaumes du Commonwealth, Andorre).
- Options : index du parti du dirigeant (`0` = parti au pouvoir), `"np"` (sans parti), `"culture=anglo"` (autre culture), ou un trait imposé (`"royal"`, `"military_officer"`…). Un monarque (`royal`) n'a pas de parti par défaut.
- Sans `head_of_government`, le chef de l'État dirige aussi le gouvernement et appartient au parti au pouvoir (sauf `"np"`).
- `parties` : idéologies des partis au pouvoir ; le premier gouverne, les suivants sont ses partenaires de coalition. Liste vide : pas de parti au pouvoir.

## Règles de noms

- Prénoms et noms tirés dans `data/names/cultures/`, noms de partis dans `data/names/party_styles/` selon le groupe de l'idéologie (`party_group` dans `data/ideologies/`).
- Pas d'homonyme dans le monde, pas deux fois le même nom de famille dans un pays, aucun nom de parti déjà pris si un autre est disponible.
- `forbidden_full_names` : noms exclus parce qu'ils rappellent des personnes réelles connues.

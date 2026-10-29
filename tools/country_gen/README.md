# Générateur des données des pays

Complète `data/countries/countries.json` avec les données réelles des pays au 1er janvier 2026.

## Sources

| Donnée | Source |
|---|---|
| Population | Wikipédia, *List of countries and dependencies by population* (chiffres officiels ou ONU) |
| PIB nominal | Wikipédia, *List of countries by GDP (nominal)* (FMI 2026, Banque mondiale en secours) |
| Dette publique | Wikipédia, *List of countries by government debt* (dette brute 2025, FMI) |
| Effectifs militaires | Wikipédia, *List of countries by number of military and paramilitary personnel* (IISS) |
| Régime, organisations | `config.json` (situation au 1er janvier 2026, saisie à la main) |

Les pages sont mises en cache dans `tools/country_gen/cache/` (non versionné). La population et le PIB des territoires rattachés (Hong Kong, Groenland, Porto Rico…) sont ajoutés à leur pays.

## Lancer

```sh
python tools/country_gen/generate_countries.py
python tools/map_gen/generate_map.py   # répartit la nouvelle population entre les provinces
```

Le script liste les lignes de Wikipédia non reconnues et les valeurs estimées (médianes) faute de source.

## Réglages (`config.json`)

- `regimes` : régime de chaque pays.
- `organization_members` et `not_un_members` : membres des organisations internationales.
- `aliases` : noms alternatifs utilisés par Wikipédia.
- `dependency_owners` : territoires rattachés à un pays.
- `no_army` : pays sans armée.
- `manual_values` : valeurs corrigées à la main (PIB, dette).

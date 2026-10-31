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

Les dirigeants, partis et idéologies ne sont pas dans `countries.json` : voir `tools/leader_gen/`.

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

## Données macroéconomiques (`generate_economy.py`)

Écrit `data/countries/economy.json` (fusionné avec `countries.json` au chargement) et `data/currencies/currencies.json`. Les pages Wikipédia sont lues **dans leur version du 1er janvier 2026**.

| Donnée | Source |
|---|---|
| Croissance réelle | *List of countries by real GDP growth rate* (FMI) |
| Inflation | *List of countries by inflation rate* (dernière année connue), corrigée à la main fin 2025 pour la Turquie, l'Argentine, le Nigeria, l'Égypte, le Ghana et la Russie (`manual_inflation`) |
| Chômage | *List of countries by unemployment rate* (FMI, sinon Banque mondiale, sinon CIA) |
| Taux directeurs | *List of countries by central bank interest rates* ; estimés (inflation + taux réel neutre) quand ils manquent |
| Note souveraine | *List of countries by credit rating* : S&P, puis Fitch, puis Moody's ; notes retirées ignorées ; le jeu estime les autres |
| Solde budgétaire | *List of countries by government budget* (FMI, prêt/emprunt net en % du PIB) |
| Secteurs | *List of countries by GDP sector composition* (agriculture, industrie, services) et rentes pétrolières, gazières et charbonnières |
| Taux de change | currency-api au 1er janvier 2026 (`exchange_rates_url`) |

Réglages (`economy_config.json`) :
- `currencies`, `currency_issuers`, `pegs` : monnaie de chaque pays, pays émetteur, ancrages (dollar, euro, roupie, rand) ;
- `dependent_central_banks`, `independent_central_banks`, `dependent_regimes` : banques centrales sous contrôle du gouvernement ;
- `inflation_targets` : cibles d'inflation ;
- `sectors` : règles qui détachent l'énergie, l'armement, la technologie, la finance et le tourisme de l'industrie et des services ;
- `foreign_debt` : part de la dette publique en devises.

```sh
python tools/country_gen/generate_economy.py
```

`country_lookup.py` regroupe le code commun aux deux outils (pages Wikipédia, noms des pays).

## Budget de l'État (`generate_budget.py`)

Écrit `data/countries/budget.json` (fusionné avec `countries.json`) : taux et recettes de 7 impôts, dépenses de 14 postes en % du PIB. Pages Wikipédia dans leur version du 1er janvier 2026.

| Donnée | Source |
|---|---|
| Recettes et dépenses totales | *List of countries by government budget* (FMI) |
| Taux de l'impôt sur le revenu (plus bas, plus haut), des sociétés, TVA | *List of countries by tax rates* ; tranches intermédiaires interpolées |
| Défense | *List of countries with highest military expenditures* (% du PIB) |
| Éducation | *List of countries by spending on education as percentage of GDP* |

Le reste vient de `budget_config.json` : répartition des recettes entre impôts selon le niveau de revenu (les rentes pétrolières alimentent les taxes sur les ressources), prix du carbone, droits de douane, taux de cotisations, profils de dépenses par niveau de revenu et valeurs saisies pour les grands pays (santé, retraites, aide internationale…). Le poste « administration et autres » complète jusqu'au total du FMI ; le jeu ajuste ensuite toutes les dépenses pour retrouver exactement le solde de départ.

```sh
python tools/country_gen/generate_budget.py
```

## Ressources stratégiques (`generate_resources.py`)

Écrit `data/countries/resources.json` (production et consommation des 10 ressources échangées, eau renouvelable et taux de prélèvement) et `data/provinces/resources.json` (richesse de 1 à 10 des provinces productrices). Pages Wikipédia dans leur version du 1er janvier 2026.

| Donnée | Source |
|---|---|
| Pétrole, gaz | *List of countries by oil production / consumption*, *natural gas production / consumption* |
| Charbon | *List of countries by coal production* ; consommation saisie pour les grands consommateurs |
| Uranium | *List of countries by uranium production* ; besoins des réacteurs d'après *Nuclear power by country* |
| Acier | *List of countries by steel production* (consommation = production - exportations nettes) |
| Blé | *List of countries by wheat production* ; consommation par habitant (`wheat_per_capita`) |
| Eau | *List of countries by total renewable water resources* |
| Terres rares, lithium, cobalt, semi-conducteurs | `resources_config.json` (USGS 2024, production de puces par lieu de fabrication) |

La consommation mondiale de chaque ressource est ramenée à sa production (marché équilibré au départ). La production est répartie entre les provinces d'après les régions saisies dans `regions` (noms anglais des provinces), sinon selon le terrain et la surface (ressources extraites) ou la population (acier, semi-conducteurs).

```sh
python tools/country_gen/generate_resources.py
```

class_name InvestmentState
extends RefCounted
## Propriété publique des secteurs, investissements étrangers et fonds souverain d'un pays.
## Les valeurs de départ sont gardées : les effets se mesurent par rapport à elles.

const OPEN := "open"
const SCREENING := "screening"
const RESTRICTED := "restricted"
const POLICIES := [OPEN, SCREENING, RESTRICTED]

## Part publique de chaque secteur (0 à 1).
var public_ownership: Dictionary = {}
var start_public_ownership: Dictionary = {}
## IDE entrants (% du PIB par an) et politique d'ouverture.
var fdi_inflow: float = 0.0
var start_fdi_inflow: float = 0.0
var fdi_policy: String = OPEN
var start_fdi_policy: String = OPEN
## Références de l'attractivité.
var start_growth: float = 0.0
var start_rating: int = 0
var start_corporate_tax: float = 0.0
## Mois pendant lesquels une expropriation fait encore fuir les investisseurs.
var expropriation_months: int = 0
## Actifs du fonds souverain (milliards de dollars).
var sovereign_fund: float = 0.0

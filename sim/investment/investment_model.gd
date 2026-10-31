class_name InvestmentModel
extends RefCounted
## Formules de la propriété publique et des investissements étrangers, sans état.

const PERCENT := 100.0


## Part de l'économie passée au public (ou au privé si négatif) depuis le départ : Σ part du secteur × écart.
static func public_shift(sectors: Dictionary, ownership: Dictionary, start_ownership: Dictionary) -> float:
	var shift := 0.0
	for sector_id: Variant in sectors.keys():
		shift += float(sectors[sector_id]) * (float(ownership.get(sector_id, 0.0))
			- float(start_ownership.get(sector_id, 0.0)))
	return shift


## Valeur des entreprises d'un secteur (milliards de dollars) : production × multiple.
static func company_value(sector_share: float, gdp_usd: float, multiple: float) -> float:
	return sector_share * gdp_usd * multiple


## IDE visés (% du PIB) : départ × ouverture × attractivité (croissance, note, impôt sur les sociétés)
## × fuite après une expropriation.
static func fdi_target(investment: InvestmentState, growth: float, rating: int, corporate_tax: float,
		settings: Dictionary) -> float:
	var factors: Dictionary = settings.get("fdi_policy_factors", {})
	var start_factor := float(factors.get(investment.start_fdi_policy, 1.0))
	var policy := float(factors.get(investment.fdi_policy, 1.0)) / start_factor if start_factor > 0.0 else 1.0
	var weights: Dictionary = settings.get("fdi_attractiveness", {})
	var score := float(weights.get("growth", 0.0)) * (growth - investment.start_growth) \
		+ float(weights.get("rating", 0.0)) * float(rating - investment.start_rating) \
		+ float(weights.get("corporate_tax", 0.0)) * (corporate_tax - investment.start_corporate_tax)
	var flight := float((settings.get("expropriation", {}) as Dictionary).get("fdi_factor", 1.0)) \
		if investment.expropriation_months > 0 else 1.0
	return investment.start_fdi_inflow * policy * exp(score) * flight

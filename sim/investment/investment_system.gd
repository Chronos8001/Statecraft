class_name InvestmentSystem
extends SimSystem
## Entreprises publiques, investissements étrangers et fonds souverains, une fois par mois, avant le budget :
## bénéfices des entreprises passées au public (recettes) et perte d'efficacité, IDE qui suivent
## l'attractivité et soutiennent la croissance, rendement du fonds souverain.

const PRIORITY := -12
const EVENT_NATIONALIZED := &"nationalized"
const EVENT_EXPROPRIATED := &"expropriated"
const EVENT_PRIVATIZED := &"privatized"


func get_id() -> StringName:
	return &"investment"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.investment_settings.is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		update_country(state.countries[tag], state)


static func update_country(country: CountryState, state: SimState) -> void:
	var settings := state.investment_settings
	var economy := country.economy
	var investment := economy.investment
	var shift := InvestmentModel.public_shift(economy.sectors, investment.public_ownership,
		investment.start_public_ownership)
	economy.public_revenue = float(settings.get("public_profit_rate", 0.0)) * shift * EconomyModel.PERCENT
	if investment.expropriation_months > 0:
		investment.expropriation_months -= 1
	var corporate_tax := float(economy.budget.tax_rates.get("corporate_tax", investment.start_corporate_tax))
	var target := InvestmentModel.fdi_target(investment, economy.growth, economy.rating, corporate_tax, settings)
	investment.fdi_inflow += (target - investment.fdi_inflow) * float(settings.get("fdi_adjustment", 1.0))
	var growth := float(settings.get("fdi_growth_effect", 0.0)) * (investment.fdi_inflow - investment.start_fdi_inflow) \
		- float(settings.get("public_inefficiency", 0.0)) * shift
	var limit := float(settings.get("max_economic_effect", INF))
	economy.investment_growth = clampf(growth, -limit, limit)
	investment.sovereign_fund *= 1.0 + float(settings.get("fund_return", 0.0)) / EconomyModel.PERCENT \
		/ EconomyModel.MONTHS_PER_YEAR


## Valeur (milliards de dollars) d'une variation de la part publique d'un secteur.
static func ownership_value(country: CountryState, state: SimState, sector: String, change: float) -> float:
	return InvestmentModel.company_value(float(country.economy.sectors.get(sector, 0.0)),
		TradeSystem.current_gdp(state, country.tag), float(state.investment_settings.get("valuation_multiple", 0.0))) \
		* absf(change)


## Ajoute (ou retire si négatif) une somme en dollars à la dette du pays, au taux de change du jour.
## Ce qui dépasse la dette existante va au fonds souverain.
static func add_debt_usd(country: CountryState, state: SimState, amount_usd: float) -> void:
	var economy := country.economy
	var currency := state.get_currency(economy.currency)
	var fx := currency.fx_factor() if currency != null else 1.0
	if amount_usd >= 0.0:
		economy.local_debt += amount_usd * fx
		return
	var repay := -amount_usd * fx
	var from_local := minf(repay, economy.local_debt)
	economy.local_debt -= from_local
	repay -= from_local
	var from_foreign := minf(repay / fx, economy.foreign_debt)
	economy.foreign_debt -= from_foreign
	repay -= from_foreign * fx
	if repay > 0.0:
		economy.investment.sovereign_fund += repay / fx

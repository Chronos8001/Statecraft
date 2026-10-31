class_name BudgetSystem
extends SimSystem
## Budget de l'État, une fois par mois, avant l'économie :
##   1. les pays de l'IA corrigent leurs dépenses selon l'évolution de leur dette (règle provisoire) ;
##   2. recettes, solde primaire et effets du budget de chaque pays, utilisés ensuite par l'économie.

const PRIORITY := -10
const RESOURCE_TAXES := "resource_taxes"
const CUSTOMS := "customs"


func get_id() -> StringName:
	return &"budget"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.budget_definitions.is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		if country.tag != str(state.player_tag):
			adjust_ai_budget(country, state)
		update_budget(country, state)


## Recettes, solde primaire et effets du budget, recopiés dans l'économie du pays.
static func update_budget(country: CountryState, state: SimState) -> void:
	var economy := country.economy
	var budget := economy.budget
	var taxes: Dictionary = state.budget_definitions.get("taxes", {})
	var spending: Dictionary = state.budget_definitions.get("spending", {})
	var settings: Dictionary = state.budget_definitions.get("settings", {})
	budget.revenues = BudgetModel.revenues(budget, taxes, settings.get("income_bracket_weights", []))
	# Les taxes sur les ressources suivent la valeur de la production (prix et volumes).
	if budget.revenues.has(RESOURCE_TAXES):
		budget.revenues[RESOURCE_TAXES] = float(budget.revenues[RESOURCE_TAXES]) * economy.resource_price_index
	# Surtaxes et accords quittés rapportent des droits de douane en plus (ou en moins).
	if budget.revenues.has(CUSTOMS):
		budget.revenues[CUSTOMS] = maxf(float(budget.revenues[CUSTOMS]) + economy.trade_customs, 0.0)
	economy.primary_balance = budget.total_revenue() + economy.public_revenue - budget.total_spending() \
		- economy.project_spending + economy.austerity
	budget.effects = BudgetModel.effects(budget, taxes, spending, settings)
	economy.budget_growth = float(budget.effects.get("growth", 0.0))
	economy.budget_unemployment = float(budget.effects.get("unemployment", 0.0))
	economy.budget_inflation = float(budget.effects.get("inflation", 0.0))


## Règle de l'IA : viser un solde primaire d'autant plus élevé que la dette a monté depuis le départ
## (et l'inverse), en ajustant toutes les dépenses dans la même proportion, par petits pas.
## Pendant un programme du FMI, l'effort budgétaire exigé suffit.
static func adjust_ai_budget(country: CountryState, state: SimState) -> void:
	var economy := country.economy
	var currency := state.get_currency(economy.currency)
	if currency == null or economy.in_imf_program():
		return
	var ai: Dictionary = (state.budget_definitions.get("settings", {}) as Dictionary).get("ai", {})
	var budget := economy.budget
	var total := budget.total_spending()
	if total <= 0.0:
		return
	var debt_change := (economy.debt_ratio(currency) - economy.start_debt_ratio) * EconomyModel.PERCENT
	var desired := economy.start_primary_balance + float(ai.get("debt_response", 0.0)) * debt_change
	var step := float(ai.get("max_adjustment_per_year", 0.0)) / EconomyModel.MONTHS_PER_YEAR
	var adjustment := clampf(desired - economy.primary_balance, -step, step)
	var floor_share := float(ai.get("min_spending_share", 0.0))
	var scale := 1.0 - adjustment / total
	for line_id: Variant in budget.spending.keys():
		var minimum := float(budget.start_spending.get(line_id, 0.0)) * floor_share
		budget.spending[line_id] = maxf(float(budget.spending[line_id]) * scale, minimum)


## La création monétaire n'est possible que si le gouvernement contrôle sa propre banque centrale.
static func can_print_money(state: SimState, tag: String) -> bool:
	var country := state.get_country(tag)
	if country == null:
		return false
	var currency := state.get_currency(country.economy.currency)
	return currency != null and not currency.independent and not currency.is_pegged() and currency.issuer == tag

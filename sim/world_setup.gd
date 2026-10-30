class_name WorldSetup
extends RefCounted
## Crée l'état des pays et des monnaies au début de la partie, à partir des données chargées.
## Le modèle est calé pour que chaque économie parte à l'équilibre : taux neutres et écart de note
## propres à chaque pays reprennent la situation réelle du 1er janvier 2026.

const BILLION := 1.0e9


## budget_definitions : {taxes, spending, settings} (catégories budget_taxes, budget_spending, defines.budget).
static func populate(state: SimState, countries: Dictionary, currencies: Dictionary, settings: Dictionary,
		budget_definitions: Dictionary = {}) -> void:
	state.economy_settings = settings
	state.budget_definitions = budget_definitions
	state.countries.clear()
	state.currencies.clear()
	var ratings := CreditRating.new(settings)
	var tags: Array = countries.keys()
	tags.sort()

	for currency_id: String in currencies.keys():
		state.currencies[currency_id] = _create_currency(currency_id, currencies[currency_id])
	for tag: String in tags:
		var currency_id := str((countries[tag] as Dictionary).get("currency", ""))
		var currency: CurrencyState = state.currencies.get(currency_id)
		if currency != null:
			currency.members.append(tag)
	for currency_id: String in currencies.keys():
		var currency: CurrencyState = state.currencies[currency_id]
		# Pays émetteur indiqué dans les données ; à défaut, l'unique pays qui l'utilise.
		currency.issuer = str((currencies[currency_id] as Dictionary).get("issuer",
			currency.members[0] if currency.members.size() == 1 else ""))

	for tag: String in tags:
		var country := CountryState.new()
		country.tag = tag
		_setup_economy(country, countries[tag], state, ratings, settings)
		_setup_budget(country, countries[tag], state)
		state.countries[tag] = country
	_calibrate_currencies(state, settings)


static func _create_currency(currency_id: String, data: Dictionary) -> CurrencyState:
	var currency := CurrencyState.new()
	currency.id = currency_id
	currency.code = str(data.get("code", currency_id.to_upper()))
	currency.usd_rate = float(data.get("usd_rate", 1.0))
	currency.start_usd_rate = currency.usd_rate
	currency.policy_rate = float(data.get("policy_rate", 0.0))
	currency.inflation_target = float(data.get("inflation_target", 2.0))
	currency.independent = bool(data.get("independent", true))
	currency.peg = str(data.get("peg", ""))
	return currency


static func _setup_economy(country: CountryState, data: Dictionary, state: SimState, ratings: CreditRating,
		settings: Dictionary) -> void:
	var source: Dictionary = data.get("economy", {})
	var economy := country.economy
	var currency: CurrencyState = state.currencies.get(str(data.get("currency", "")))
	economy.currency = currency.id if currency != null else ""
	economy.population = int(data.get("population", 0))
	economy.real_gdp = float(source.get("gdp_billion_usd", 0.0))
	economy.sectors = (source.get("sectors", {}) as Dictionary).duplicate()
	var growth_bounds: Array = settings["growth_bounds"]
	economy.growth = clampf(float(source.get("growth", 0.0)), float(growth_bounds[0]), float(growth_bounds[1]))
	economy.potential_growth = economy.growth
	economy.inflation = float(source.get("inflation", 0.0))
	economy.unemployment = float(source.get("unemployment", 0.0))
	economy.natural_unemployment = economy.unemployment
	if currency == null:
		return
	economy.neutral_real_rate = clamp_neutral(currency.policy_rate - economy.inflation, settings)

	# Dette : part en devises (sauf pour les pays qui utilisent la monnaie de référence).
	var debt := float(source.get("debt_to_gdp", 0.0)) * economy.nominal_gdp()
	var foreign_share := 0.0 if currency.id == str(settings["reference_currency"]) \
		else float(source.get("foreign_debt_share", 0.0))
	economy.local_debt = debt * (1.0 - foreign_share)
	economy.foreign_debt = debt * foreign_share

	# Note : celle des agences si elle existe, sinon estimée par le modèle.
	var reference: CurrencyState = state.currencies.get(str(settings["reference_currency"]))
	var gdp_per_capita := economy.gdp_per_capita_usd(currency)
	var rating_id := str(source.get("rating", ""))
	var known := ratings.index_of(rating_id)
	economy.rating = known if known != CreditRating.UNKNOWN else 0
	_set_debt_rates(economy, currency, reference, ratings)
	var score := EconomyModel.rating_score(gdp_per_capita, economy.debt_ratio(currency), economy.inflation,
		currency.inflation_target, economy.growth, economy.real_interest_burden(currency), false, settings)
	if known == CreditRating.UNKNOWN:
		economy.rating = maxi(ratings.clamp_index(score), ratings.index_of(str(settings["min_estimated_rating"])))
		economy.rating_estimated = true
		_set_debt_rates(economy, currency, reference, ratings)
		score = EconomyModel.rating_score(gdp_per_capita, economy.debt_ratio(currency), economy.inflation,
			currency.inflation_target, economy.growth, economy.real_interest_burden(currency), false, settings)
	var anchor := economy.rating
	# Pays déjà en défaut : la dette a été restructurée, la note remonte vers celle de sortie de crise.
	if ratings.is_default(economy.rating):
		anchor = ratings.index_of(str((settings["crisis"] as Dictionary)["recovery_rating"]))
	var max_offset := float(settings["max_rating_offset"])
	economy.rating_offset = clampf(anchor - score, -max_offset, max_offset)
	economy.review_phase = absi(hash(country.tag)) % int(settings["rating_review_months"])

	# Les taux effectifs de départ sont réduits si la charge d'intérêts dépasse le plafond : une grande partie
	# de la dette des pays à taux élevés a été émise plus tôt, à de meilleures conditions ou en devises.
	var burden := economy.interest_burden(currency)
	var max_burden := float(settings["max_start_interest_burden"])
	if burden > max_burden:
		economy.debt_rate_factor = max_burden / burden
		economy.local_debt_rate *= economy.debt_rate_factor
		economy.foreign_debt_rate *= economy.debt_rate_factor
	# Solde primaire : le solde réel de 2025 auquel on rajoute les intérêts calculés.
	economy.primary_balance = float(source.get("budget_balance", 0.0)) + economy.interest_burden(currency)
	economy.start_primary_balance = economy.primary_balance
	economy.start_debt_ratio = economy.debt_ratio(currency)


## Budget de départ : taux réels, recettes par point de taux, et dépenses ajustées dans la même proportion
## pour retrouver exactement le solde primaire de départ.
static func _setup_budget(country: CountryState, data: Dictionary, state: SimState) -> void:
	if state.budget_definitions.is_empty():
		return
	var budget := country.economy.budget
	var source: Dictionary = data.get("budget", {})
	var taxes: Dictionary = state.budget_definitions.get("taxes", {})
	var weights: Array = (state.budget_definitions.get("settings", {}) as Dictionary).get("income_bracket_weights", [])
	var tax_data: Dictionary = source.get("taxes", {})
	for tax_id: Variant in taxes.keys():
		var entry: Dictionary = tax_data.get(tax_id, {})
		var revenue := float(entry.get("revenue", 0.0))
		var rate := 0.0
		if str(tax_id) == BudgetModel.INCOME_TAX:
			for value: Variant in entry.get("brackets", []):
				budget.income_brackets.append(float(value))
			while budget.income_brackets.size() < weights.size():
				budget.income_brackets.append(0.0)
			budget.start_income_brackets = budget.income_brackets.duplicate()
			rate = BudgetModel.average_income_rate(budget.income_brackets, weights)
		else:
			rate = float(entry.get("rate", 0.0))
			budget.tax_rates[tax_id] = rate
			budget.start_tax_rates[tax_id] = rate
		budget.revenue_per_point[tax_id] = revenue / rate if rate > 0.0 \
			else float((taxes[tax_id] as Dictionary).get("default_revenue_per_point", 0.0))
	for line_id: Variant in (state.budget_definitions.get("spending", {}) as Dictionary).keys():
		budget.spending[line_id] = float((source.get("spending", {}) as Dictionary).get(line_id, 0.0))
	budget.revenues = BudgetModel.revenues(budget, taxes, weights)
	var total := budget.total_spending()
	var target := budget.total_revenue() - country.economy.primary_balance
	if total > 0.0 and target > 0.0:
		for line_id: Variant in budget.spending.keys():
			budget.spending[line_id] = float(budget.spending[line_id]) * target / total
	budget.start_spending = budget.spending.duplicate()


static func clamp_neutral(value: float, settings: Dictionary) -> float:
	var bounds: Array = settings["neutral_real_rate_bounds"]
	return clampf(value, float(bounds[0]), float(bounds[1]))


## Taux effectifs de départ = taux auxquels le pays emprunte aujourd'hui.
static func _set_debt_rates(economy: EconomyState, currency: CurrencyState, reference: CurrencyState,
		ratings: CreditRating) -> void:
	var spread := ratings.spread(economy.rating)
	economy.local_debt_rate = currency.policy_rate + spread
	economy.foreign_debt_rate = (reference.policy_rate if reference != null else currency.policy_rate) + spread


## Taux neutres et écarts de départ des monnaies, pour que la règle de Taylor et le change partent stables.
static func _calibrate_currencies(state: SimState, settings: Dictionary) -> void:
	for currency: CurrencyState in state.currencies.values():
		EconomySystem.update_currency_aggregates(currency, state)
	var reference: CurrencyState = state.currencies.get(str(settings["reference_currency"]))
	for currency: CurrencyState in state.currencies.values():
		var taylor_without_neutral := EconomyModel.taylor_rate(currency.inflation, 0.0, currency.inflation_target,
			0.0, currency.independent, settings)
		currency.neutral_real_rate = clamp_neutral(currency.policy_rate - taylor_without_neutral, settings)
		if currency.is_pegged():
			var anchor: CurrencyState = state.currencies.get(currency.peg)
			currency.peg_spread = currency.policy_rate - anchor.policy_rate if anchor != null else 0.0
		if reference != null:
			currency.start_real_rate_gap = (currency.policy_rate - currency.inflation) \
				- (reference.policy_rate - reference.inflation)

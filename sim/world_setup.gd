class_name WorldSetup
extends RefCounted
## Crée l'état des pays et des monnaies au début de la partie, à partir des données chargées.
## Le modèle est calé pour que chaque économie parte à l'équilibre : taux neutres et écart de note
## propres à chaque pays reprennent la situation réelle du 1er janvier 2026.

const BILLION := 1.0e9


static func populate(state: SimState, countries: Dictionary, currencies: Dictionary, settings: Dictionary) -> void:
	state.economy_settings = settings
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

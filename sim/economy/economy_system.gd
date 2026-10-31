class_name EconomySystem
extends SimSystem
## Macroéconomie mondiale, une fois par mois :
##   1. banques centrales et taux de change (monnaies flottantes, puis monnaies ancrées) ;
##   2. chaque pays : croissance, inflation, chômage, secteurs, dette ;
##   3. revue des notes, crises de la dette et programmes du FMI.
## Les pays et les monnaies sont parcourus dans l'ordre alphabétique : la simulation reste déterministe.

const EVENT_RATING_CHANGED := &"rating_changed"
const EVENT_DEBT_CRISIS := &"debt_crisis"
const EVENT_CRISIS_ENDED := &"crisis_ended"
const EVENT_IMF_PROGRAM := &"imf_program"
const EVENT_IMF_ENDED := &"imf_ended"

var _sector_trends: Dictionary = {}


## sectors : catégorie « economy_sectors » (tendance de chaque secteur).
func _init(sectors: Dictionary = {}) -> void:
	for sector_id: Variant in sectors.keys():
		_sector_trends[sector_id] = float((sectors[sector_id] as Dictionary).get("trend", 0.0))


func get_id() -> StringName:
	return &"economy"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func on_month(state: SimState) -> void:
	var settings := state.economy_settings
	if settings.is_empty():
		return
	update_currencies(state, settings)
	var tags: Array = state.countries.keys()
	tags.sort()
	var ratings := CreditRating.new(settings)
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		var currency := state.get_currency(country.economy.currency)
		if currency != null:
			step_country(country.economy, currency, state, ratings, _sector_trends, settings)
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		var currency := state.get_currency(country.economy.currency)
		if currency != null:
			step_finances(country, currency, state, ratings, settings)


## Inflation et écart de production d'une monnaie : moyennes de ses membres pondérées par le PIB.
static func update_currency_aggregates(currency: CurrencyState, state: SimState) -> void:
	var total := 0.0
	var inflation := 0.0
	var gap := 0.0
	for tag: String in currency.members:
		var economy := state.get_country(tag).economy if state.get_country(tag) != null else null
		if economy == null:
			continue
		var weight := maxf(economy.nominal_gdp(), 0.0)
		total += weight
		inflation += economy.inflation * weight
		gap += economy.output_gap * weight
	if total > 0.0:
		currency.inflation = inflation / total
		currency.output_gap = gap / total


static func update_currencies(state: SimState, settings: Dictionary) -> void:
	var ids: Array = state.currencies.keys()
	ids.sort()
	var reference: CurrencyState = state.currencies.get(str(settings["reference_currency"]))
	for currency_id: String in ids:
		update_currency_aggregates(state.currencies[currency_id], state)
	# Monnaies flottantes d'abord : les monnaies ancrées suivent leur ancre.
	for currency_id: String in ids:
		var currency: CurrencyState = state.currencies[currency_id]
		if currency.is_pegged():
			continue
		if not is_player_controlled(currency, state):
			var goal := EconomyModel.taylor_rate(currency.inflation, currency.output_gap, currency.inflation_target,
				currency.neutral_real_rate, currency.independent, settings)
			currency.policy_rate = EconomyModel.next_policy_rate(currency.policy_rate, goal, settings)
		currency.neutral_real_rate += (float(settings["neutral_real_rate"]) - currency.neutral_real_rate) \
			* float(settings["neutral_rate_convergence"])
		if reference != null and currency != reference:
			var real_gap := (currency.policy_rate - currency.inflation) - (reference.policy_rate - reference.inflation) \
				- currency.start_real_rate_gap
			currency.last_depreciation = EconomyModel.monthly_depreciation(currency.inflation, real_gap,
				reference.inflation, settings)
			currency.usd_rate *= 1.0 + currency.last_depreciation / EconomyModel.PERCENT
	for currency_id: String in ids:
		var currency: CurrencyState = state.currencies[currency_id]
		var anchor: CurrencyState = state.currencies.get(currency.peg) if currency.is_pegged() else null
		if anchor == null:
			continue
		currency.policy_rate = maxf(anchor.policy_rate + currency.peg_spread, float(settings["min_policy_rate"]))
		var previous := currency.usd_rate
		currency.usd_rate = currency.start_usd_rate * anchor.fx_factor()
		currency.last_depreciation = (currency.usd_rate / previous - 1.0) * EconomyModel.PERCENT


## La banque centrale obéit au joueur si elle dépend de son gouvernement (et n'est pas ancrée).
static func is_player_controlled(currency: CurrencyState, state: SimState) -> bool:
	return not currency.independent and not currency.is_pegged() and not currency.issuer.is_empty() \
		and currency.issuer == str(state.player_tag)


static func step_country(economy: EconomyState, currency: CurrencyState, state: SimState, ratings: CreditRating,
		sector_trends: Dictionary, settings: Dictionary) -> void:
	var growth_bounds: Array = settings["growth_bounds"]
	var inflation_bounds: Array = settings["inflation_bounds"]
	var unemployment_bounds: Array = settings["unemployment_bounds"]
	var crisis: Dictionary = settings["crisis"]
	var imf: Dictionary = settings["imf"]

	var long_run := EconomyModel.long_run_growth(economy.gdp_per_capita_usd(currency), settings)
	economy.potential_growth += (long_run - economy.potential_growth) * float(settings["potential_convergence"])
	economy.neutral_real_rate += (float(settings["neutral_real_rate"]) - economy.neutral_real_rate) \
		* float(settings["neutral_rate_convergence"])
	# Impulsion budgétaire : un solde primaire plus faible qu'au départ soutient la demande (et l'inverse).
	var fiscal_impulse := float(settings["fiscal_multiplier"]) * (economy.start_primary_balance - economy.primary_balance)
	var growth := economy.potential_growth + economy.budget_growth + economy.resource_growth + fiscal_impulse \
		+ EconomyModel.demand_effect(currency.policy_rate, economy.inflation, economy.neutral_real_rate, settings)
	if economy.in_crisis():
		growth += float(crisis["growth_shock"])
	if economy.in_imf_program():
		growth -= float(imf["growth_drag"])
	economy.growth = clampf(growth, float(growth_bounds[0]), float(growth_bounds[1]))
	economy.real_gdp *= 1.0 + economy.growth / EconomyModel.PERCENT / EconomyModel.MONTHS_PER_YEAR
	economy.output_gap = EconomyModel.next_output_gap(economy.output_gap, economy.growth, economy.potential_growth,
		settings)

	var expected := EconomyModel.expected_inflation(economy.inflation, currency.inflation_target, currency.independent,
		settings)
	economy.inflation = clampf(EconomyModel.next_inflation(economy.inflation, expected + economy.budget_inflation + economy.resource_inflation,
		economy.output_gap,
		currency.last_depreciation, settings), float(inflation_bounds[0]), float(inflation_bounds[1]))
	economy.unemployment = clampf(EconomyModel.next_unemployment(economy.unemployment,
		economy.natural_unemployment + economy.budget_unemployment, economy.output_gap, settings), float(unemployment_bounds[0]), float(unemployment_bounds[1]))
	economy.price_level *= 1.0 + economy.inflation / EconomyModel.PERCENT / EconomyModel.MONTHS_PER_YEAR
	economy.sectors = EconomyModel.next_sector_shares(economy.sectors, sector_trends)
	if economy.in_imf_program():
		var step := float(imf["austerity_per_year"]) / EconomyModel.MONTHS_PER_YEAR
		var added := minf(step, float(imf["max_austerity"]) - economy.austerity)
		if added > 0.0:
			economy.austerity += added
			economy.primary_balance += added
	_accrue_debt(economy, currency, state, ratings, settings)


## Intérêts et déficit du mois ; les taux effectifs rejoignent peu à peu les taux du marché.
static func _accrue_debt(economy: EconomyState, currency: CurrencyState, state: SimState, ratings: CreditRating,
		settings: Dictionary) -> void:
	var reference: CurrencyState = state.currencies.get(str(settings["reference_currency"]))
	var spread := ratings.spread(economy.rating)
	var local_market := currency.policy_rate + spread
	var foreign_market := (reference.policy_rate if reference != null else currency.policy_rate) + spread
	if economy.in_imf_program():
		var imf_rate := float((settings["imf"] as Dictionary)["rate"])
		local_market = minf(local_market, maxf(imf_rate, currency.policy_rate))
		foreign_market = minf(foreign_market, imf_rate)
	var maturity := float(settings["debt_maturity_months"])
	economy.local_debt_rate += (local_market * economy.debt_rate_factor - economy.local_debt_rate) / maturity
	economy.foreign_debt_rate += (foreign_market * economy.debt_rate_factor - economy.foreign_debt_rate) / maturity

	var months := EconomyModel.MONTHS_PER_YEAR
	var fx := currency.fx_factor()
	# La création monétaire finance une partie du déficit sans nouvel emprunt.
	var deficit := (-economy.budget_balance(currency) - economy.budget.monetary_financing) / EconomyModel.PERCENT \
		* economy.nominal_gdp() / months
	var total := economy.total_debt(currency)
	var foreign_share := economy.foreign_debt * fx / total if total > 0.0 else 0.0
	economy.local_debt = maxf(economy.local_debt + deficit * (1.0 - foreign_share), 0.0)
	economy.foreign_debt = maxf(economy.foreign_debt + deficit * foreign_share / fx, 0.0)


## Programmes du FMI, crises de la dette et revue de la note.
static func step_finances(country: CountryState, currency: CurrencyState, state: SimState, ratings: CreditRating,
		settings: Dictionary) -> void:
	var economy := country.economy
	var crisis: Dictionary = settings["crisis"]
	_tick_programs(country, state)
	if not economy.in_crisis() and not economy.in_imf_program() and not ratings.is_default(economy.rating):
		var max_rating := ratings.index_of(str(crisis["max_rating"]))
		var chance := EconomyModel.crisis_probability(economy.rating, max_rating,
			float(crisis["monthly_probability_per_notch"]))
		var burden_trigger := economy.real_interest_burden(currency) > float(crisis["interest_burden_trigger"])
		if burden_trigger or (chance > 0.0 and state.rng.randf() < chance):
			start_crisis(country, currency, state, ratings)
	# Les pays de l'IA appellent le FMI dès qu'ils sont en crise (règle provisoire, avant l'IA de l'étape 12).
	if str(state.player_tag) != country.tag and economy.in_crisis() and can_request_imf(economy, ratings, settings):
		start_imf_program(country, state)
	if not economy.in_crisis() and posmod(state.date.month - 1, int(settings["rating_review_months"])) \
			== economy.review_phase:
		_review_rating(country, currency, state, ratings, settings)


static func _tick_programs(country: CountryState, state: SimState) -> void:
	var economy := country.economy
	var settings := state.economy_settings
	if economy.imf_cooldown > 0:
		economy.imf_cooldown -= 1
	if economy.imf_months > 0:
		economy.imf_months -= 1
		if economy.imf_months == 0:
			economy.imf_cooldown = int((settings["imf"] as Dictionary)["cooldown_months"])
			state.add_event(EVENT_IMF_ENDED, country.tag)
	if economy.crisis_months > 0:
		economy.crisis_months -= 1
		if economy.crisis_months == 0:
			_end_crisis(country, state)


static func _review_rating(country: CountryState, currency: CurrencyState, state: SimState, ratings: CreditRating,
		settings: Dictionary) -> void:
	var economy := country.economy
	var score := rating_score(economy, currency, settings)
	var reviewed := EconomyModel.reviewed_rating(economy.rating, score, ratings.best(),
		float(settings["rating_hysteresis"]))
	if reviewed != economy.rating:
		state.add_event(EVENT_RATING_CHANGED, country.tag, {"old": ratings.id_of(economy.rating),
			"new": ratings.id_of(reviewed), "upgrade": reviewed > economy.rating})
		economy.rating = reviewed


## Score de solvabilité du pays, écart propre au pays compris.
static func rating_score(economy: EconomyState, currency: CurrencyState, settings: Dictionary) -> float:
	return EconomyModel.rating_score(economy.gdp_per_capita_usd(currency), economy.debt_ratio(currency),
		economy.inflation, currency.inflation_target, economy.growth, economy.real_interest_burden(currency),
		economy.in_imf_program(), settings) + economy.rating_offset


## Défaut de paiement : note en défaut, restructuration de la dette, choc sur l'activité, les prix et la monnaie.
static func start_crisis(country: CountryState, currency: CurrencyState, state: SimState, ratings: CreditRating) -> void:
	var economy := country.economy
	var crisis: Dictionary = state.economy_settings["crisis"]
	var old_rating := ratings.id_of(economy.rating)
	economy.rating = 0
	economy.crisis_months = int(crisis["duration_months"])
	var keep := 1.0 - float(crisis["haircut"])
	economy.local_debt *= keep
	economy.foreign_debt *= keep
	economy.inflation += float(crisis["inflation_shock"])
	# Seule une monnaie nationale flottante décroche ; une union monétaire ou un ancrage tient.
	if not currency.is_pegged() and currency.members.size() == 1 \
			and currency.id != str(state.economy_settings["reference_currency"]):
		currency.usd_rate *= 1.0 + float(crisis["depreciation"])
	state.add_event(EVENT_DEBT_CRISIS, country.tag, {"old": old_rating})


static func _end_crisis(country: CountryState, state: SimState) -> void:
	var economy := country.economy
	var settings := state.economy_settings
	var ratings := CreditRating.new(settings)
	var currency := state.get_currency(economy.currency)
	economy.rating = ratings.index_of(str((settings["crisis"] as Dictionary)["recovery_rating"]))
	# Le score repart de la note de sortie de crise.
	if currency != null:
		var max_offset := float(settings["max_rating_offset"])
		economy.rating_offset = 0.0
		economy.rating_offset = clampf(economy.rating - rating_score(economy, currency, settings), -max_offset,
			max_offset)
	state.add_event(EVENT_CRISIS_ENDED, country.tag, {"new": ratings.id_of(economy.rating)})


## Le FMI aide un pays mal noté ou en crise, sans programme en cours ni récent.
static func can_request_imf(economy: EconomyState, ratings: CreditRating, settings: Dictionary) -> bool:
	if economy.in_imf_program() or economy.imf_cooldown > 0:
		return false
	var max_rating := ratings.index_of(str((settings["imf"] as Dictionary)["max_rating"]))
	return economy.in_crisis() or economy.rating <= max_rating


static func start_imf_program(country: CountryState, state: SimState) -> void:
	var economy := country.economy
	economy.imf_months = int((state.economy_settings["imf"] as Dictionary)["duration_months"])
	economy.austerity = 0.0
	state.add_event(EVENT_IMF_PROGRAM, country.tag)

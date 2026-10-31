class_name AidSystem
extends SimSystem
## Aide internationale, une fois par mois, avant le budget : versements des programmes (aide économique et
## humanitaire, prêts et leurs remboursements, ventes et dons d'armes, conseillers militaires) et effets sur
## le pays aidé (croissance, stabilité) à proportion du poids de l'aide dans son PIB. Les programmes de 2026
## versent leur argent mais leurs effets sont déjà compris dans la situation de départ.

const PRIORITY := -11
const EU_GROUP := "@eu"
const EVENT_AID := &"aid_given"
const EVENT_AID_REFUSED := &"aid_refused"
const MONTHS_PER_YEAR := 12.0
const PERCENT := 100.0


func get_id() -> StringName:
	return &"aid"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.aid_definitions.is_empty():
		return
	var settings := settings_of(state)
	var remaining: Array[Dictionary] = []
	for program: Dictionary in state.diplomacy.aid_programs:
		var donor := state.get_country(str(program["donor"]))
		var recipient := state.get_country(str(program["recipient"]))
		if donor == null or recipient == null:
			continue
		_pay(state, program, donor, recipient, settings)
		program["months_left"] = int(program["months_left"]) - 1
		if int(program["months_left"]) > 0:
			remaining.append(program)
	state.diplomacy.aid_programs = remaining
	refresh_effects(state)


static func settings_of(state: SimState) -> Dictionary:
	return state.diplomacy_settings.get("aid", {})


## Versement du mois. Prêt : versé en entier le premier mois, puis remboursé avec intérêts.
static func _pay(state: SimState, program: Dictionary, donor: CountryState, recipient: CountryState,
		settings: Dictionary) -> void:
	var definition: Dictionary = state.aid_definitions.get(program["kind"], {})
	if bool(definition.get("repay", false)):
		if not bool(program.get("disbursed", false)):
			var principal := float(program["amount"])
			InvestmentSystem.add_debt_usd(donor, state, principal)
			InvestmentSystem.add_debt_usd(recipient, state, -principal)
			program["disbursed"] = true
			program["balance"] = principal
			program["months_left"] = int(settings.get("loan_term_months", 1)) + 1
			return
		var term := float(settings.get("loan_term_months", 1))
		var payment := float(program["amount"]) / term + float(program["balance"]) * float(settings.get("loan_rate", 0.0)) \
			/ PERCENT / MONTHS_PER_YEAR
		program["balance"] = maxf(float(program["balance"]) - float(program["amount"]) / term, 0.0)
		InvestmentSystem.add_debt_usd(recipient, state, payment)
		InvestmentSystem.add_debt_usd(donor, state, -payment)
		return
	var monthly := float(program["amount"]) / MONTHS_PER_YEAR if int(program["total_months"]) > 1 \
		else float(program["amount"])
	if str(definition.get("payer", "donor")) == "recipient":
		InvestmentSystem.add_debt_usd(recipient, state, monthly)
		InvestmentSystem.add_debt_usd(donor, state, -monthly)
	else:
		InvestmentSystem.add_debt_usd(donor, state, monthly)
		if bool(definition.get("cash", false)):
			InvestmentSystem.add_debt_usd(recipient, state, -monthly)
	if bool(definition.get("military", false)):
		var tag := str(program["recipient"])
		state.diplomacy.arms_received[tag] = float(state.diplomacy.arms_received.get(tag, 0.0)) + monthly


## Effets des programmes lancés pendant la partie sur les pays aidés.
static func refresh_effects(state: SimState) -> void:
	var settings := settings_of(state)
	var growth: Dictionary = {}
	var stability: Dictionary = {}
	for program: Dictionary in state.diplomacy.aid_programs:
		if bool(program.get("initial", false)):
			continue
		var tag := str(program["recipient"])
		var definition: Dictionary = state.aid_definitions.get(program["kind"], {})
		var share := yearly_share(state, program)
		growth[tag] = float(growth.get(tag, 0.0)) + float(definition.get("growth", 0.0)) * share
		var points := float(definition.get("stability", 0.0)) * (1.0 if bool(definition.get("flat", false)) else share)
		stability[tag] = float(stability.get(tag, 0.0)) + points
	for country: CountryState in state.countries.values():
		country.economy.aid_growth = minf(float(growth.get(country.tag, 0.0)), float(settings.get("max_growth", INF)))
		country.aid_stability = minf(float(stability.get(country.tag, 0.0)), float(settings.get("max_stability", INF)))


## Poids annuel du programme dans le PIB du pays aidé (%).
static func yearly_share(state: SimState, program: Dictionary) -> float:
	var gdp := TradeSystem.current_gdp(state, str(program["recipient"]))
	return float(program["amount"]) / gdp * PERCENT if gdp > 0.0 else 0.0


## Le pays aidé accepte si ses relations avec le donateur atteignent le minimum du type d'aide.
static func accepts(state: SimState, donor: String, recipient: String, kind: String) -> bool:
	if recipient == str(state.player_tag):
		return true
	var definition: Dictionary = state.aid_definitions.get(kind, {})
	return state.diplomacy.relation(donor, recipient) >= float(definition.get("min_relation", -DiplomacyState.LIMIT))


## Nouveau programme : amount en milliards de dollars (par an, ou en une fois si months = 1).
static func start_program(state: SimState, donor: String, recipient: String, kind: String, amount: float,
		months: int, initial: bool = false) -> void:
	var program := {"donor": donor, "recipient": recipient, "kind": kind, "amount": amount, "months_left": months,
		"total_months": months, "initial": initial}
	state.diplomacy.aid_programs.append(program)
	if initial:
		return
	var definition: Dictionary = state.aid_definitions.get(kind, {})
	var settings := settings_of(state)
	# Une aide d'1 % du PIB du pays aidé rapporte les points de relations du type d'aide, dans des bornes.
	var gain := clampf(float(definition.get("relation", 0.0)) * yearly_share(state, program),
		float(settings.get("min_relation_gain", 0.0)), float(settings.get("max_relation_gain", INF)))
	state.diplomacy.change_relation(donor, recipient, gain)
	state.diplomacy.change_opinion(recipient, donor, float(definition.get("opinion", 0.0)) * gain
		/ maxf(float(definition.get("relation", 1.0)), 1.0))
	refresh_effects(state)


## Programmes de 2026 (« @eu » réparti entre les membres de l'UE selon leur PIB).
static func setup_start(state: SimState) -> void:
	for entry: Variant in (state.diplomacy_start.get("aid", {}) as Dictionary).get("list", []):
		var values: Array = entry
		var donors: Dictionary = {}
		if str(values[0]) == EU_GROUP:
			var total := 0.0
			for member: Variant in OrganizationSystem.members(state, "eu"):
				donors[str(member)] = TradeSystem.current_gdp(state, str(member))
				total += float(donors[str(member)])
			for member: Variant in donors.keys():
				donors[member] = float(donors[member]) / total if total > 0.0 else 0.0
		else:
			donors[str(values[0])] = 1.0
		for donor: Variant in donors.keys():
			if state.countries.has(donor) and state.countries.has(values[1]):
				start_program(state, str(donor), str(values[1]), str(values[2]), float(values[3]) * float(donors[donor]),
					int(values[4]), true)


## Programmes entre deux pays (dans les deux sens).
static func programs_between(state: SimState, a: String, b: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for program: Dictionary in state.diplomacy.aid_programs:
		if (program["donor"] == a and program["recipient"] == b) or (program["donor"] == b and program["recipient"] == a):
			result.append(program)
	return result

class_name ConstitutionSystem
extends SimSystem
## Constitution, une fois par mois : référendums arrivés à échéance et état d'urgence (stabilité en hausse,
## croissance en baisse, légitimité qui s'use en démocratie, élections repoussées).

const PRIORITY := -35
const EVENT_REFORM_ADOPTED := &"constitution_changed"
const EVENT_REFORM_REJECTED := &"constitution_rejected"
const EVENT_REFERENDUM_CALLED := &"referendum_called"
const EVENT_REFERENDUM_HELD := &"referendum_held"
const EVENT_EMERGENCY := &"emergency_changed"
const DEFAULT_PRESIDENTIAL_TERM := 5


func get_id() -> StringName:
	return &"constitution"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.politics_definitions.is_empty():
		return
	var settings := settings_of(state)
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		var politics := country.politics
		if not politics.pending_referendum.is_empty() and PoliticsState.is_due(state.date.year, state.date.month,
				int(politics.pending_referendum["year"]), int(politics.pending_referendum["month"])):
			hold_referendum(country, state)
		country.economy.emergency_growth = 0.0
		if politics.emergency_months > 0:
			politics.emergency_months -= 1
			country.economy.emergency_growth = float(settings.get("emergency_growth", 0.0))
			if politics.democratic:
				country.society.start_legitimacy -= float(settings.get("emergency_legitimacy_per_month", 0.0))
			if politics.emergency_months == 0:
				state.add_event(EVENT_EMERGENCY, tag, {"active": false})


static func settings_of(state: SimState) -> Dictionary:
	return (state.politics_definitions.get("settings", {}) as Dictionary).get("constitution", {})


static func definition_of(state: SimState, reform_id: String) -> Dictionary:
	return (state.politics_definitions.get("constitution", {}) as Dictionary).get(reform_id, {})


static func hold_referendum(country: CountryState, state: SimState) -> void:
	var politics := country.politics
	var reform := str(politics.pending_referendum["reform"])
	var option := str(politics.pending_referendum["option"])
	politics.pending_referendum = {}
	var yes := ConstitutionModel.referendum_yes(politics, country.society, definition_of(state, reform),
		str(country.constitution.get(reform, "")), option, settings_of(state))
	var passed := yes > ConstitutionModel.PERCENT / 2.0
	state.add_event(EVENT_REFERENDUM_HELD, country.tag, {"reform": reform, "yes": yes, "passed": passed})
	if passed:
		apply_reform(country, state, reform, option)


## Met la réforme en application : mandats, mode de scrutin, seuil, forme du pouvoir exécutif.
static func apply_reform(country: CountryState, state: SimState, reform: String, option_id: String) -> void:
	var option := LawModel.option_of(definition_of(state, reform), option_id)
	var value: Variant = option.get("value")
	var politics := country.politics
	country.constitution[reform] = option_id
	match reform:
		"presidential_term_limit":
			politics.term_limit = int(value)
		"presidential_term":
			politics.presidential_term = int(value)
		"legislative_term":
			politics.term_years = int(value)
		"electoral_system":
			politics.system_type = str(value)
			if politics.system_type == PoliticsState.SYSTEM_MIXED and politics.list_share <= 0.0:
				politics.list_share = float(settings_of(state).get("default_list_share", 0.5))
		"threshold":
			politics.threshold = float(value)
		"executive":
			_set_executive(country, state, str(value))
	country.society.start_legitimacy += float(option.get("legitimacy", 0.0))
	state.add_event(EVENT_REFORM_ADOPTED, country.tag, {"reform": reform, "option": option_id})


static func _set_executive(country: CountryState, state: SimState, regime: String) -> void:
	var politics := country.politics
	politics.regime = regime
	politics.executive = PoliticsState.EXECUTIVE_PRESIDENTIAL if regime == "presidential_republic" \
		else PoliticsState.EXECUTIVE_PARLIAMENTARY
	var wants_presidency := regime != "parliamentary_republic"
	if wants_presidency and not politics.has_presidency:
		politics.has_presidency = true
		politics.presidential_term = maxi(politics.presidential_term, DEFAULT_PRESIDENTIAL_TERM)
		politics.two_rounds = true
		politics.terms_served = 0
		var date := ElectionSystem._add_months(state.date.year, state.date.month,
			int(settings_of(state).get("new_presidency_delay_months", 1)))
		politics.next_presidential_year = date[0]
		politics.next_presidential_month = date[1]
	elif not wants_presidency:
		politics.has_presidency = false

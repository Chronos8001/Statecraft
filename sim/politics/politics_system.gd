class_name PoliticsSystem
extends SimSystem
## Vie politique, une fois par mois, après la société : sondages des partis.

const PRIORITY := 20
const EVENT_PROMISE := &"promise_resolved"


func get_id() -> StringName:
	return &"politics"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.politics_definitions.is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		update_country(state.countries[tag], state)


static func update_country(country: CountryState, state: SimState) -> void:
	var politics := country.politics
	if politics.parties.is_empty() or country.society.group_shares.is_empty():
		return
	var groups: Dictionary = state.society_definitions.get("groups", {})
	var settings: Dictionary = state.politics_definitions.get("settings", {})
	var campaign: Dictionary = settings.get("campaign", {})
	politics.campaign_bonus = CampaignModel.campaign_bonus(politics, TradeSystem.current_gdp(state, country.tag), campaign)
	update_promises(country, state, campaign)
	# Ordre fixe des tirages pour que la partie reste reproductible.
	var ids: Array = politics.parties.keys()
	ids.sort()
	for party_id: String in ids:
		var party: PartyState = politics.parties[party_id]
		party.drift = PoliticsModel.next_drift(party.drift, state.rng.randfn(0.0, 1.0), settings)
	var values := PoliticsModel.polls(politics, country.society, groups, settings)
	for party_id: String in ids:
		var party: PartyState = politics.parties[party_id]
		party.previous_poll = party.poll
		party.poll = float(values[party_id])


## Promesses dont le scrutin est passé : tenues si le budget apporte assez au groupe, caduques si le parti
## a perdu le pouvoir, rompues à l'échéance (sanction durable pour le groupe et la légitimité).
static func update_promises(country: CountryState, state: SimState, settings: Dictionary) -> void:
	var politics := country.politics
	var society := country.society
	var budget_groups: Dictionary = country.economy.budget.effects.get(BudgetModel.GROUPS, {})
	var kept: Array[Dictionary] = []
	for promise: Dictionary in politics.promises:
		var group_id := str(promise["group"])
		var outcome := ""
		if str(promise["party"]) != politics.ruling_party():
			outcome = "void"
		elif not bool(promise.get("pending", true)) and float(budget_groups.get(group_id, 0.0)) \
				>= float(settings.get("promise_requirement", 0.0)):
			outcome = "kept"
		elif PoliticsState.is_due(state.date.year, state.date.month, int(promise["deadline_year"]),
				int(promise["deadline_month"])):
			outcome = "broken"
		if outcome.is_empty():
			kept.append(promise)
			continue
		society.bonuses[group_id] = float(society.bonuses.get(group_id, 0.0)) - float(promise["gain"])
		if outcome == "broken":
			society.start_satisfaction[group_id] = float(society.start_satisfaction.get(group_id, 0.0)) \
				- float(settings.get("promise_penalty", 0.0))
			if politics.democratic:
				society.start_legitimacy -= float(settings.get("promise_legitimacy_penalty", 0.0))
		if outcome != "void":
			state.add_event(EVENT_PROMISE, country.tag, {"group": group_id, "outcome": outcome})
	politics.promises = kept


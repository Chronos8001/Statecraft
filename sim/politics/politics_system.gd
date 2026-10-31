class_name PoliticsSystem
extends SimSystem
## Vie politique, une fois par mois, après la société : sondages des partis.

const PRIORITY := 20


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

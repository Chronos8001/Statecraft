class_name ElectionSystem
extends SimSystem
## Élections, une fois par mois, après les sondages : législatives et présidentielles arrivées à échéance.
## Démocraties : vote par province, sièges selon le système du pays, formation du gouvernement.
## Autres régimes : scrutins de façade, le pouvoir en place garde ses sièges.

const PRIORITY := 25
const EVENT_ELECTION := &"election_held"
const KIND_LEGISLATIVE := "legislative"
const KIND_PRESIDENTIAL := "presidential"
const MONTHS_PER_YEAR := 12
const EVENT_FRAUD_DETECTED := &"fraud_detected"


func get_id() -> StringName:
	return &"elections"


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
		var country: CountryState = state.countries[tag]
		var politics := country.politics
		if politics.seats <= 0 or politics.suspended or politics.emergency_months > 0:
			continue
		var held := false
		if PoliticsState.is_due(state.date.year, state.date.month, politics.next_election_year,
				politics.next_election_month):
			hold_legislative(country, state)
			held = true
		if politics.has_presidency and PoliticsState.is_due(state.date.year, state.date.month,
				politics.next_presidential_year, politics.next_presidential_month):
			hold_presidential(country, state)
			held = true
		if held:
			_check_fraud(country, state)
			for promise: Dictionary in politics.promises:
				promise["pending"] = false
			politics.reset_campaign()


static func settings_of(state: SimState) -> Dictionary:
	return (state.politics_definitions.get("settings", {}) as Dictionary).get("elections", {})


static func position_of(party: PartyState, settings: Dictionary) -> float:
	return float((settings.get("positions", {}) as Dictionary).get(party.party_group, 0.0))


## Résultat national du jour : sondage avec un petit écart aléatoire propre au scrutin.
static func election_day_votes(politics: PoliticsState, state: SimState, settings: Dictionary) -> Dictionary:
	var ids: Array = politics.parties.keys()
	ids.sort()
	var votes: Dictionary = {}
	var total := 0.0
	for party_id: String in ids:
		var party: PartyState = politics.parties[party_id]
		var value := party.poll * exp(state.rng.randfn(0.0, 1.0) * float(settings.get("election_sigma", 0.0)))
		votes[party_id] = value
		total += value
	for party_id: String in ids:
		votes[party_id] = float(votes[party_id]) / total * (ElectionModel.PERCENT - politics.other_poll) \
			if total > 0.0 else 0.0
	return votes


static func hold_legislative(country: CountryState, state: SimState) -> void:
	var politics := country.politics
	var settings := settings_of(state)
	var seats_before := _seats(politics)
	var result := {"kind": KIND_LEGISLATIVE, "year": state.date.year, "month": state.date.month,
		"seats_before": seats_before, "government_changed": false}
	if politics.democratic and not politics.parties.is_empty():
		var provinces: Array = (state.politics_definitions.get("provinces", {}) as Dictionary).get(country.tag, [])
		var national := _rigged(politics, election_day_votes(politics, state, settings), state)
		var groups_of: Dictionary = {}
		for party: PartyState in politics.parties.values():
			groups_of[party.id] = party.party_group
		var regional := ElectionModel.regional_votes(national, groups_of, provinces, politics.other_poll, settings,
			rally_leans(politics, state))
		if not provinces.is_empty():
			national = ElectionModel.national_votes(regional, provinces)
		politics.other_vote = politics.other_poll
		politics.other_seats = roundi(politics.seats * politics.other_vote / ElectionModel.PERCENT
			* float(settings.get("others_seat_factor", 0.0)))
		var won := ElectionModel.allocate(politics.system_type, politics.threshold, politics.list_share, national,
			regional, provinces, politics.seats - politics.other_seats, float(settings.get("majoritarian_exponent", 1.0)))
		for party: PartyState in politics.parties.values():
			party.seats = int(won.get(party.id, 0))
			party.vote = float(national.get(party.id, 0.0))
		result["votes"] = national
		result["regions"] = ElectionModel.regional_winners(regional)
		if politics.executive == PoliticsState.EXECUTIVE_PARLIAMENTARY:
			var formed := ElectionModel.form_government(_coalition_inputs(politics, settings), politics.seats,
				politics.government, settings)
			result["government_changed"] = apply_government(country, state, formed)
	politics.dissolved = false
	politics.election_year = state.date.year
	politics.election_month = state.date.month
	var next := _add_months(state.date.year, state.date.month, maxi(politics.term_years, 1) * MONTHS_PER_YEAR)
	politics.next_election_year = next[0]
	politics.next_election_month = next[1]
	result["seats_after"] = _seats(politics)
	result["winner"] = _largest_party(politics)
	politics.last_result = result
	state.add_event(EVENT_ELECTION, country.tag, {"kind": KIND_LEGISLATIVE, "winner": result["winner"],
		"government_changed": result["government_changed"], "managed": not politics.democratic})


static func hold_presidential(country: CountryState, state: SimState) -> void:
	var politics := country.politics
	var settings := settings_of(state)
	var definitions: Dictionary = state.politics_definitions.get("parties", {})
	var incumbent_party := str(GovernmentSystem.character(state, politics.head_of_state).get("party", ""))
	var result := {"kind": KIND_PRESIDENTIAL, "year": state.date.year, "month": state.date.month,
		"government_changed": false}
	var winner := incumbent_party
	if politics.democratic and not politics.parties.is_empty():
		var scores := _rigged(politics, election_day_votes(politics, state, settings), state)
		if scores.has(incumbent_party):
			var factor := 1.0 - float(settings.get("open_seat_penalty", 0.0)) if term_limited(politics) \
				else 1.0 + float(settings.get("incumbent_bonus", 0.0))
			scores[incumbent_party] = float(scores[incumbent_party]) * factor
		var positions: Dictionary = {}
		for party: PartyState in politics.parties.values():
			positions[party.id] = position_of(party, settings)
		var outcome := ElectionModel.presidential(scores, positions, politics.two_rounds, settings)
		winner = str(outcome["winner"])
		result["rounds"] = outcome["rounds"]
		if not winner.is_empty() and winner == incumbent_party and term_limited(politics):
			_install_successor(country, state, winner)
		if not winner.is_empty() and winner != incumbent_party:
			var leader := str((definitions.get(winner, {}) as Dictionary).get("leader", ""))
			if not leader.is_empty():
				var same_person := politics.head_of_government == politics.head_of_state
				politics.head_of_state = leader
				if politics.executive == PoliticsState.EXECUTIVE_PRESIDENTIAL:
					if same_person:
						politics.head_of_government = leader
					var government: Array[String] = [winner]
					result["government_changed"] = apply_government(country, state, government)
	politics.terms_served = politics.terms_served + 1 if winner == incumbent_party and not term_limited(politics) else 1
	politics.presidential_year = state.date.year
	politics.presidential_month = state.date.month
	var next := _add_months(state.date.year, state.date.month, maxi(politics.presidential_term, 1) * MONTHS_PER_YEAR)
	politics.next_presidential_year = next[0]
	politics.next_presidential_month = next[1]
	result["winner"] = winner
	politics.last_result = result
	state.add_event(EVENT_ELECTION, country.tag, {"kind": KIND_PRESIDENTIAL, "winner": winner,
		"government_changed": result["government_changed"], "managed": not politics.democratic})


## Installe un nouveau gouvernement. Les attentes des groupes sociaux suivent la famille politique au pouvoir ;
## en régime parlementaire, le chef du parti qui dirige devient chef du gouvernement. Renvoie true si le
## gouvernement a changé.
static func apply_government(country: CountryState, state: SimState, government: Array[String]) -> bool:
	var politics := country.politics
	if government.is_empty() or government == politics.government:
		return false
	var old_ruling := politics.ruling_party()
	var new_ruling: PartyState = politics.parties.get(government[0])
	politics.government = government
	if new_ruling == null or old_ruling == new_ruling.id:
		return true
	var groups: Dictionary = state.society_definitions.get("groups", {})
	var ideologies: Dictionary = state.society_definitions.get("ideologies", {})
	var old_group := str((ideologies.get(politics.ideology, {}) as Dictionary).get("party_group", ""))
	var society := country.society
	for group_id: Variant in society.start_satisfaction.keys():
		var affinity: Dictionary = (groups.get(group_id, {}) as Dictionary).get("affinity", {})
		var change := float(affinity.get(new_ruling.party_group, 0.0)) - float(affinity.get(old_group, 0.0))
		society.start_satisfaction[group_id] = float(society.start_satisfaction[group_id]) + change
	politics.ideology = new_ruling.ideology
	GovernmentSystem.form_cabinet(country, state)
	if politics.executive == PoliticsState.EXECUTIVE_PARLIAMENTARY:
		var leader := str((state.politics_definitions.get("parties", {}) as Dictionary).get(new_ruling.id, {}).get(
			"leader", ""))
		if not leader.is_empty():
			politics.head_of_government = leader
	return true


static func _seats(politics: PoliticsState) -> Dictionary:
	var result: Dictionary = {}
	for party: PartyState in politics.parties.values():
		result[party.id] = party.seats
	return result


static func _coalition_inputs(politics: PoliticsState, settings: Dictionary) -> Dictionary:
	var excluded: Array = settings.get("cordon_groups", []) if politics.cordon else []
	var result: Dictionary = {}
	for party: PartyState in politics.parties.values():
		result[party.id] = [party.seats, position_of(party, settings), excluded.has(party.party_group)]
	return result


static func _largest_party(politics: PoliticsState) -> String:
	var best: PartyState = null
	for party: PartyState in politics.parties.values():
		if best == null or party.seats > best.seats or (party.seats == best.seats and party.id < best.id):
			best = party
	return best.id if best != null else ""


static func _add_months(year: int, month: int, months: int) -> Array[int]:
	var index := year * MONTHS_PER_YEAR + month - 1 + months
	return [index / MONTHS_PER_YEAR, index % MONTHS_PER_YEAR + 1]


## Le parti du président sortant garde la présidence avec un nouveau candidat.
static func _install_successor(country: CountryState, state: SimState, party_id: String) -> void:
	var politics := country.politics
	var successor := GovernmentModel.make_character(state, country, party_id, "%s|president|%d|%d" % [country.tag,
		state.date.year, state.date.month])
	if successor.is_empty():
		return
	var character_id := "%s%d" % [GovernmentSystem.CHARACTER_PREFIX, state.next_character_id]
	state.next_character_id += 1
	state.characters[character_id] = successor
	if politics.head_of_government == politics.head_of_state and politics.executive == PoliticsState.EXECUTIVE_PRESIDENTIAL:
		politics.head_of_government = character_id
	politics.head_of_state = character_id


## Le président en place ne peut pas se représenter.
static func term_limited(politics: PoliticsState) -> bool:
	return politics.term_limit > 0 and politics.terms_served >= politics.term_limit


static func campaign_settings(state: SimState) -> Dictionary:
	return (state.politics_definitions.get("settings", {}) as Dictionary).get("campaign", {})


## Penchant local du parti au pouvoir dans les provinces où il a tenu un meeting.
static func rally_leans(politics: PoliticsState, state: SimState) -> Dictionary:
	var result: Dictionary = {}
	var bonus := float(campaign_settings(state).get("rally_regional_bonus", 0.0))
	for province_id: Variant in politics.rallies.keys():
		result[province_id] = {politics.ruling_party(): bonus}
	return result


static func _rigged(politics: PoliticsState, votes: Dictionary, state: SimState) -> Dictionary:
	if politics.fraud_level <= 0:
		return votes
	var points: Array = campaign_settings(state).get("fraud_points", [])
	if points.is_empty():
		return votes
	return CampaignModel.rigged_votes(votes, politics.ruling_party(),
		float(points[mini(politics.fraud_level, points.size()) - 1]))


## Fraude découverte : scandal durable (stabilité et légitimité), notifié au monde entier.
static func _check_fraud(country: CountryState, state: SimState) -> void:
	var politics := country.politics
	if politics.fraud_level <= 0:
		return
	var settings := campaign_settings(state)
	var chance := CampaignModel.detection_chance(politics.fraud_level, country.society.democracy_index,
		politics.media_factor, settings)
	if state.rng.randf() >= chance:
		return
	var index := mini(politics.fraud_level, 3) - 1
	var stability := float((settings.get("scandal_stability", [0, 0, 0]) as Array)[index])
	var legitimacy := float((settings.get("scandal_legitimacy", [0, 0, 0]) as Array)[index])
	var society := country.society
	society.stability = maxf(society.stability - stability, 0.0)
	society.start_stability -= stability / 2.0
	society.legitimacy = maxf(society.legitimacy - legitimacy, 0.0)
	society.start_legitimacy -= legitimacy / 2.0
	state.add_event(EVENT_FRAUD_DETECTED, country.tag, {"level": politics.fraud_level})


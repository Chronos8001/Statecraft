class_name OrganizationSystem
extends SimSystem
## Organisations internationales : adhésions, départs, exclusions, créations et invitations ; ONU avec
## Conseil de sécurité (5 membres permanents avec veto, 10 élus renouvelés chaque janvier) et résolutions
## de condamnation. Chaque membre vote selon ses relations ; les règles de chaque organisation (unanimité,
## zone, accord commercial lié) sont dans data/organization_rules.

const PRIORITY := 31
const UN := "un"
const CUSTOM_PREFIX := "custom_"
const GENERAL_ASSEMBLY := "general_assembly"
const RESOLUTION_CONDEMN := "condemn"
const RESOLUTION_SANCTIONS := "sanctions"
const SECURITY_COUNCIL := "security_council"
const EVENT_JOINED := &"organization_joined"
const EVENT_JOIN_REFUSED := &"organization_join_refused"
const EVENT_LEFT := &"organization_left"
const EVENT_EXPELLED := &"organization_expelled"
const EVENT_CREATED := &"organization_created"
const EVENT_RESOLUTION := &"resolution_voted"


func get_id() -> StringName:
	return &"organizations"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.diplomacy_settings.is_empty() or state.date.month != 1:
		return
	renew_council(state)


static func settings_of(state: SimState) -> Dictionary:
	return state.diplomacy_settings.get("organizations", {})


static func rules_of(state: SimState, org_id: String) -> Dictionary:
	return state.organization_rules.get(org_id, {})


## Organisations de départ : celles des données et leurs membres ; Conseil de sécurité de 2026.
static func setup_start(state: SimState, organizations: Dictionary, countries: Dictionary) -> void:
	var diplomacy := state.diplomacy
	for org_id: String in organizations.keys():
		var data: Dictionary = organizations[org_id]
		diplomacy.organizations[org_id] = {"kind": str(data.get("kind", "")), "name": data.get("name", org_id),
			"abbreviation": data.get("abbreviation", org_id), "color": str(data.get("color", "#808080")),
			"members": [], "custom": false}
	var tags: Array = countries.keys()
	tags.sort()
	for tag: String in tags:
		for org_id: Variant in (countries[tag] as Dictionary).get("organizations", []):
			if diplomacy.organizations.has(org_id):
				(diplomacy.organizations[org_id]["members"] as Array).append(tag)
	var council: Dictionary = state.diplomacy_start.get("security_council", {})
	for tag: Variant in council.get("permanent", []):
		diplomacy.security_council[str(tag)] = 0
	var elected: Dictionary = council.get("elected", {})
	for tag: Variant in elected.keys():
		diplomacy.security_council[str(tag)] = int(elected[tag])


static func members(state: SimState, org_id: String) -> Array:
	return (state.diplomacy.organizations.get(org_id, {}) as Dictionary).get("members", [])


static func is_member(state: SimState, org_id: String, tag: String) -> bool:
	return members(state, org_id).has(tag)


static func organizations_of(state: SimState, tag: String) -> Array[String]:
	var result: Array[String] = []
	for org_id: String in state.diplomacy.organizations.keys():
		if is_member(state, org_id, tag):
			result.append(org_id)
	return result


static func eligible(state: SimState, org_id: String, tag: String) -> bool:
	var rule: Variant = rules_of(state, org_id).get("eligible", "any")
	return not (rule is Array) or (rule as Array).has(tag)


## Vote d'un membre sur une adhésion (positif : pour).
static func join_score(state: SimState, org_id: String, voter: String, applicant: String) -> float:
	var rules := rules_of(state, org_id)
	var kind := str((state.diplomacy.organizations.get(org_id, {}) as Dictionary).get("kind", ""))
	var base := float(rules.get("vote_base", (settings_of(state).get("kind_vote_base", {}) as Dictionary).get(kind, 0.0)))
	var score := base + state.diplomacy.relation(voter, applicant)
	var a := state.get_country(voter)
	var b := state.get_country(applicant)
	if a != null and b != null:
		if rules.has("same_regime"):
			score += float(rules["same_regime"]) * (1.0 if a.politics.democratic == b.politics.democratic else -1.0)
		if bool(rules.get("democratic", false)) and not b.politics.democratic:
			score -= DiplomacyState.LIMIT
	return score


## Résultat attendu d'un vote des membres : {yes, no, passed, vetoed}.
static func member_vote(state: SimState, org_id: String, subject: String, voters: Array, score_of: Callable,
		decision: String) -> Dictionary:
	var yes := 0
	var no := 0
	var vetoed := false
	var veto_members: Array = state.diplomacy_start.get("security_council", {}).get("permanent", []) \
		if (settings_of(state).get("veto_organizations", []) as Array).has(org_id) else []
	for voter: Variant in voters:
		if str(voter) == subject:
			continue
		if float(score_of.call(str(voter))) > 0.0:
			yes += 1
		else:
			no += 1
			if veto_members.has(voter):
				vetoed = true
	var passed := false
	match decision:
		"unanimity":
			passed = no == 0 and yes > 0
		"two_thirds":
			passed = yes * 3 >= (yes + no) * 2 and yes > 0
		_:
			passed = yes > no
	return {"yes": yes, "no": no, "passed": passed and not vetoed, "vetoed": vetoed}


static func expected_join(state: SimState, org_id: String, applicant: String) -> Dictionary:
	if is_custom(state, org_id):
		return {"yes": 0, "no": 0, "passed": false, "vetoed": false}
	return member_vote(state, org_id, applicant, members(state, org_id),
		func(voter: String) -> float: return join_score(state, org_id, voter, applicant),
		str(rules_of(state, org_id).get("decision", "majority")))


static func expected_expulsion(state: SimState, org_id: String, target: String) -> Dictionary:
	var threshold := float(settings_of(state).get("expel_threshold", 0.0))
	return member_vote(state, org_id, target, members(state, org_id),
		func(voter: String) -> float: return threshold - state.diplomacy.relation(voter, target), "two_thirds")


static func is_custom(state: SimState, org_id: String) -> bool:
	return bool((state.diplomacy.organizations.get(org_id, {}) as Dictionary).get("custom", false))


## Bonus de relations entre membres d'une organisation.
static func relation_bonus(state: SimState, org_id: String) -> float:
	var rules := rules_of(state, org_id)
	if rules.has("relation_bonus"):
		return float(rules["relation_bonus"])
	var kind := str((state.diplomacy.organizations.get(org_id, {}) as Dictionary).get("kind", ""))
	return float((settings_of(state).get("kind_bonus", {}) as Dictionary).get(kind, 0.0))


static func add_member(state: SimState, org_id: String, tag: String) -> void:
	var diplomacy := state.diplomacy
	var bonus := relation_bonus(state, org_id)
	for member: Variant in members(state, org_id):
		var key := DiplomacyState.pair_key(tag, str(member))
		diplomacy.treaty_bonus[key] = float(diplomacy.treaty_bonus.get(key, 0.0)) + bonus
	(diplomacy.organizations[org_id]["members"] as Array).append(tag)
	_set_trade_membership(state, org_id, tag, true)


static func remove_member(state: SimState, org_id: String, tag: String) -> void:
	var diplomacy := state.diplomacy
	(diplomacy.organizations[org_id]["members"] as Array).erase(tag)
	var bonus := relation_bonus(state, org_id)
	for member: Variant in members(state, org_id):
		var key := DiplomacyState.pair_key(tag, str(member))
		diplomacy.treaty_bonus[key] = float(diplomacy.treaty_bonus.get(key, 0.0)) - bonus
	_set_trade_membership(state, org_id, tag, false)


static func _set_trade_membership(state: SimState, org_id: String, tag: String, member: bool) -> void:
	var agreement_id := str(rules_of(state, org_id).get("trade_agreement", ""))
	if agreement_id.is_empty() or not state.trade.agreements.has(agreement_id):
		return
	var agreement_members: Array = state.trade.agreements[agreement_id]["members"]
	if member and not agreement_members.has(tag):
		agreement_members.append(tag)
	elif not member:
		agreement_members.erase(tag)
	state.trade.refresh_pair_kinds(TradeModel.KIND_ORDER)
	state.trade.dirty = true
	TradeSystem.update_trade(state)


static func join(state: SimState, org_id: String, applicant: String) -> void:
	var settings := settings_of(state)
	state.diplomacy.set_cooldown("join_" + org_id, applicant, applicant, int(settings.get("join_cooldown", 0)))
	var vote := expected_join(state, org_id, applicant)
	if bool(vote["passed"]):
		add_member(state, org_id, applicant)
		state.add_event(EVENT_JOINED, applicant, {"organization": org_id})
	else:
		for member: Variant in members(state, org_id):
			if join_score(state, org_id, str(member), applicant) <= 0.0:
				state.diplomacy.change_relation(applicant, str(member), float(settings.get("refused_relation", 0.0)))
		state.add_event(EVENT_JOIN_REFUSED, applicant, {"organization": org_id, "yes": vote["yes"], "no": vote["no"]})


static func leave(state: SimState, org_id: String, tag: String) -> void:
	remove_member(state, org_id, tag)
	for member: Variant in members(state, org_id):
		state.diplomacy.change_relation(tag, str(member), float(settings_of(state).get("leave_relation", 0.0)))
	state.add_event(EVENT_LEFT, tag, {"organization": org_id})


static func expel(state: SimState, org_id: String, by: String, target: String) -> Dictionary:
	var vote := expected_expulsion(state, org_id, target)
	state.diplomacy.set_cooldown("expel_" + org_id, by, target, int(settings_of(state).get("join_cooldown", 0)))
	if bool(vote["passed"]):
		remove_member(state, org_id, target)
		state.diplomacy.change_relation(by, target, float(settings_of(state).get("expel_relation", 0.0)))
		state.add_event(EVENT_EXPELLED, by, {"organization": org_id, "target": target})
	return vote


static func create(state: SimState, founder: String, org_name: String, kind: String) -> String:
	var diplomacy := state.diplomacy
	var org_id := "%s%d" % [CUSTOM_PREFIX, diplomacy.next_organization_id]
	diplomacy.next_organization_id += 1
	var color := Color.from_hsv(float(absi(org_id.hash()) % 360) / 360.0, 0.55, 0.8)
	diplomacy.organizations[org_id] = {"kind": kind, "name": org_name, "abbreviation": abbreviate(org_name),
		"color": "#" + color.to_html(false), "members": [founder], "custom": true}
	state.add_event(EVENT_CREATED, founder, {"organization": org_id})
	return org_id


static func abbreviate(text: String) -> String:
	var result := ""
	for word: String in text.split(" ", false):
		if word.length() > 2:
			result += word.substr(0, 1).to_upper()
	return result if not result.is_empty() else text.substr(0, 3).to_upper()


## Le pays invité accepte selon ses relations avec l'hôte et avec les membres.
static func invite_score(state: SimState, org_id: String, host: String, target: String) -> float:
	var weight := float(settings_of(state).get("invite_member_weight", 0.5))
	var total := 0.0
	var current := members(state, org_id)
	for member: Variant in current:
		total += state.diplomacy.relation(target, str(member))
	var average := total / current.size() if not current.is_empty() else 0.0
	var kind := str((state.diplomacy.organizations.get(org_id, {}) as Dictionary).get("kind", ""))
	var base := float((settings_of(state).get("kind_vote_base", {}) as Dictionary).get(kind, 0.0))
	return base + (1.0 - weight) * state.diplomacy.relation(target, host) + weight * average


static func invite(state: SimState, org_id: String, host: String, target: String) -> bool:
	state.diplomacy.set_cooldown("invite_" + org_id, host, target, int(settings_of(state).get("join_cooldown", 0)))
	var accepted := target == str(state.player_tag) or invite_score(state, org_id, host, target) > 0.0
	if accepted:
		add_member(state, org_id, target)
		state.add_event(EVENT_JOINED, target, {"organization": org_id})
	else:
		state.add_event(EVENT_JOIN_REFUSED, target, {"organization": org_id, "yes": 0, "no": 1})
	return accepted


## Conseil de sécurité : chaque janvier, les sièges arrivés à échéance sont attribués à d'autres membres de
## l'ONU (les sortants ne sont pas rééligibles aussitôt).
static func renew_council(state: SimState) -> void:
	var diplomacy := state.diplomacy
	var settings := settings_of(state)
	var outgoing: Array = []
	for tag: Variant in diplomacy.security_council.keys():
		var end := int(diplomacy.security_council[tag])
		if end > 0 and end < state.date.year:
			diplomacy.security_council.erase(tag)
			outgoing.append(tag)
	var candidates: Array = members(state, UN).filter(func(tag: Variant) -> bool:
		return not diplomacy.security_council.has(tag) and not outgoing.has(tag))
	candidates.sort()
	var elected := diplomacy.security_council.values().filter(func(end: Variant) -> bool: return int(end) > 0).size()
	while elected < int(settings.get("council_seats", 0)) and not candidates.is_empty():
		var index := state.rng.randi_range(0, candidates.size() - 1)
		diplomacy.security_council[candidates[index]] = state.date.year + int(settings.get("council_term", 1)) - 1
		candidates.remove_at(index)
		elected += 1


## Vote d'un pays sur une résolution condamnant target, proposée par proposer : 1 pour, -1 contre, 0 abstention.
static func resolution_vote(state: SimState, voter: String, proposer: String, target: String) -> int:
	if voter == target:
		return -1
	if voter == proposer:
		return 1
	var threshold := float((settings_of(state).get("resolution", {}) as Dictionary).get("vote_threshold", 0.0))
	var difference := state.diplomacy.relation(voter, proposer) - state.diplomacy.relation(voter, target)
	return 1 if difference > threshold else -1 if difference < -threshold else 0


## Résultat attendu d'une résolution : {yes, no, abstain, passed, vetoed}.
static func expected_resolution(state: SimState, body: String, proposer: String, target: String) -> Dictionary:
	var settings: Dictionary = settings_of(state).get("resolution", {})
	var voters: Array = state.diplomacy.security_council.keys() if body == SECURITY_COUNCIL else members(state, UN)
	var result := {"yes": 0, "no": 0, "abstain": 0, "vetoed": false}
	for voter: Variant in voters:
		var vote := resolution_vote(state, str(voter), proposer, target)
		var key := "yes" if vote > 0 else "no" if vote < 0 else "abstain"
		result[key] = int(result[key]) + 1
		if vote < 0 and body == SECURITY_COUNCIL and int(state.diplomacy.security_council[voter]) == 0:
			result["vetoed"] = true
	if body == SECURITY_COUNCIL:
		result["passed"] = int(result["yes"]) >= int(settings.get("council_majority", 9)) and not bool(result["vetoed"])
	else:
		result["passed"] = int(result["yes"]) > int(result["no"])
	return result


## kind : condamnation, ou sanctions (Conseil de sécurité seulement : tous les membres de l'ONU appliquent alors
## les mesures « un_measures »).
static func vote_resolution(state: SimState, body: String, proposer: String, target: String,
		kind: String = RESOLUTION_CONDEMN) -> Dictionary:
	var settings: Dictionary = settings_of(state).get("resolution", {})
	var result := expected_resolution(state, body, proposer, target)
	var diplomacy := state.diplomacy
	diplomacy.set_cooldown("resolution", proposer, target, int(settings.get("cooldown", 0)))
	var voters: Array = diplomacy.security_council.keys() if body == SECURITY_COUNCIL else members(state, UN)
	if bool(result["passed"]):
		for voter: Variant in voters:
			if resolution_vote(state, str(voter), proposer, target) > 0 and str(voter) != target:
				diplomacy.change_relation(str(voter), target, float(settings.get("passed_target_relation", 0.0)))
		var country := state.get_country(target)
		if country != null:
			country.society.start_legitimacy += float(settings.get("%s_legitimacy" % body, 0.0))
		if kind == RESOLUTION_SANCTIONS:
			for member: Variant in members(state, UN):
				if str(member) != target:
					for measure: Variant in SanctionSystem.settings_of(state).get("un_measures", []):
						SanctionSystem._add(state, str(member), target, str(measure))
			SanctionSystem.refresh_all(state)
	else:
		for voter: Variant in voters:
			if resolution_vote(state, str(voter), proposer, target) < 0:
				diplomacy.change_relation(proposer, str(voter), float(settings.get("failed_proposer_relation", 0.0)))
	state.add_event(EVENT_RESOLUTION, proposer, {"body": body, "kind": kind, "target": target, "passed": result["passed"],
		"yes": result["yes"], "no": result["no"], "vetoed": result["vetoed"]})
	return result

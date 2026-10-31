class_name InfluenceSystem
extends SimSystem
## Sphères d'influence, une fois par mois : revenu de points d'influence (poids économique et budget de la
## diplomatie), lent retour de l'influence vers son niveau de départ. L'influence d'un pays dans un autre
## (0 à 100) part du commerce, des bases, des alliances et de l'aide ; elle facilite l'acceptation de nos
## traités, de notre aide et de nos adhésions, et oriente les votes à l'ONU. Les actions (soutenir un parti,
## financer l'opposition, influence culturelle, bases) se paient en points.

const PRIORITY := 32
const EVENT_INFLUENCE := &"influence_action"
const LIMIT := 100.0
const START_MONTHS := 6.0
const ACTIONS := ["support_party", "fund_opposition", "soft_power", "open_base", "close_base"]


func get_id() -> StringName:
	return &"influence"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	var settings := settings_of(state)
	if settings.is_empty():
		return
	var diplomacy := state.diplomacy
	var world := 0.0
	for tag: String in state.countries.keys():
		world += TradeSystem.current_gdp(state, tag)
	var cap_months := float(settings.get("cap_months", INF))
	for tag: String in state.countries.keys():
		var income := monthly_income(state, tag, world)
		diplomacy.influence_points[tag] = minf(float(diplomacy.influence_points.get(tag, 0.0)) + income,
			income * cap_months)
	var decay := float(settings.get("change_decay", 0.0))
	for key: Variant in diplomacy.influence_changes.keys():
		var value := float(diplomacy.influence_changes[key]) * (1.0 - decay)
		if absf(value) < DiplomacySystem.CLEANUP:
			diplomacy.influence_changes.erase(key)
		else:
			diplomacy.influence_changes[key] = value


static func settings_of(state: SimState) -> Dictionary:
	return state.diplomacy_settings.get("influence", {})


## Points gagnés par mois : base, poids économique (racine de la part du PIB mondial), budget de la diplomatie.
static func monthly_income(state: SimState, tag: String, world_gdp: float) -> float:
	var settings := settings_of(state)
	var country := state.get_country(tag)
	var share := TradeSystem.current_gdp(state, tag) / world_gdp if world_gdp > 0.0 else 0.0
	var budget := float(country.economy.budget.effects.get("influence", 0.0)) if country != null else 0.0
	return maxf(float(settings.get("income_base", 0.0)) + float(settings.get("income_scale", 0.0)) * sqrt(share)
		+ float(settings.get("budget_factor", 0.0)) * budget, 0.0)


## Influence de holder dans target (0 à 100).
static func influence(state: SimState, holder: String, target: String) -> float:
	if holder == target:
		return 0.0
	var diplomacy := state.diplomacy
	var key := DiplomacyState.opinion_key(holder, target)
	var value := float(diplomacy.start_influence.get(key, 0.0)) + float(diplomacy.influence_changes.get(key, 0.0))
	if diplomacy.bases.has(key) and not diplomacy.start_bases.has(key):
		value += float((settings_of(state).get("start", {}) as Dictionary).get("base", 0.0))
	return clampf(value, 0.0, LIMIT)


## Influence de départ : dépendance commerciale, bases (accès militaire), alliances, programmes d'aide.
static func setup_start(state: SimState) -> void:
	var diplomacy := state.diplomacy
	var rules: Dictionary = settings_of(state).get("start", {})
	if rules.is_empty():
		return
	var raw: Dictionary = {}
	var cache: Dictionary = {}
	for target: String in state.countries.keys():
		for holder: String in state.countries.keys():
			if holder != target:
				var trade := SanctionSystem.share(state, target, holder, cache)
				if trade > 0.0:
					raw[DiplomacyState.opinion_key(holder, target)] = float(rules.get("trade", 0.0)) * trade
	for treaty: Dictionary in diplomacy.treaties.values():
		var key := DiplomacyState.opinion_key(str(treaty["a"]), str(treaty["b"]))
		match str(treaty["type"]):
			"military_access":
				diplomacy.bases[key] = true
				diplomacy.start_bases[key] = true
				raw[key] = float(raw.get(key, 0.0)) + float(rules.get("base", 0.0))
			"mutual_defense":
				for pair_key: String in [key, DiplomacyState.opinion_key(str(treaty["b"]), str(treaty["a"]))]:
					raw[pair_key] = float(raw.get(pair_key, 0.0)) + float(rules.get("mutual_defense", 0.0))
	for program: Dictionary in diplomacy.aid_programs:
		var key := DiplomacyState.opinion_key(str(program["donor"]), str(program["recipient"]))
		raw[key] = float(raw.get(key, 0.0)) + float(rules.get("aid", 0.0))
	var minimum := float(rules.get("min_stored", 0.0))
	for key: String in raw.keys():
		if float(raw[key]) >= minimum:
			diplomacy.start_influence[key] = minf(float(raw[key]), LIMIT)
	# Réserve de départ : six mois de revenu.
	var world := 0.0
	for tag: String in state.countries.keys():
		world += TradeSystem.current_gdp(state, tag)
	for tag: String in state.countries.keys():
		diplomacy.influence_points[tag] = monthly_income(state, tag, world) * START_MONTHS


## Action d'influence : coût en points, effets, risque d'être démasqué (presse libre de la cible).
static func perform(state: SimState, actor: String, target: String, action: String, party_id: String) -> void:
	var settings: Dictionary = (settings_of(state).get("actions", {}) as Dictionary).get(action, {})
	var diplomacy := state.diplomacy
	var country := state.get_country(target)
	var key := DiplomacyState.opinion_key(actor, target)
	diplomacy.influence_points[actor] = float(diplomacy.influence_points.get(actor, 0.0)) - float(settings.get("cost", 0.0))
	diplomacy.set_cooldown("influence_" + action, actor, target, int(settings.get("cooldown", 0)))
	diplomacy.influence_changes[key] = float(diplomacy.influence_changes.get(key, 0.0)) + float(settings.get("influence", 0.0))
	match action:
		"support_party":
			var party: PartyState = country.politics.parties.get(party_id)
			if party != null:
				party.drift += float(settings.get("drift", 0.0))
				if not country.politics.is_in_government(party_id):
					diplomacy.change_relation(actor, target, float(settings.get("government_relation", 0.0)))
		"fund_opposition":
			country.society.stability = maxf(country.society.stability - float(settings.get("stability", 0.0)), 0.0)
			var opposition := MediaSystem._main_opposition(country.politics)
			if opposition != null:
				opposition.drift += float(settings.get("drift", 0.0))
		"soft_power":
			diplomacy.change_opinion(target, actor, float(settings.get("opinion", 0.0)))
		"open_base":
			diplomacy.bases[key] = true
			diplomacy.change_relation(actor, target, float(settings.get("relation", 0.0)))
		"close_base":
			diplomacy.bases.erase(key)
			diplomacy.start_bases.erase(key)
			diplomacy.change_relation(actor, target, float(settings.get("relation", 0.0)))
	var exposed := settings.has("exposure") and state.rng.randf() < float(settings["exposure"]) * country.politics.media_factor
	if exposed:
		diplomacy.change_relation(actor, target, float(settings.get("exposed_relation", 0.0)))
	state.add_event(EVENT_INFLUENCE, actor, {"target": target, "action": action, "exposed": exposed})


## Poids de l'influence dans les décisions des pays de l'IA (réglage « weights »).
static func weight(state: SimState, decision: String) -> float:
	return float((settings_of(state).get("weights", {}) as Dictionary).get(decision, 0.0))

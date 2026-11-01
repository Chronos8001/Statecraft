class_name CrisisSystem
extends SimSystem
## Crises intérieures, une fois par mois, avant la société :
## - grèves, manifestations et émeutes quand un groupe social perd beaucoup de satisfaction depuis le départ ;
## - guerre civile après six mois de stabilité effondrée et de légitimité basse ;
## - coup d'État quand l'armée est mécontente et le pouvoir peu légitime (hors démocraties solides).
## Les crises en cours pèsent sur la croissance, la stabilité et la légitimité visées. Les pays de l'IA
## répondent aussitôt (négociation en démocratie, répression ailleurs) ; le joueur choisit sa réponse.

const PRIORITY := 8
const EVENT_STARTED := &"unrest_started"
const EVENT_ENDED := &"unrest_ended"
const EVENT_COUP := &"coup"
const CIVIL_WAR := "civil_war"
const RESPONSE_CONCEDE := "concede"
const RESPONSE_NEGOTIATE := "negotiate"
const RESPONSE_REPRESS := "repress"
const JUNTA := "military_junta"
const MILITARY_GROUP := "military"


func get_id() -> StringName:
	return &"crises"


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


static func settings_of(state: SimState) -> Dictionary:
	return (state.politics_definitions.get("settings", {}) as Dictionary).get("crises", {})


static func update_country(country: CountryState, state: SimState) -> void:
	var definitions: Dictionary = state.politics_definitions.get("crises", {})
	if definitions.is_empty():
		return
	_advance(country, state)
	var types: Array = definitions.keys()
	types.sort()
	for crisis_type: String in types:
		var definition: Dictionary = definitions[crisis_type]
		if str(definition["kind"]) == "group":
			for group_id: Variant in definition["groups"]:
				_try_group_crisis(country, state, crisis_type, definition, str(group_id))
	_check_civil_war(country, state, definitions.get(CIVIL_WAR, {}))
	_check_coup(country, state)
	refresh_effects(country, state)


## Fait avancer les crises en cours, fin des crises et des concessions arrivées à terme.
static func _advance(country: CountryState, state: SimState) -> void:
	var settings := settings_of(state)
	var remaining: Array[Dictionary] = []
	for crisis: Dictionary in country.crises:
		crisis["months_left"] = int(crisis["months_left"]) - 1
		if str(crisis["type"]) == CIVIL_WAR:
			# Avec une guerre civile sur la carte, ce sont les combats qui décident de la fin (WarSystem).
			if WarSystem.civil_war_of(state, country.tag) != null:
				remaining.append(crisis)
				continue
			var ending := country.society.stability >= float(settings.get("civil_war_end_stability", 0.0)) \
				and state.rng.randf() < float(settings.get("civil_war_end_chance", 0.0))
			if ending or int(crisis["months_left"]) <= 0:
				country.society.start_stability += float(settings.get("peace_stability", 0.0)) \
					if bool(crisis.get("initial", false)) else 0.0
				state.add_event(EVENT_ENDED, country.tag, {"crisis": CIVIL_WAR})
				continue
		elif int(crisis["months_left"]) <= 0:
			state.add_event(EVENT_ENDED, country.tag, {"crisis": crisis["type"], "group": crisis.get("group", "")})
			continue
		remaining.append(crisis)
	country.crises = remaining
	var bonuses: Array[Dictionary] = []
	for bonus: Dictionary in country.crisis_bonuses:
		bonus["months_left"] = int(bonus["months_left"]) - 1
		if int(bonus["months_left"]) <= 0:
			var group_id := str(bonus["group"])
			country.society.bonuses[group_id] = float(country.society.bonuses.get(group_id, 0.0)) - float(bonus["points"])
		else:
			bonuses.append(bonus)
	country.crisis_bonuses = bonuses


static func has_crisis(country: CountryState, crisis_type: String, group_id: String = "") -> bool:
	return country.crises.any(func(crisis: Dictionary) -> bool:
		return str(crisis["type"]) == crisis_type and (group_id.is_empty() or str(crisis.get("group", "")) == group_id))


static func _try_group_crisis(country: CountryState, state: SimState, crisis_type: String, definition: Dictionary,
		group_id: String) -> void:
	var society := country.society
	if not society.satisfaction.has(group_id) or has_crisis(country, crisis_type, group_id):
		return
	var trigger: Dictionary = definition["trigger"]
	var drop := float(society.start_satisfaction[group_id]) - float(society.satisfaction[group_id])
	var needed := float(trigger.get("satisfaction_drop", 0.0))
	if drop < needed:
		return
	if trigger.has("stability_drop") and society.start_stability - society.stability < float(trigger["stability_drop"]):
		return
	var settings := settings_of(state)
	var chance := minf(float(definition["chance"]) * (1.0 + (drop - needed) / float(settings.get("drop_scale", 1.0))),
		float(settings.get("max_group_chance", 1.0)))
	if state.rng.randf() >= chance:
		return
	var duration: Array = definition["duration"]
	var crisis := {"id": state.next_crisis_id, "type": crisis_type, "group": group_id,
		"months_left": state.rng.randi_range(int(duration[0]), int(duration[1]))}
	state.next_crisis_id += 1
	country.crises.append(crisis)
	state.add_event(EVENT_STARTED, country.tag, {"crisis": crisis_type, "group": group_id, "id": crisis["id"]})
	if country.tag != str(state.player_tag) and bool(definition.get("responses", false)):
		respond(country, state, int(crisis["id"]), RESPONSE_NEGOTIATE if country.politics.democratic else RESPONSE_REPRESS)


static func _check_civil_war(country: CountryState, state: SimState, definition: Dictionary) -> void:
	if definition.is_empty() or has_crisis(country, CIVIL_WAR):
		country.collapse_months = 0
		return
	var trigger: Dictionary = definition["trigger"]
	var society := country.society
	var collapsing := society.stability < float(trigger.get("stability_below", 0.0)) \
		and society.start_stability - society.stability >= float(trigger.get("stability_drop", 0.0)) \
		and society.legitimacy < float(trigger.get("legitimacy_below", 0.0))
	country.collapse_months = country.collapse_months + 1 if collapsing else 0
	if country.collapse_months < int(trigger.get("months", 1)):
		return
	country.collapse_months = 0
	start_civil_war(country, state, definition, false)


static func start_civil_war(country: CountryState, state: SimState, definition: Dictionary, initial: bool) -> void:
	var duration: Array = definition.get("duration", [1, 1])
	country.crises.append({"id": state.next_crisis_id, "type": CIVIL_WAR, "group": "", "initial": initial,
		"months_left": state.rng.randi_range(int(duration[0]), int(duration[1]))})
	state.next_crisis_id += 1
	if not initial:
		TensionSystem.add_event(state, "civil_war")
		state.add_event(EVENT_STARTED, country.tag, {"crisis": CIVIL_WAR})
		WarSystem.start_civil_war(state, country.tag)


## Fin d'une guerre civile décidée par les combats : la crise s'arrête (stabilité retrouvée pour une guerre
## déjà en cours en 2026, comme à la fin d'une crise).
static func end_civil_war_crisis(country: CountryState, state: SimState) -> void:
	var settings := settings_of(state)
	for index: int in country.crises.size():
		var crisis: Dictionary = country.crises[index]
		if str(crisis["type"]) != CIVIL_WAR:
			continue
		country.crises.remove_at(index)
		if bool(crisis.get("initial", false)):
			country.society.start_stability += float(settings.get("peace_stability", 0.0))
		state.add_event(EVENT_ENDED, country.tag, {"crisis": CIVIL_WAR})
		refresh_effects(country, state)
		return


## Coup d'État : armée mécontente, pouvoir peu légitime, démocratie fragile ou absente.
static func _check_coup(country: CountryState, state: SimState) -> void:
	var settings: Dictionary = settings_of(state).get("coup", {})
	var society := country.society
	var politics := country.politics
	if politics.regime == JUNTA or not society.satisfaction.has(MILITARY_GROUP):
		return
	var drop := float(society.start_satisfaction[MILITARY_GROUP]) - float(society.satisfaction[MILITARY_GROUP])
	if drop < float(settings.get("military_drop", 0.0)) or society.legitimacy >= float(settings.get("legitimacy_below", 0.0)) \
			or society.democracy_index >= float(settings.get("democracy_below", 0.0)):
		return
	if state.rng.randf() >= float(settings.get("chance", 0.0)):
		return
	var success := float(settings.get("success_base", 0.0)) + float(society.influence.get(MILITARY_GROUP, 0.0)) \
		- society.legitimacy / SocietyModel.PERCENT
	if state.rng.randf() < success:
		install_junta(country, state)
		TensionSystem.add_event(state, "coup")
		state.add_event(EVENT_COUP, country.tag, {"success": true})
	else:
		society.stability = maxf(society.stability - float(settings.get("failure_stability", 0.0)), 0.0)
		society.start_satisfaction[MILITARY_GROUP] = float(society.start_satisfaction[MILITARY_GROUP]) \
			- float(settings.get("failure_military", 0.0))
		state.add_event(EVENT_COUP, country.tag, {"success": false})


## La junte prend le pouvoir : un général dirige, plus d'élections ni de partis au gouvernement.
static func install_junta(country: CountryState, state: SimState) -> void:
	var settings: Dictionary = settings_of(state).get("coup", {})
	var politics := country.politics
	var society := country.society
	politics.regime = JUNTA
	politics.democratic = false
	politics.polls_published = false
	politics.executive = PoliticsState.EXECUTIVE_PRESIDENTIAL
	politics.has_presidency = false
	politics.suspended = true
	politics.government.clear()
	politics.promises.clear()
	politics.reset_campaign()
	var general := GovernmentModel.make_character(state, country, "", "%s|junta|%d|%d" % [country.tag, state.date.year,
		state.date.month])
	if not general.is_empty():
		general["traits"] = ["military_officer"]
		var character_id := "%s%d" % [GovernmentSystem.CHARACTER_PREFIX, state.next_character_id]
		state.next_character_id += 1
		state.characters[character_id] = general
		politics.head_of_state = character_id
		politics.head_of_government = character_id
	var regimes: Dictionary = state.society_definitions.get("regimes", {})
	var junta: Dictionary = regimes.get(JUNTA, {})
	society.influence = SocietyModel.influence_weights(society.group_shares, state.society_definitions.get("groups", {}),
		junta.get("group_influence", {}))
	society.legitimacy = float(junta.get("legitimacy", settings.get("junta_legitimacy", 0.0)))
	society.start_legitimacy = society.legitimacy
	society.stability = maxf(society.stability - float(settings.get("success_stability", 0.0)), 0.0)
	GovernmentSystem.form_cabinet(country, state)


## Réponse à une crise : concession (coût budgétaire, groupe apaisé), négociation (durée réduite, coût et
## gain moindres) ou répression (fin immédiate, légitimité et colère du groupe).
static func respond(country: CountryState, state: SimState, crisis_id: int, response: String) -> void:
	var index := -1
	for i: int in country.crises.size():
		if int(country.crises[i]["id"]) == crisis_id:
			index = i
	if index < 0:
		return
	var crisis: Dictionary = country.crises[index]
	var settings: Dictionary = (settings_of(state).get("responses", {}) as Dictionary).get(response, {})
	var group_id := str(crisis.get("group", ""))
	var gdp := TradeSystem.current_gdp(state, country.tag)
	if settings.has("cost_share"):
		InvestmentSystem.add_debt_usd(country, state, float(settings["cost_share"]) / SocietyModel.PERCENT * gdp)
	if settings.has("bonus") and not group_id.is_empty():
		var points := float(settings["bonus"])
		country.society.bonuses[group_id] = float(country.society.bonuses.get(group_id, 0.0)) + points
		country.crisis_bonuses.append({"group": group_id, "points": points,
			"months_left": int(settings.get("bonus_months", 1))})
	if response == RESPONSE_REPRESS:
		var society := country.society
		if not group_id.is_empty():
			society.start_satisfaction[group_id] = float(society.start_satisfaction[group_id]) \
				- float(settings.get("group_penalty", 0.0))
		society.start_legitimacy -= float(settings.get("legitimacy_democracy" if country.politics.democratic
			else "legitimacy_other", 0.0))
		society.stability = minf(society.stability + float(settings.get("stability", 0.0)), SocietyModel.PERCENT)
	crisis["response"] = response
	if bool(settings.get("end", false)):
		country.crises.remove_at(index)
		state.add_event(EVENT_ENDED, country.tag, {"crisis": crisis["type"], "group": group_id, "response": response})
	elif settings.has("duration_factor"):
		crisis["months_left"] = maxi(ceili(int(crisis["months_left"]) * float(settings["duration_factor"])), 1)
	refresh_effects(country, state)


## Effets des crises en cours (les guerres civiles déjà en cours en 2026 sont comprises dans les données).
static func refresh_effects(country: CountryState, state: SimState) -> void:
	var definitions: Dictionary = state.politics_definitions.get("crises", {})
	var effects := {"growth": 0.0, "stability": 0.0, "legitimacy": 0.0, "severity": 0}
	for crisis: Dictionary in country.crises:
		if bool(crisis.get("initial", false)):
			effects["severity"] = int(effects["severity"]) + int((definitions.get(crisis["type"], {}) as Dictionary).get(
				"severity", 0))
			continue
		var definition: Dictionary = definitions.get(crisis["type"], {})
		for key: String in ["growth", "stability", "legitimacy"]:
			effects[key] = float(effects[key]) + float((definition.get("effects", {}) as Dictionary).get(key, 0.0))
		effects["severity"] = int(effects["severity"]) + int(definition.get("severity", 0))
	country.crisis_effects = effects
	country.economy.crisis_growth = float(effects["growth"])

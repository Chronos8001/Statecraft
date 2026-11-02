class_name DecisionSystem
extends SimSystem
## Décisions ponctuelles et arbres de décisions nationaux (data/decisions, data/focus_trees).
## Décision : visible et disponible selon des conditions, coût payé au lancement (seulement s'il a un sens :
## argent, influence, stabilité, légitimité), durée en jours, effets à la fin, délai avant de la reprendre.
## Arbre : un nœud à la fois, durée en mois, prérequis (« requires » : tous, « requires_any » : au moins un),
## nœuds exclusifs (en prendre un ferme les autres), effets à la fin. Chaque pays suit l'arbre qui le cite,
## sinon l'arbre générique. Les pays de l'IA choisissent au hasard pondéré (en attendant l'étape 12).

const PRIORITY := -29
const EVENT_DECISION_DONE := &"decision_completed"
const EVENT_FOCUS_DONE := &"focus_completed"
const GENERIC_TREE := "generic"
const COST_KEYS := ["debt_gdp", "influence", "stability", "legitimacy"]
const PERCENT := 100.0


func get_id() -> StringName:
	return &"decisions"


func get_periods() -> Array[StringName]:
	return [DAILY, MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_day(state: SimState) -> void:
	var today := state.date.to_day_number()
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		if not country.decisions_active.is_empty():
			var ids: Array = country.decisions_active.keys()
			ids.sort()
			for id: String in ids:
				if int(country.decisions_active[id]) <= today:
					complete_decision(state, country, id)
		if not country.focus_current.is_empty() and country.focus_end_day <= today:
			complete_focus(state, country)


func on_month(state: SimState) -> void:
	var settings := settings_of(state)
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		if StringName(tag) == state.player_tag:
			continue
		var country: CountryState = state.countries[tag]
		if country.focus_current.is_empty():
			var node := ai_pick_focus(state, country)
			if not node.is_empty():
				start_focus(state, country, node)
		if state.rng.randf() < float(settings.get("ai_monthly_chance", 0.0)):
			var decision := ai_pick_decision(state, country)
			if not decision.is_empty():
				start_decision(state, country, decision)


static func settings_of(state: SimState) -> Dictionary:
	return state.decision_settings


## Range chaque pays sous son arbre (à appeler une fois les définitions chargées).
static func assign_trees(state: SimState) -> void:
	for country: CountryState in state.countries.values():
		country.focus_tree = GENERIC_TREE if state.focus_trees.has(GENERIC_TREE) else ""
	var ids: Array = state.focus_trees.keys()
	ids.sort()
	for tree_id: String in ids:
		for tag: Variant in (state.focus_trees[tree_id] as Dictionary).get("countries", []):
			var country := state.get_country(str(tag))
			if country != null:
				country.focus_tree = tree_id


static func _scope(country: CountryState) -> Dictionary:
	return {"country": country.tag, "from": ""}


# --- Décisions ---------------------------------------------------------------------------------------------------

static func is_visible(state: SimState, country: CountryState, id: String) -> bool:
	var definition: Dictionary = state.decision_definitions.get(id, {})
	return not definition.is_empty() and ScriptConditions.evaluate(state, _scope(country), definition.get("visible", null))


## Raison du refus (clé de localisation), ou "" si la décision peut être prise.
static func decision_refusal(state: SimState, country: CountryState, id: String) -> String:
	if not is_visible(state, country, id):
		return "DECISION_UNKNOWN"
	if country.decisions_active.has(id):
		return "DECISION_ACTIVE"
	if int(country.decision_ready.get(id, 0)) > state.date.to_day_number():
		return "DECISION_COOLDOWN"
	var definition: Dictionary = state.decision_definitions[id]
	if not ScriptConditions.evaluate(state, _scope(country), definition.get("available", null)):
		return "DECISION_UNAVAILABLE"
	if not can_pay(state, country, definition.get("cost", {})):
		return "DECISION_TOO_EXPENSIVE"
	return ""


static func can_pay(state: SimState, country: CountryState, cost: Dictionary) -> bool:
	if float(cost.get("influence", 0.0)) > float(state.diplomacy.influence_points.get(country.tag, 0.0)):
		return false
	if float(cost.get("stability", 0.0)) > country.society.stability:
		return false
	return float(cost.get("legitimacy", 0.0)) <= country.society.legitimacy


static func _pay(state: SimState, country: CountryState, cost: Dictionary) -> void:
	if cost.has("debt_gdp"):
		InvestmentSystem.add_debt_usd(country, state, TradeSystem.current_gdp(state, country.tag)
			* float(cost["debt_gdp"]) / PERCENT)
	if cost.has("influence"):
		state.diplomacy.influence_points[country.tag] = float(state.diplomacy.influence_points.get(country.tag, 0.0)) \
			- float(cost["influence"])
	country.society.stability -= float(cost.get("stability", 0.0))
	country.society.legitimacy -= float(cost.get("legitimacy", 0.0))


## Lance une décision : coût et effets de départ aussitôt, effets principaux à la fin (aussitôt sans durée).
static func start_decision(state: SimState, country: CountryState, id: String) -> bool:
	if not decision_refusal(state, country, id).is_empty():
		return false
	var definition: Dictionary = state.decision_definitions[id]
	_pay(state, country, definition.get("cost", {}))
	ScriptEffects.apply(state, _scope(country), definition.get("on_start", {}))
	var days := int(definition.get("days", 0))
	if days <= 0:
		_finish_decision(state, country, id)
	else:
		country.decisions_active[id] = state.date.to_day_number() + days
	return true


static func complete_decision(state: SimState, country: CountryState, id: String) -> void:
	country.decisions_active.erase(id)
	_finish_decision(state, country, id)


static func _finish_decision(state: SimState, country: CountryState, id: String) -> void:
	var definition: Dictionary = state.decision_definitions[id]
	ScriptEffects.apply(state, _scope(country), definition.get("effects", {}))
	var cooldown := int(definition.get("cooldown_days", -1))
	# Sans délai, une décision ne se prend qu'une fois.
	country.decision_ready[id] = state.date.to_day_number() + cooldown if cooldown >= 0 else 1 << 30
	state.add_event(EVENT_DECISION_DONE, country.tag, {"decision": id})


## Annule une décision en cours : le coût n'est pas rendu.
static func cancel_decision(state: SimState, country: CountryState, id: String) -> bool:
	if not country.decisions_active.has(id):
		return false
	country.decisions_active.erase(id)
	var definition: Dictionary = state.decision_definitions.get(id, {})
	country.decision_ready[id] = state.date.to_day_number() + maxi(int(definition.get("cooldown_days", 0)), 0)
	return true


static func ai_pick_decision(state: SimState, country: CountryState) -> String:
	var ids: Array = state.decision_definitions.keys()
	ids.sort()
	var candidates: Array[String] = []
	for id: String in ids:
		if bool((state.decision_definitions[id] as Dictionary).get("player_only", false)):
			continue
		if decision_refusal(state, country, id).is_empty():
			candidates.append(id)
	return _weighted(state, country, candidates, state.decision_definitions)


# --- Arbres ------------------------------------------------------------------------------------------------------

static func tree_nodes(state: SimState, country: CountryState) -> Dictionary:
	return (state.focus_trees.get(country.focus_tree, {}) as Dictionary).get("nodes", {})


## Raison du refus pour un nœud de l'arbre du pays, ou "".
static func focus_refusal(state: SimState, country: CountryState, node_id: String) -> String:
	var nodes := tree_nodes(state, country)
	if not nodes.has(node_id):
		return "FOCUS_UNKNOWN"
	if country.focus_done.has(node_id):
		return "FOCUS_DONE"
	if is_excluded(state, country, node_id):
		return "FOCUS_EXCLUDED"
	if not country.focus_current.is_empty():
		return "FOCUS_BUSY"
	var node: Dictionary = nodes[node_id]
	for required: Variant in node.get("requires", []):
		if not country.focus_done.has(str(required)):
			return "FOCUS_MISSING_PREREQUISITE"
	var any: Array = node.get("requires_any", [])
	if not any.is_empty() and not any.any(func(required: Variant) -> bool: return country.focus_done.has(str(required))):
		return "FOCUS_MISSING_PREREQUISITE"
	if not ScriptConditions.evaluate(state, _scope(country), node.get("available", null)):
		return "FOCUS_UNAVAILABLE"
	return ""


## Un nœud exclusif d'un nœud déjà fait ou en cours est fermé (l'exclusion vaut dans les deux sens).
static func is_excluded(state: SimState, country: CountryState, node_id: String) -> bool:
	var nodes := tree_nodes(state, country)
	var taken: Array = country.focus_done.keys()
	if not country.focus_current.is_empty():
		taken.append(country.focus_current)
	for other: Variant in taken:
		if ((nodes.get(str(other), {}) as Dictionary).get("exclusive", []) as Array).has(node_id):
			return true
		if ((nodes.get(node_id, {}) as Dictionary).get("exclusive", []) as Array).has(str(other)):
			return true
	return false


static func start_focus(state: SimState, country: CountryState, node_id: String) -> bool:
	if not focus_refusal(state, country, node_id).is_empty():
		return false
	var node: Dictionary = tree_nodes(state, country)[node_id]
	country.focus_current = node_id
	country.focus_start_day = state.date.to_day_number()
	country.focus_end_day = country.focus_start_day + roundi(float(node.get("months", 0))
		* float(settings_of(state).get("days_per_month", 30.0)))
	return true


static func complete_focus(state: SimState, country: CountryState) -> void:
	var node_id := country.focus_current
	var node: Dictionary = tree_nodes(state, country).get(node_id, {})
	country.focus_current = ""
	country.focus_done[node_id] = true
	ScriptEffects.apply(state, _scope(country), node.get("effects", {}))
	state.add_event(EVENT_FOCUS_DONE, country.tag, {"focus": node_id})


## Abandonne le nœud en cours (l'avancement est perdu).
static func cancel_focus(country: CountryState) -> bool:
	if country.focus_current.is_empty():
		return false
	country.focus_current = ""
	return true


## Avancement du nœud en cours (0 à 1).
static func focus_progress(state: SimState, country: CountryState) -> float:
	if country.focus_current.is_empty():
		return 0.0
	var total := maxi(country.focus_end_day - country.focus_start_day, 1)
	return clampf(float(state.date.to_day_number() - country.focus_start_day) / total, 0.0, 1.0)


static func ai_pick_focus(state: SimState, country: CountryState) -> String:
	var nodes := tree_nodes(state, country)
	var ids: Array = nodes.keys()
	ids.sort()
	var candidates: Array[String] = []
	for id: String in ids:
		if focus_refusal(state, country, id).is_empty():
			candidates.append(id)
	return _weighted(state, country, candidates, nodes)


## Choix pondéré par « ai_weight » et ses facteurs « ai_modifiers ».
static func _weighted(state: SimState, country: CountryState, candidates: Array[String], definitions: Dictionary) -> String:
	if candidates.is_empty():
		return ""
	var weights: Array[float] = []
	var total := 0.0
	for id: String in candidates:
		var definition: Dictionary = definitions[id]
		var weight := float(definition.get("ai_weight", 1.0))
		for modifier: Variant in definition.get("ai_modifiers", []):
			if ScriptConditions.evaluate(state, _scope(country), (modifier as Dictionary).get("if", null)):
				weight *= float((modifier as Dictionary).get("factor", 1.0))
		weights.append(maxf(weight, 0.0))
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return ""
	var roll := state.rng.randf() * total
	for index: int in candidates.size():
		roll -= weights[index]
		if roll < 0.0:
			return candidates[index]
	return candidates[candidates.size() - 1]


# --- Validation --------------------------------------------------------------------------------------------------

static func validate_definitions(decisions: Dictionary, trees: Dictionary, event_ids: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for id: Variant in decisions.keys():
		var definition: Dictionary = decisions[id]
		var where := "décision %s" % str(id)
		errors.append_array(ScriptConditions.validate(definition.get("visible", null), where + " (visible)"))
		errors.append_array(ScriptConditions.validate(definition.get("available", null), where + " (disponible)"))
		errors.append_array(ScriptEffects.validate(definition.get("on_start", {}), where + " (départ)", event_ids))
		errors.append_array(ScriptEffects.validate(definition.get("effects", {}), where, event_ids))
		for key: Variant in (definition.get("cost", {}) as Dictionary).keys():
			if not COST_KEYS.has(str(key)):
				errors.append("%s : coût inconnu « %s »" % [where, str(key)])
		for modifier: Variant in definition.get("ai_modifiers", []):
			errors.append_array(ScriptConditions.validate((modifier as Dictionary).get("if", null), where + " (IA)"))
	for tree_id: Variant in trees.keys():
		var nodes: Dictionary = (trees[tree_id] as Dictionary).get("nodes", {})
		for node_id: Variant in nodes.keys():
			var node: Dictionary = nodes[node_id]
			var where := "arbre %s, nœud %s" % [str(tree_id), str(node_id)]
			for key: String in ["requires", "requires_any", "exclusive"]:
				for other: Variant in node.get(key, []):
					if not nodes.has(str(other)):
						errors.append("%s : nœud inconnu « %s » (%s)" % [where, str(other), key])
			errors.append_array(ScriptConditions.validate(node.get("available", null), where))
			errors.append_array(ScriptEffects.validate(node.get("effects", {}), where, event_ids))
			for modifier: Variant in node.get("ai_modifiers", []):
				errors.append_array(ScriptConditions.validate((modifier as Dictionary).get("if", null), where + " (IA)"))
	return errors

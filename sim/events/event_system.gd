class_name EventSystem
extends SimSystem
## Événements scriptés (data/events/*.json) :
## - chaque mois, un événement dont le déclencheur est vrai survient avec une chance tirée de son délai moyen
##   (MTTH, en mois, modulé par des facteurs) ; portée « country » (tiré pour chaque pays) ou « world » ;
## - « once » : une seule fois (par pays, ou pour le monde) ; « triggered_only » : seulement par une chaîne ;
## - effets immédiats, puis 1 à 4 choix : l'IA choisit selon des poids, le joueur dans une fenêtre (le jeu
##   se met en pause) ; un événement mondial propose ses choix au joueur pour son pays ;
## - chaînes : un effet « trigger_event » programme un événement, aussitôt ou après quelques jours ;
## - modificateurs temporaires (croissance, chômage, stabilité visée) décomptés chaque mois.

const PRIORITY := -30
const EVENT_PENDING := &"script_event_pending"
const EVENT_FIRED := &"script_event_fired"
const EVENT_CHOSEN := &"script_event_chosen"
const SCOPE_WORLD := "world"
const WORLD_KEY := "world"
const MAX_OPTIONS := 4


func get_id() -> StringName:
	return &"events"


func get_periods() -> Array[StringName]:
	return [DAILY, MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_day(state: SimState) -> void:
	if state.scheduled_events.is_empty():
		return
	var today := state.date.to_day_number()
	var due: Array[Dictionary] = []
	for entry: Dictionary in state.scheduled_events:
		if int(entry["day"]) <= today:
			due.append(entry)
	for entry: Dictionary in due:
		state.scheduled_events.erase(entry)
		fire(state, str(entry["id"]), {"country": str(entry["country"]), "from": str(entry["from"])})


func on_month(state: SimState) -> void:
	for country: CountryState in state.countries.values():
		tick_modifiers(country)
	draw(state)


# --- Tirage ------------------------------------------------------------------------------------------------------

static func draw(state: SimState) -> void:
	var ids: Array = state.event_definitions.keys()
	ids.sort()
	var tags: Array = state.countries.keys()
	tags.sort()
	for id: String in ids:
		var definition: Dictionary = state.event_definitions[id]
		if bool(definition.get("triggered_only", false)) or not definition.has("mtth_months"):
			continue
		if str(definition.get("scope", "country")) == SCOPE_WORLD:
			_try(state, id, definition, {"country": "", "from": ""})
		else:
			for tag: String in tags:
				_try(state, id, definition, {"country": tag, "from": ""})


static func _try(state: SimState, id: String, definition: Dictionary, scope: Dictionary) -> void:
	if bool(definition.get("once", false)) and has_fired(state, id, str(scope["country"])):
		return
	if _pending_index(state, str(scope["country"]) if not str(scope["country"]).is_empty() else str(state.player_tag),
			id) >= 0:
		return
	if not ScriptConditions.evaluate(state, scope, definition.get("trigger", null)):
		return
	if state.rng.randf() < monthly_chance(state, definition, scope):
		fire(state, id, scope)


## Chance par mois pour un délai moyen de MTTH mois (loi exponentielle), après ses facteurs.
static func monthly_chance(state: SimState, definition: Dictionary, scope: Dictionary) -> float:
	var mtth := float(definition.get("mtth_months", 0.0))
	for modifier: Variant in definition.get("mtth_modifiers", []):
		if ScriptConditions.evaluate(state, scope, (modifier as Dictionary).get("if", null)):
			mtth *= float((modifier as Dictionary).get("factor", 1.0))
	return 1.0 - exp(-1.0 / mtth) if mtth > 0.0 else 1.0


static func has_fired(state: SimState, id: String, tag: String) -> bool:
	return (state.events_fired.get(id, {}) as Dictionary).has(tag if not tag.is_empty() else WORLD_KEY)


## Programme un événement (chaîne) pour un pays, aujourd'hui ou dans quelques jours.
static func schedule(state: SimState, id: String, tag: String, from: String, days: int) -> void:
	if not state.event_definitions.has(id):
		return
	if days <= 0:
		fire(state, id, {"country": tag, "from": from})
		return
	state.scheduled_events.append({"id": id, "country": tag, "from": from,
		"day": state.date.to_day_number() + days})


# --- Déclenchement et choix --------------------------------------------------------------------------------------

## L'événement survient : effets immédiats, puis le choix (IA aussitôt, joueur dans une fenêtre).
static func fire(state: SimState, id: String, scope: Dictionary) -> void:
	var definition: Dictionary = state.event_definitions.get(id, {})
	if definition.is_empty():
		return
	var tag := str(scope.get("country", ""))
	var key := tag if not tag.is_empty() else WORLD_KEY
	if not state.events_fired.has(id):
		state.events_fired[id] = {}
	(state.events_fired[id] as Dictionary)[key] = true
	ScriptEffects.apply(state, scope, definition.get("immediate", {}))
	var world := tag.is_empty()
	state.add_event(EVENT_FIRED, tag, {"event": id, "world": world})
	var options: Array = definition.get("options", [])
	if options.is_empty():
		return
	var player := str(state.player_tag)
	var chooser := player if world else tag
	if chooser.is_empty() or state.get_country(chooser) == null:
		return
	var choice_scope := {"country": chooser, "from": str(scope.get("from", ""))}
	if chooser == player:
		state.pending_events.append({"id": id, "country": chooser, "from": choice_scope["from"]})
		state.add_event(EVENT_PENDING, chooser, {"event": id})
	else:
		choose(state, id, choice_scope, ai_choice(state, definition, choice_scope))


## Choix de l'IA, tiré selon les poids des options (« ai_weight », modulés par « ai_modifiers »).
static func ai_choice(state: SimState, definition: Dictionary, scope: Dictionary) -> int:
	var options: Array = definition.get("options", [])
	var weights: Array[float] = []
	var total := 0.0
	for option: Variant in options:
		var weight := float((option as Dictionary).get("ai_weight", state.event_settings.get("default_ai_weight", 1.0)))
		for modifier: Variant in (option as Dictionary).get("ai_modifiers", []):
			if ScriptConditions.evaluate(state, scope, (modifier as Dictionary).get("if", null)):
				weight *= float((modifier as Dictionary).get("factor", 1.0))
		weights.append(maxf(weight, 0.0))
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return 0
	var roll := state.rng.randf() * total
	for index: int in weights.size():
		roll -= weights[index]
		if roll < 0.0:
			return index
	return weights.size() - 1


static func choose(state: SimState, id: String, scope: Dictionary, option_index: int) -> void:
	var options: Array = (state.event_definitions.get(id, {}) as Dictionary).get("options", [])
	if option_index < 0 or option_index >= options.size():
		return
	ScriptEffects.apply(state, scope, (options[option_index] as Dictionary).get("effects", {}))
	state.add_event(EVENT_CHOSEN, str(scope.get("country", "")), {"event": id, "option": option_index})


## Premier événement en attente du joueur ({} s'il n'y en a pas).
static func next_pending(state: SimState) -> Dictionary:
	return state.pending_events[0] if not state.pending_events.is_empty() else {}


static func choice_refusal(state: SimState, tag: String, id: String, option_index: int) -> String:
	var pending := _pending_index(state, tag, id)
	if pending < 0:
		return "EVENT_NOT_PENDING"
	var options: Array = (state.event_definitions.get(id, {}) as Dictionary).get("options", [])
	if option_index < 0 or option_index >= options.size():
		return "EVENT_NOT_PENDING"
	return ""


static func answer(state: SimState, tag: String, id: String, option_index: int) -> void:
	var pending := _pending_index(state, tag, id)
	if pending < 0:
		return
	var entry: Dictionary = state.pending_events[pending]
	state.pending_events.remove_at(pending)
	choose(state, id, {"country": tag, "from": str(entry.get("from", ""))}, option_index)


static func _pending_index(state: SimState, tag: String, id: String) -> int:
	for index: int in state.pending_events.size():
		var entry: Dictionary = state.pending_events[index]
		if str(entry["id"]) == id and str(entry["country"]) == tag:
			return index
	return -1


# --- Modificateurs temporaires -----------------------------------------------------------------------------------

static func tick_modifiers(country: CountryState) -> void:
	if country.event_modifiers.is_empty():
		return
	var kept: Array[Dictionary] = []
	for modifier: Dictionary in country.event_modifiers:
		modifier["months"] = int(modifier.get("months", 0)) - 1
		if int(modifier["months"]) > 0:
			kept.append(modifier)
	country.event_modifiers = kept
	refresh_modifiers(country)


static func refresh_modifiers(country: CountryState) -> void:
	var growth := 0.0
	var unemployment := 0.0
	var stability := 0.0
	for modifier: Dictionary in country.event_modifiers:
		growth += float(modifier.get("growth", 0.0))
		unemployment += float(modifier.get("unemployment", 0.0))
		stability += float(modifier.get("stability", 0.0))
	country.economy.event_growth = growth
	country.economy.event_unemployment = unemployment
	country.event_stability = stability


# --- Validation --------------------------------------------------------------------------------------------------

## Erreurs de toutes les définitions (déclencheurs, facteurs, effets, choix, chaînes).
static func validate_definitions(definitions: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Array = definitions.keys()
	for id: Variant in ids:
		var definition: Dictionary = definitions[id]
		var where := "événement %s" % str(id)
		errors.append_array(ScriptConditions.validate(definition.get("trigger", null), where + " (déclencheur)"))
		for modifier: Variant in definition.get("mtth_modifiers", []):
			errors.append_array(ScriptConditions.validate((modifier as Dictionary).get("if", null), where + " (MTTH)"))
		errors.append_array(ScriptEffects.validate(definition.get("immediate", {}), where + " (immédiat)", ids))
		if not bool(definition.get("triggered_only", false)) and not definition.has("mtth_months"):
			errors.append("%s : ni « mtth_months » ni « triggered_only »" % where)
		var options: Array = definition.get("options", [])
		if options.size() > int(MAX_OPTIONS):
			errors.append("%s : au plus %d choix" % [where, MAX_OPTIONS])
		for index: int in options.size():
			var option: Dictionary = options[index]
			var place := "%s (choix %d)" % [where, index + 1]
			errors.append_array(ScriptEffects.validate(option.get("effects", {}), place, ids))
			for modifier: Variant in option.get("ai_modifiers", []):
				errors.append_array(ScriptConditions.validate((modifier as Dictionary).get("if", null), place))
	return errors

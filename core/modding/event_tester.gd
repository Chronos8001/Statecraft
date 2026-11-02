class_name EventTester
extends RefCounted
## Essai d'un événement dans une partie de test : le déclencheur est-il vrai pour ce pays, avec quelle chance
## par mois ; puis effets immédiats et choix appliqués, avec les valeurs du pays avant et après.

const PERCENT := 100.0
const WATCHED := ["stability", "legitimacy", "growth", "unemployment", "inflation", "debt"]


## Rapport : {fired, trigger, chance, before, after, events, error}.
static func run(state: SimState, id: String, definition: Dictionary, tag: String, option_index: int) -> Dictionary:
	var report := {"fired": false, "trigger": false, "chance": 0.0, "before": {}, "after": {}, "events": [], "error": ""}
	var world := str(definition.get("scope", "country")) == EventSystem.SCOPE_WORLD
	if state.get_country(tag) == null:
		report["error"] = "EDITOR_TEST_NO_COUNTRY"
		return report
	var scope := {"country": "" if world else tag, "from": ""}
	report["trigger"] = ScriptConditions.evaluate(state, scope, definition.get("trigger", null))
	if definition.has("mtth_months"):
		report["chance"] = EventSystem.monthly_chance(state, definition, scope) * PERCENT
	state.event_definitions = state.event_definitions.duplicate()
	state.event_definitions[id] = definition
	EventSystem.index_actions(state)
	report["before"] = snapshot(state, tag)
	state.events.clear()
	ScriptEffects.apply(state, scope, definition.get("immediate", {}))
	var options: Array = definition.get("options", [])
	if option_index >= 0 and option_index < options.size():
		EventSystem.choose(state, id, {"country": tag, "from": ""}, option_index)
	report["fired"] = true
	report["after"] = snapshot(state, tag)
	var types: Array = []
	for event: Dictionary in state.events:
		types.append(str(event.get("type", "")))
	report["events"] = types
	return report


static func snapshot(state: SimState, tag: String) -> Dictionary:
	var country := state.get_country(tag)
	if country == null:
		return {}
	var result: Dictionary = {}
	for key: String in WATCHED:
		var value: Variant = ScriptConditions.number_of(state, {"country": tag, "from": ""}, key)
		result[key] = float(value) if value != null else 0.0
	result["growth"] = country.economy.event_growth
	result["unemployment"] = country.economy.event_unemployment
	result["inflation"] = country.economy.event_inflation
	return result

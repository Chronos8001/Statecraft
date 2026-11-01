extends GutTest
## Événements scriptés : langage de conditions et d'effets, validation, MTTH, « once », chaînes, choix de
## l'IA, événements du joueur en attente, événements mondiaux, modificateurs temporaires.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(regime: String) -> Dictionary:
	return {"population": 10000000, "currency": "usd", "regime": regime, "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0}}


## AAA (joueur, démocratie), BBB (démocratie), CCC (régime autoritaire).
func _world(events: Dictionary = {}) -> SimState:
	var state := SimState.new()
	state.setup(5, GameDate.new(2026, 1, 1), &"AAA")
	var countries := {"AAA": _country("republic"), "BBB": _country("republic"), "CCC": _country("autocracy")}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"workers": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"republic": {"democratic": true, "group_influence": {}},
				"autocracy": {"democratic": false, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}})
	# Sans données politiques, le régime n'est pas rempli : on le fixe ici.
	for tag: String in countries.keys():
		var country := state.get_country(tag)
		country.politics.regime = str(countries[tag]["regime"])
		country.politics.democratic = country.politics.regime == "republic"
	state.event_definitions = events
	state.event_settings = _defines["events"]
	return state


func _scope(tag: String, from: String = "") -> Dictionary:
	return {"country": tag, "from": from}


func _fired(state: SimState, id: String) -> int:
	return state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == EventSystem.EVENT_FIRED and str(event["event"]) == id).size()


# --- Conditions --------------------------------------------------------------------------------------------------

func test_comparisons() -> void:
	assert_true(ScriptConditions.compare(20.0, "<30"))
	assert_false(ScriptConditions.compare(30.0, "<30"))
	assert_true(ScriptConditions.compare(30.0, "<=30"))
	assert_true(ScriptConditions.compare(2.5, ">=2.5"))
	assert_true(ScriptConditions.compare(-3.0, "> -5"))
	assert_true(ScriptConditions.compare(4.0, "!=5"))
	assert_true(ScriptConditions.compare(5.0, 5))
	assert_false(ScriptConditions.compare(5.0, "~5"), "opérateur inconnu")


func test_conditions() -> void:
	var state := _world()
	state.get_country("AAA").society.stability = 25.0
	var aaa := _scope("AAA")
	assert_true(ScriptConditions.evaluate(state, aaa, {"stability": "<30", "democratic": true}))
	assert_false(ScriptConditions.evaluate(state, aaa, {"stability": "<30", "democratic": false}), "toutes les clés")
	assert_true(ScriptConditions.evaluate(state, aaa, {"any": [{"democratic": false}, {"stability": "<30"}]}))
	assert_true(ScriptConditions.evaluate(state, aaa, {"any": {"democratic": false, "tag": "AAA"}}))
	assert_true(ScriptConditions.evaluate(state, aaa, {"not": {"tag": ["BBB", "CCC"]}}))
	assert_true(ScriptConditions.evaluate(state, aaa, {"is_player": true, "at_war": false, "year": ">=2026"}))
	assert_true(ScriptConditions.evaluate(state, _scope("CCC"), {"regime": "autocracy"}))
	state.diplomacy.change_relation("AAA", "CCC", -50.0)
	assert_true(ScriptConditions.evaluate(state, _scope("AAA", "CCC"), {"relation": {"with": "from", "value": "<-20"}}))
	state.get_country("AAA").laws["social_networks"] = "free"
	assert_true(ScriptConditions.evaluate(state, aaa, {"law": {"social_networks": "free"}}))
	assert_false(ScriptConditions.evaluate(state, _scope(""), {"stability": ">0"}), "portée mondiale : pas de pays")
	assert_true(ScriptConditions.evaluate(state, _scope(""), {"year": 2026, "world_tension": ">=0"}))


func test_validation() -> void:
	assert_eq(ScriptConditions.validate({"stability": "<30", "any": [{"tag": "USA"}]}, "x").size(), 0)
	assert_eq(ScriptConditions.validate({"stabilty": "<30"}, "x").size(), 1, "clé mal écrite")
	assert_eq(ScriptConditions.validate({"growth": "moins de 2"}, "x").size(), 1, "comparaison invalide")
	assert_eq(ScriptEffects.validate({"add_stability": 2, "trigger_event": "next"}, "x", ["next"]).size(), 0)
	assert_eq(ScriptEffects.validate({"add_stabilty": 2}, "x", []).size(), 1, "effet inconnu")
	assert_eq(ScriptEffects.validate({"trigger_event": "missing"}, "x", []).size(), 1, "chaîne inconnue")
	assert_eq(ScriptEffects.validate({"then": {}}, "x", []).size(), 1, "then sans if")
	assert_eq(ScriptEffects.validate({"add_modifier": {"growht": 1}}, "x", []).size(), 1)
	var errors := EventSystem.validate_definitions({"bad": {"options": []}})
	assert_eq(errors.size(), 1, "ni MTTH ni triggered_only")


func test_game_events_are_valid() -> void:
	var definitions := DataLoader.get_category("events")
	assert_gt(definitions.size(), 0)
	assert_eq(EventSystem.validate_definitions(definitions), PackedStringArray(), "événements du jeu valides")


# --- Effets ------------------------------------------------------------------------------------------------------

func test_effects() -> void:
	var state := _world()
	var aaa := state.get_country("AAA")
	aaa.society.stability = 98.0
	ScriptEffects.apply(state, _scope("AAA"), {"add_stability": 5, "set_flag": "reform", "set_world_flag": "crash"})
	assert_almost_eq(aaa.society.stability, 100.0, 0.001, "bornée")
	assert_true(ScriptConditions.evaluate(state, _scope("AAA"), {"has_flag": "reform", "has_world_flag": "crash"}))
	ScriptEffects.apply(state, _scope("AAA", "CCC"), {"add_relation": {"with": "from", "value": -10}})
	assert_almost_eq(state.diplomacy.relation("AAA", "CCC"), state.diplomacy.start_relation("AAA", "CCC") - 10.0, 0.001)
	ScriptEffects.apply(state, _scope("CCC"), {"if": {"democratic": true}, "then": {"set_flag": "yes"},
		"else": {"set_flag": "no"}})
	assert_true(ScriptConditions.evaluate(state, _scope("CCC"), {"has_flag": "no", "not": {"has_flag": "yes"}}))
	ScriptEffects.apply(state, _scope(""), {"every_country": {"limit": {"democratic": true}, "effects": {"set_flag": "dem"}}})
	assert_true(ScriptConditions.evaluate(state, _scope("BBB"), {"has_flag": "dem"}))
	assert_false(ScriptConditions.evaluate(state, _scope("CCC"), {"has_flag": "dem"}))
	var tension := state.diplomacy.world_tension
	ScriptEffects.apply(state, _scope(""), {"add_tension": 5, "clear_world_flag": "crash"})
	assert_gt(state.diplomacy.world_tension, tension)
	assert_false(state.world_flags.has("crash"))


func test_temporary_modifiers() -> void:
	var state := _world()
	var aaa := state.get_country("AAA")
	ScriptEffects.apply(state, _scope("AAA"), {"add_modifier": {"growth": -0.5, "stability": -3, "months": 2}})
	ScriptEffects.apply(state, _scope("AAA"), {"add_modifier": {"unemployment": 1.0}})
	assert_almost_eq(aaa.economy.event_growth, -0.5, 0.001)
	assert_almost_eq(aaa.event_stability, -3.0, 0.001)
	assert_almost_eq(aaa.economy.event_unemployment, 1.0, 0.001)
	EventSystem.tick_modifiers(aaa)
	assert_almost_eq(aaa.economy.event_growth, -0.5, 0.001, "encore un mois")
	EventSystem.tick_modifiers(aaa)
	assert_almost_eq(aaa.economy.event_growth, 0.0, 0.001, "expiré")
	assert_almost_eq(aaa.economy.event_unemployment, 1.0, 0.001, "durée par défaut plus longue")


# --- Tirage, chaînes, choix ---------------------------------------------------------------------------------------

func test_mtth_frequency() -> void:
	var event := {"title_key": "EVENT_T", "desc_key": "EVENT_D", "scope": "world", "mtth_months": 4.0, "options": [],
		"mtth_modifiers": [{"factor": 0.5, "if": {"has_world_flag": "faster"}}]}
	var state := _world({"tick": event})
	var expected := 1.0 - exp(-1.0 / 4.0)
	assert_almost_eq(EventSystem.monthly_chance(state, event, _scope("")), expected, 0.0001)
	state.world_flags["faster"] = true
	assert_almost_eq(EventSystem.monthly_chance(state, event, _scope("")), 1.0 - exp(-1.0 / 2.0), 0.0001, "facteur")
	state.world_flags.clear()
	var months := 3000
	for _month: int in months:
		EventSystem.draw(state)
	assert_almost_eq(float(_fired(state, "tick")) / months, expected, 0.03, "fréquence conforme au MTTH")


func test_trigger_and_once() -> void:
	var event := {"title_key": "EVENT_T", "desc_key": "EVENT_D", "scope": "country", "mtth_months": 0.01, "once": true,
		"trigger": {"democratic": true}, "options": []}
	var state := _world({"once": event})
	for _month: int in 5:
		EventSystem.draw(state)
	assert_eq(_fired(state, "once"), 2, "une fois par démocratie")
	assert_true(EventSystem.has_fired(state, "once", "AAA"))
	assert_false(EventSystem.has_fired(state, "once", "CCC"), "déclencheur faux")


func test_chain_with_delay() -> void:
	var start := {"title_key": "EVENT_T", "desc_key": "EVENT_D", "scope": "country", "triggered_only": true,
		"immediate": {"trigger_event": {"id": "next", "days": 3, "target": "self"}}, "options": []}
	var next := {"title_key": "EVENT_T", "desc_key": "EVENT_D", "scope": "country", "triggered_only": true,
		"immediate": {"set_flag": "chained"}, "options": []}
	var state := _world({"start": start, "next": next})
	EventSystem.draw(state)
	assert_eq(_fired(state, "start"), 0, "seulement par une chaîne")
	EventSystem.fire(state, "start", _scope("BBB", "CCC"))
	assert_eq(state.scheduled_events.size(), 1)
	var system := EventSystem.new()
	for _day: int in 2:
		state.date = GameDate.new(state.date.year, state.date.month, state.date.day + 1)
		system.on_day(state)
	assert_eq(_fired(state, "next"), 0, "pas avant le délai")
	state.date = GameDate.new(state.date.year, state.date.month, state.date.day + 1)
	system.on_day(state)
	assert_eq(_fired(state, "next"), 1)
	assert_true(ScriptConditions.evaluate(state, _scope("BBB"), {"has_flag": "chained"}))
	assert_true(state.scheduled_events.is_empty())


func test_ai_choice_follows_weights() -> void:
	var event := {"title_key": "EVENT_T", "desc_key": "EVENT_D", "scope": "country", "triggered_only": true,
		"options": [
			{"name_key": "EVENT_A", "effects": {"set_flag": "a"}, "ai_weight": 1,
				"ai_modifiers": [{"factor": 0, "if": {"democratic": false}}]},
			{"name_key": "EVENT_B", "effects": {"set_flag": "b"}, "ai_weight": 1,
				"ai_modifiers": [{"factor": 0, "if": {"democratic": true}}]}]}
	var state := _world({"pick": event})
	assert_eq(EventSystem.ai_choice(state, event, _scope("BBB")), 0)
	EventSystem.fire(state, "pick", _scope("CCC"))
	assert_true(ScriptConditions.evaluate(state, _scope("CCC"), {"has_flag": "b"}), "facteur nul : jamais choisi")
	var counts := [0, 0]
	(event["options"][0] as Dictionary).erase("ai_modifiers")
	(event["options"][1] as Dictionary).erase("ai_modifiers")
	event["options"][1]["ai_weight"] = 3
	for _draw: int in 2000:
		counts[EventSystem.ai_choice(state, event, _scope("BBB"))] += 1
	assert_almost_eq(float(counts[1]) / 2000.0, 0.75, 0.04, "tirage selon les poids")


func test_player_answers_pending_event() -> void:
	var event := {"title_key": "EVENT_T", "desc_key": "EVENT_D", "scope": "country", "triggered_only": true,
		"immediate": {"set_flag": "seen"},
		"options": [{"name_key": "EVENT_A", "effects": {"set_flag": "a"}}, {"name_key": "EVENT_B", "effects": {"set_flag": "b"}}]}
	var state := _world({"ask": event})
	EventSystem.fire(state, "ask", _scope("AAA"))
	assert_eq(state.pending_events.size(), 1, "le joueur choisit lui-même")
	event["mtth_months"] = 0.01
	event.erase("triggered_only")
	EventSystem.draw(state)
	assert_eq(state.pending_events.size(), 1, "pas de doublon tant que le joueur n'a pas répondu")
	assert_true(ScriptConditions.evaluate(state, _scope("AAA"), {"has_flag": "seen", "not": {"has_flag": "b"}}))
	assert_eq(ChooseEventOptionCommand.new(&"AAA", "other", 0).refusal_reason(state), "EVENT_NOT_PENDING")
	assert_eq(ChooseEventOptionCommand.new(&"AAA", "ask", 5).refusal_reason(state), "EVENT_NOT_PENDING")
	var command := ChooseEventOptionCommand.new(&"AAA", "ask", 1)
	assert_true(command.can_execute(state))
	command.execute(state)
	assert_true(state.pending_events.is_empty())
	assert_true(ScriptConditions.evaluate(state, _scope("AAA"), {"has_flag": "b"}))


func test_world_event() -> void:
	var event := {"title_key": "EVENT_T", "desc_key": "EVENT_D", "scope": "world", "mtth_months": 0.01, "once": true,
		"immediate": {"every_country": {"limit": {"democratic": false}, "effects": {"add_modifier": {"growth": -1.0}}}},
		"options": [{"name_key": "EVENT_A", "effects": {"set_flag": "answered"}}]}
	var state := _world({"crash": event})
	EventSystem.draw(state)
	EventSystem.draw(state)
	assert_eq(_fired(state, "crash"), 1, "une seule fois pour le monde")
	assert_almost_eq(state.get_country("CCC").economy.event_growth, -1.0, 0.001)
	assert_almost_eq(state.get_country("BBB").economy.event_growth, 0.0, 0.001)
	assert_eq(state.pending_events.size(), 1, "le joueur répond pour son pays")
	assert_eq(str(state.pending_events[0]["country"]), "AAA")

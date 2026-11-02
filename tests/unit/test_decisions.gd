extends GutTest
## Décisions ponctuelles et arbres de décisions : conditions, coût, durée, délai, annulation, prérequis,
## exclusivité, un nœud à la fois, choix de l'IA, nouveaux effets (influence, corruption, technologie,
## modificateurs permanents, voisins), validation des données du jeu.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const DECISIONS := {
	"rally": {"name_key": "DECISION_X", "desc_key": "DECISION_X", "category": "politics",
		"cost": {"stability": 5}, "days": 10, "cooldown_days": 30,
		"on_start": {"set_flag": "rally_started"}, "effects": {"add_legitimacy": 4}},
	"instant": {"name_key": "DECISION_X", "desc_key": "DECISION_X", "category": "economy",
		"visible": {"democratic": true}, "available": {"stability": "<90"}, "effects": {"set_flag": "instant_done"}},
	"summit": {"name_key": "DECISION_X", "desc_key": "DECISION_X", "category": "diplomacy",
		"cost": {"influence": 50}, "effects": {}},
}
const TREE := {"test": {"name_key": "FOCUS_X", "nodes": {
	"root": {"name_key": "FOCUS_X", "desc_key": "FOCUS_X", "x": 0, "y": 0, "months": 2,
		"effects": {"add_modifier": {"growth": 0.5, "months": -1}}},
	"left": {"name_key": "FOCUS_X", "desc_key": "FOCUS_X", "x": 0, "y": 1, "months": 1, "requires": ["root"],
		"exclusive": ["right"], "effects": {"set_flag": "left"}},
	"right": {"name_key": "FOCUS_X", "desc_key": "FOCUS_X", "x": 2, "y": 1, "months": 1, "requires": ["root"],
		"exclusive": ["left"], "ai_weight": 0},
	"merge": {"name_key": "FOCUS_X", "desc_key": "FOCUS_X", "x": 1, "y": 2, "months": 1, "requires_any": ["left", "right"],
		"available": {"stability": ">10"}},
}}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country() -> Dictionary:
	return {"population": 10000000, "currency": "usd", "regime": "republic", "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"AAA")
	WorldSetup.populate(state, {"AAA": _country(), "BBB": _country()}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {},
		{}, {"groups": {"workers": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}})
	for tag: String in ["AAA", "BBB"]:
		state.get_country(tag).politics.democratic = true
	state.land_neighbors = {"AAA": {"BBB": true}, "BBB": {"AAA": true}}
	state.decision_definitions = DECISIONS.duplicate(true)
	state.focus_trees = TREE.duplicate(true)
	state.decision_settings = _defines["decisions"]
	state.event_settings = _defines["events"]
	state.focus_trees["test"]["countries"] = ["AAA", "BBB"]
	DecisionSystem.assign_trees(state)
	return state


func _advance_days(state: SimState, system: DecisionSystem, days: int) -> void:
	for _day: int in days:
		for _hour: int in GameDate.HOURS_PER_DAY:
			state.date.advance_hour()
		system.on_day(state)


# --- Décisions ---------------------------------------------------------------------------------------------------

func test_decision_cost_duration_and_cooldown() -> void:
	var state := _world()
	var system := DecisionSystem.new()
	var country := state.get_country("AAA")
	assert_true(DecisionCommand.new(&"AAA", "rally").can_execute(state))
	DecisionCommand.new(&"AAA", "rally").execute(state)
	assert_almost_eq(country.society.stability, 45.0, 0.001, "coût payé au lancement")
	assert_true(ScriptConditions.evaluate(state, {"country": "AAA", "from": ""}, {"has_flag": "rally_started",
		"has_decision": "rally"}))
	assert_eq(DecisionSystem.decision_refusal(state, country, "rally"), "DECISION_ACTIVE")
	var legitimacy := country.society.legitimacy
	_advance_days(state, system, 9)
	assert_almost_eq(country.society.legitimacy, legitimacy, 0.001, "pas encore fini")
	_advance_days(state, system, 1)
	assert_almost_eq(country.society.legitimacy, legitimacy + 4.0, 0.001, "effets à la fin")
	assert_eq(DecisionSystem.decision_refusal(state, country, "rally"), "DECISION_COOLDOWN")
	_advance_days(state, system, 30)
	assert_eq(DecisionSystem.decision_refusal(state, country, "rally"), "")


func test_decision_conditions_and_once() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	country.society.stability = 95.0
	assert_eq(DecisionSystem.decision_refusal(state, country, "instant"), "DECISION_UNAVAILABLE")
	country.society.stability = 50.0
	assert_true(DecisionSystem.start_decision(state, country, "instant"))
	assert_true(ScriptConditions.evaluate(state, {"country": "AAA", "from": ""}, {"has_flag": "instant_done"}),
		"sans durée : effets aussitôt")
	assert_eq(DecisionSystem.decision_refusal(state, country, "instant"), "DECISION_COOLDOWN", "sans délai : une seule fois")
	country.politics.democratic = false
	assert_eq(DecisionSystem.decision_refusal(state, country, "instant"), "DECISION_UNKNOWN", "invisible")


func test_decision_influence_cost_and_cancel() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	state.diplomacy.influence_points["AAA"] = 20.0
	assert_eq(DecisionSystem.decision_refusal(state, country, "summit"), "DECISION_TOO_EXPENSIVE")
	state.diplomacy.influence_points["AAA"] = 60.0
	assert_true(DecisionSystem.start_decision(state, country, "summit"))
	assert_almost_eq(float(state.diplomacy.influence_points["AAA"]), 10.0, 0.001)
	DecisionSystem.start_decision(state, country, "rally")
	var cancel := DecisionCommand.new(&"AAA", "rally", true)
	assert_true(cancel.can_execute(state))
	cancel.execute(state)
	assert_false(country.decisions_active.has("rally"))
	assert_almost_eq(country.society.stability, 45.0, 0.001, "coût non rendu")
	assert_false(DecisionCommand.new(&"AAA", "rally", true).can_execute(state))


# --- Arbre -------------------------------------------------------------------------------------------------------

func test_focus_prerequisites_exclusivity_and_one_at_a_time() -> void:
	var state := _world()
	var system := DecisionSystem.new()
	var country := state.get_country("AAA")
	assert_eq(country.focus_tree, "test")
	assert_eq(DecisionSystem.focus_refusal(state, country, "left"), "FOCUS_MISSING_PREREQUISITE")
	assert_true(FocusCommand.new(&"AAA", "root").can_execute(state))
	FocusCommand.new(&"AAA", "root").execute(state)
	assert_eq(DecisionSystem.focus_refusal(state, country, "root"), "FOCUS_BUSY")
	_advance_days(state, system, 30)
	assert_almost_eq(DecisionSystem.focus_progress(state, country), 0.5, 0.05)
	_advance_days(state, system, 31)
	assert_true(country.focus_done.has("root"))
	assert_almost_eq(country.economy.event_growth, 0.5, 0.001, "modificateur permanent")
	EventSystem.tick_modifiers(country)
	assert_almost_eq(country.economy.event_growth, 0.5, 0.001, "il ne s'use pas")
	assert_true(DecisionSystem.start_focus(state, country, "left"))
	assert_eq(DecisionSystem.focus_refusal(state, country, "right"), "FOCUS_EXCLUDED")
	_advance_days(state, system, 31)
	assert_eq(DecisionSystem.focus_refusal(state, country, "right"), "FOCUS_EXCLUDED", "fermé pour de bon")
	assert_eq(DecisionSystem.focus_refusal(state, country, "merge"), "", "un seul prérequis suffit")
	country.society.stability = 5.0
	assert_eq(DecisionSystem.focus_refusal(state, country, "merge"), "FOCUS_UNAVAILABLE")


func test_focus_cancel_loses_progress() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	DecisionSystem.start_focus(state, country, "root")
	assert_true(FocusCommand.new(&"AAA", "").can_execute(state))
	FocusCommand.new(&"AAA", "").execute(state)
	assert_eq(country.focus_current, "")
	assert_false(country.focus_done.has("root"))
	assert_false(FocusCommand.new(&"AAA", "").can_execute(state))


func test_ai_follows_tree_and_weights() -> void:
	var state := _world()
	var system := DecisionSystem.new()
	var ai := state.get_country("BBB")
	system.on_month(state)
	assert_eq(ai.focus_current, "root", "l'IA commence l'arbre")
	assert_eq(state.get_country("AAA").focus_current, "", "jamais pour le joueur")
	_advance_days(state, system, 61)
	system.on_month(state)
	assert_eq(ai.focus_current, "left", "« right » a un poids nul")


# --- Effets ------------------------------------------------------------------------------------------------------

func test_new_effects() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	var scope := {"country": "AAA", "from": ""}
	var influence := float(state.diplomacy.influence_points.get("AAA", 0.0))
	ScriptEffects.apply(state, scope, {"add_influence": 12, "add_corruption": -10})
	assert_almost_eq(float(state.diplomacy.influence_points["AAA"]), influence + 12.0, 0.001)
	assert_almost_eq(country.society.corruption, 20.0, 0.001)
	assert_almost_eq(country.society.start_corruption, 20.0, 0.001)
	var before := state.diplomacy.relation("BBB", "AAA")
	ScriptEffects.apply(state, scope, {"every_neighbor": {"add_relation": {"with": "from", "value": 8}}})
	assert_almost_eq(state.diplomacy.relation("BBB", "AAA"), before + 8.0, 0.01)
	assert_eq(ScriptEffects.validate({"every_neighbor": {"bogus": 1}}, "x", []).size(), 1)


# --- Données du jeu ----------------------------------------------------------------------------------------------

func test_game_data_is_valid() -> void:
	var decisions := DataLoader.get_category("decisions")
	var trees := DecisionSystem.resolve_trees(DataLoader.get_category("focus_trees"))
	assert_gt(decisions.size(), 15)
	assert_true(trees.has("generic"))
	assert_gt(((trees["generic"] as Dictionary)["nodes"] as Dictionary).size(), 30)
	var errors := DecisionSystem.validate_definitions(decisions, trees, DataLoader.get_category("events").keys())
	assert_eq(errors.size(), 0, "\n".join(errors))
	for id: Variant in decisions.keys():
		for key: Variant in ((decisions[id] as Dictionary).get("cost", {}) as Dictionary).keys():
			assert_true(DecisionSystem.COST_KEYS.has(str(key)))
	var techs := DataLoader.get_category("technologies")
	for node: Variant in ((trees["generic"] as Dictionary)["nodes"] as Dictionary).values():
		var tech := str(((node as Dictionary).get("effects", {}) as Dictionary).get("add_tech", ""))
		if not tech.is_empty():
			assert_true(techs.has(tech), tech)

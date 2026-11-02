extends GutTest
## Événements mondiaux et nationaux : déclencheurs sur action, nouvelles, portée province, nouvelles conditions
## (from, any_neighbor, gdp_rank, détroits) et nouveaux effets (inflation, dette en % du PIB, chocs d'offre,
## détroits, gisements).

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const OPTION := {"name_key": "EVENT_X_A", "effects": {"add_stability": 1}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(gdp: float) -> Dictionary:
	return {"population": 10000000, "currency": "usd", "regime": "republic", "capital": 1,
		"economy": {"gdp_billion_usd": gdp, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0}}


## AAA (joueur, PIB moyen), BBB (voisin de AAA, le plus riche), CCC (le plus petit, voisin de BBB).
func _world(events: Dictionary = {}) -> SimState:
	var state := SimState.new()
	state.setup(7, GameDate.new(2026, 1, 1), &"AAA")
	WorldSetup.populate(state, {"AAA": _country(500.0), "BBB": _country(2000.0), "CCC": _country(50.0)}, CURRENCIES,
		_defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"workers": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}})
	for tag: String in ["AAA", "BBB", "CCC"]:
		state.get_country(tag).politics.democratic = true
	state.land_neighbors = {"AAA": {"BBB": true}, "BBB": {"AAA": true, "CCC": true}, "CCC": {"BBB": true}}
	state.event_definitions = events
	state.event_settings = _defines["events"]
	EventSystem.index_actions(state)
	return state


func _scope(tag: String, from: String = "") -> Dictionary:
	return {"country": tag, "from": from}


func _fired(state: SimState, id: String) -> Array[Dictionary]:
	return state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == EventSystem.EVENT_FIRED and str(event["event"]) == id)


func _event(extra: Dictionary) -> Dictionary:
	var definition := {"title_key": "EVENT_X_TITLE", "desc_key": "EVENT_X_DESC", "scope": "country", "options": [OPTION]}
	definition.merge(extra, true)
	return definition


# --- Conditions --------------------------------------------------------------------------------------------------

func test_new_conditions() -> void:
	var state := _world()
	assert_true(ScriptConditions.evaluate(state, _scope("BBB"), {"gdp_rank": 1}))
	assert_true(ScriptConditions.evaluate(state, _scope("CCC"), {"gdp_rank": ">=3"}))
	assert_true(ScriptConditions.evaluate(state, _scope("AAA"), {"population": ">9"}))
	assert_true(ScriptConditions.evaluate(state, _scope("BBB"), {"borders_player": true}))
	assert_false(ScriptConditions.evaluate(state, _scope("CCC"), {"borders_player": true}))
	assert_true(ScriptConditions.evaluate(state, _scope("AAA"), {"is_player_or_neighbor": true}))
	assert_true(ScriptConditions.evaluate(state, _scope("AAA", "BBB"), {"from": {"gdp_rank": 1}}))
	assert_false(ScriptConditions.evaluate(state, _scope("AAA"), {"from": {"gdp_rank": 1}}), "pas de pays d'origine")
	state.get_country("CCC").society.stability = 10.0
	assert_true(ScriptConditions.evaluate(state, _scope("BBB"), {"any_neighbor": {"stability": "<20"}}))
	assert_false(ScriptConditions.evaluate(state, _scope("AAA"), {"any_neighbor": {"stability": "<20"}}))
	state.closed_straits["hormuz"] = true
	assert_true(ScriptConditions.evaluate(state, _scope(""), {"strait_closed": "hormuz"}))
	var scope := {"country": "AAA", "from": "", "action": {"government_changed": true, "kind": "legislative"}}
	assert_true(ScriptConditions.evaluate(state, scope, {"action": {"government_changed": true}}))
	assert_false(ScriptConditions.evaluate(state, scope, {"action": {"kind": "presidential"}}))
	assert_eq(ScriptConditions.validate({"from": {"bogus": 1}, "any_neighbor": {"at_war": true}}, "x").size(), 1)


# --- Déclencheurs sur action -------------------------------------------------------------------------------------

func test_on_action_for_actor() -> void:
	var state := _world({"shift": _event({"on_action": "election_held",
		"trigger": {"action": {"government_changed": true}}})})
	state.add_event(ElectionSystem.EVENT_ELECTION, "BBB", {"government_changed": false})
	state.add_event(ElectionSystem.EVENT_ELECTION, "CCC", {"government_changed": true})
	assert_eq(state.action_queue.size(), 2, "les actions suivies sont mises en file")
	EventSystem.process_actions(state)
	var fired := _fired(state, "shift")
	assert_eq(fired.size(), 1)
	assert_eq(str(fired[0]["tag"]), "CCC")
	assert_true(state.action_queue.is_empty())
	state.add_event(&"minister_scandal", "AAA")
	assert_true(state.action_queue.is_empty(), "les actions sans événement ne sont pas suivies")


func test_on_action_for_others_with_from() -> void:
	var state := _world({"reaction": _event({"on_action": "election_held", "action_scope": "others",
		"trigger": {"is_player": true, "from": {"gdp_rank": 1}},
		"options": [{"name_key": "EVENT_X_A", "effects": {"add_relation": {"with": "from", "value": 10}}}]})})
	state.add_event(ElectionSystem.EVENT_ELECTION, "CCC", {"government_changed": true})
	EventSystem.process_actions(state)
	assert_eq(_fired(state, "reaction").size(), 0, "CCC n'est pas le plus riche")
	state.add_event(ElectionSystem.EVENT_ELECTION, "BBB", {"government_changed": true})
	EventSystem.process_actions(state)
	var fired := _fired(state, "reaction")
	assert_eq(fired.size(), 1, "seul le joueur réagit")
	assert_eq(str(fired[0]["from"]), "BBB")
	var pending := EventSystem.next_pending(state)
	assert_eq(str(pending["from"]), "BBB")
	var before := state.diplomacy.relation("AAA", "BBB")
	EventSystem.answer(state, "AAA", "reaction", 0)
	assert_almost_eq(state.diplomacy.relation("AAA", "BBB"), before + 10.0, 0.01)


func test_on_action_events_are_not_drawn_monthly() -> void:
	var state := _world({"shift": _event({"on_action": "coup", "mtth_months": 0.1})})
	for _month: int in 12:
		EventSystem.draw(state)
	assert_eq(_fired(state, "shift").size(), 0)


# --- Nouvelles ---------------------------------------------------------------------------------------------------

func test_news_flag() -> void:
	var state := _world({"quake": _event({"triggered_only": true, "news": {"gdp_rank": "<=2"}}),
		"info": {"title_key": "EVENT_X_TITLE", "desc_key": "EVENT_X_DESC", "scope": "world", "triggered_only": true,
			"news": true}})
	EventSystem.fire(state, "quake", _scope("BBB"))
	EventSystem.fire(state, "quake", _scope("CCC"))
	EventSystem.fire(state, "quake", _scope("AAA"))
	EventSystem.fire(state, "info", _scope(""))
	var fired := _fired(state, "quake")
	assert_true(bool(fired[0]["news"]), "pays de l'IA assez grand")
	assert_false(bool(fired[1]["news"]), "trop petit")
	assert_false(bool(fired[2]["news"]), "le joueur a une fenêtre")
	assert_true(bool(_fired(state, "info")[0]["news"]), "événement mondial sans choix : simple nouvelle")
	assert_eq(state.pending_events.size(), 1, "seul l'événement du joueur attend une réponse")


# --- Effets ------------------------------------------------------------------------------------------------------

func test_random_province() -> void:
	var state := _world()
	state.energy_definitions = {"provinces": {"1": {"coastal": true, "terrain": "plains", "population": 1000},
		"2": {"coastal": false, "terrain": "mountains", "population": 900000},
		"3": {"coastal": true, "terrain": "urban", "population": 500000}}}
	state.provinces_by_owner = {"AAA": ["1", "2"], "BBB": ["3"]}
	var scope := _scope("AAA")
	ScriptEffects.apply(state, scope, {"random_province": {"limit": {"coastal": false},
		"effects": {"damage_infrastructure": 3}}})
	assert_eq(str(scope["province"]), "2")
	assert_almost_eq(float(state.infrastructure_damage["2"]), 3.0, 0.001)
	ScriptEffects.apply(state, scope, {"random_province": {"limit": {"terrain": ["urban"]}, "effects": {}}})
	assert_eq(str(scope["province"]), "2", "aucune province urbaine à AAA : rien ne change")
	assert_eq(ScriptEffects.validate({"random_province": {"limit": {"altitude": 3}, "effects": {}}}, "x", []).size(), 1)


func test_random_country() -> void:
	var state := _world()
	ScriptEffects.apply(state, _scope(""), {"random_country": {"limit": {"gdp_rank": 1},
		"effects": {"set_flag": "chosen"}}})
	assert_true(ScriptConditions.evaluate(state, _scope("BBB"), {"has_flag": "chosen"}))
	assert_false(ScriptConditions.evaluate(state, _scope("AAA"), {"has_flag": "chosen"}))


func test_economic_effects() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	ScriptEffects.apply(state, _scope("AAA"), {"add_modifier": {"inflation": 1.5, "months": 2}})
	assert_almost_eq(country.economy.event_inflation, 1.5, 0.001)
	EventSystem.tick_modifiers(country)
	EventSystem.tick_modifiers(country)
	assert_almost_eq(country.economy.event_inflation, 0.0, 0.001, "le modificateur expire")
	var currency := state.get_currency(country.economy.currency)
	var debt := country.economy.debt_ratio(currency)
	ScriptEffects.apply(state, _scope("AAA"), {"add_debt_gdp": 10})
	assert_almost_eq(country.economy.debt_ratio(currency), debt + 0.1, 0.01, "10 points de PIB")


func test_supply_shock_and_capacity() -> void:
	var state := _world()
	var market := MarketState.new()
	market.resource_id = "oil"
	market.supply = 1000.0
	state.markets["oil"] = market
	ScriptEffects.apply(state, _scope(""), {"add_supply_shock": {"resource": "oil", "share": 0.1, "months": 2}})
	assert_almost_eq(market.shock, 0.1, 0.001)
	ResourceSystem._tick_shock(market)
	assert_almost_eq(market.shock, 0.1, 0.001)
	ResourceSystem._tick_shock(market)
	assert_almost_eq(market.shock, 0.0, 0.001, "le choc s'arrête")
	ScriptEffects.apply(state, _scope("CCC"), {"add_resource_capacity": {"resource": "oil", "world_share": 0.01}})
	assert_almost_eq(float(state.get_country("CCC").resources.production_base["oil"]), 10.0, 0.001)
	assert_true(state.get_country("CCC").resources.consumption_base.has("oil"), "nouveau producteur")
	ResourceSystem._grow_bases(state.get_country("CCC"), state)
	assert_true(ScriptConditions.evaluate(state, _scope("CCC"), {"has_resource": "oil"}))


func test_strait_effects() -> void:
	var state := _world()
	state.resource_definitions = {"straits": {"hormuz": {}}}
	ScriptEffects.apply(state, _scope(""), {"close_strait": "hormuz"})
	assert_true(state.closed_straits.has("hormuz"))
	assert_eq(state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == ResourceSystem.EVENT_STRAIT_CLOSED).size(), 1)
	ScriptEffects.apply(state, _scope(""), {"close_strait": "hormuz"})
	assert_eq(state.events.size(), 1, "déjà fermé : rien de plus")
	ScriptEffects.apply(state, _scope(""), {"open_strait": "hormuz"})
	assert_false(state.closed_straits.has("hormuz"))
	ScriptEffects.apply(state, _scope(""), {"close_strait": "unknown"})
	assert_false(state.closed_straits.has("unknown"))


func test_chain_from_world_to_every_country() -> void:
	var state := _world({
		"world_start": {"title_key": "EVENT_X_TITLE", "desc_key": "EVENT_X_DESC", "scope": "world",
			"triggered_only": true, "immediate": {"every_country": {"effects": {"trigger_event": "national"}}}},
		"national": _event({"triggered_only": true})})
	EventSystem.fire(state, "world_start", _scope(""))
	assert_eq(_fired(state, "national").size(), 3, "un événement national par pays")
	assert_eq(state.pending_events.size(), 1, "le joueur choisit le sien")


func test_game_events_use_known_actions() -> void:
	var events := DataLoader.get_category("events")
	assert_gt(events.size(), 40)
	for id: Variant in events.keys():
		var action := str((events[id] as Dictionary).get("on_action", ""))
		if not action.is_empty():
			assert_true(EventSystem.ACTION_TYPES.has(action), "%s : %s" % [id, action])

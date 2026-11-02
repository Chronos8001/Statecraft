extends GutTest
## Pays dynamiques : absorption pacifique (territoire, population, PIB, dette, commerce, références), dissolution,
## changement de nom ; puis le vrai monde avec plusieurs unions, qui doit continuer à tourner sans erreur.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const MONTHS := 3

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(gdp: float) -> Dictionary:
	return {"population": 10000000, "currency": "usd", "regime": "republic", "capital": 1,
		"economy": {"gdp_billion_usd": gdp, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0}}


## AAA (joueur), BBB et CCC ; provinces 1-2 à BBB, 3 à CCC, 4 à AAA ; 2 touche 3 et 3 touche 4.
func _world() -> SimState:
	var state := SimState.new()
	state.setup(4, GameDate.new(2026, 1, 1), &"AAA")
	WorldSetup.populate(state, {"AAA": _country(500.0), "BBB": _country(800.0), "CCC": _country(100.0)}, CURRENCIES,
		_defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"workers": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}})
	state.energy_definitions = {"provinces": {"1": {"population": 6000000}, "2": {"population": 4000000},
		"3": {"population": 10000000}, "4": {"population": 10000000}}}
	state.province_owner = {"1": "BBB", "2": "BBB", "3": "CCC", "4": "AAA"}
	state.province_control = state.province_owner.duplicate()
	state.provinces_by_owner = {"BBB": ["1", "2"], "CCC": ["3"], "AAA": ["4"]}
	state.province_neighbors = {"1": ["2"], "2": ["1", "3"], "3": ["2", "4"], "4": ["3"]}
	CountryLifecycle.recompute_land_neighbors(state)
	state.trade.start_flows = {"BBB": {"CCC": 10.0, "AAA": 5.0}, "CCC": {"BBB": 4.0, "AAA": 2.0},
		"AAA": {"CCC": 3.0, "BBB": 6.0}}
	state.trade.start_gdp = {"AAA": 500.0, "BBB": 800.0, "CCC": 100.0}
	return state


func test_annexation_moves_everything() -> void:
	var state := _world()
	var bbb := state.get_country("BBB")
	var ccc := state.get_country("CCC")
	var population := bbb.economy.population + ccc.economy.population
	var gdp := bbb.economy.real_gdp + ccc.economy.real_gdp
	var currency := state.get_currency("usd")
	var debt := bbb.economy.total_debt(currency) + ccc.economy.total_debt(currency)
	state.diplomacy.change_relation("AAA", "CCC", 20.0)
	state.diplomacy.treaties[1] = {"type": "trade", "a": "AAA", "b": "CCC"}
	state.puppets["CCC"] = "AAA"
	var tension := state.diplomacy.world_tension
	assert_true(CountryLifecycle.annex(state, "BBB", "CCC"))
	assert_null(state.get_country("CCC"))
	assert_eq(str(state.dissolved["CCC"]), "BBB")
	assert_eq(ControlSystem.owner(state, "3"), "BBB")
	assert_eq(ControlSystem.controller(state, "3"), "BBB")
	assert_eq(bbb.economy.population, population, "toute la population")
	assert_almost_eq(bbb.economy.real_gdp, gdp, 0.01, "tout le PIB")
	assert_almost_eq(bbb.economy.total_debt(currency), debt, 0.01, "toute la dette")
	assert_true((state.land_neighbors["BBB"] as Dictionary).has("AAA"), "nouvelle frontière commune")
	assert_false(state.land_neighbors.has("CCC"))
	assert_almost_eq(float(state.trade.start_flows["BBB"]["AAA"]), 7.0, 0.001, "exportations reprises")
	assert_almost_eq(float(state.trade.start_flows["AAA"]["BBB"]), 9.0, 0.001, "importations reprises")
	assert_false((state.trade.start_flows["BBB"] as Dictionary).has("CCC"), "commerce devenu intérieur")
	assert_false(state.trade.start_flows.has("CCC"))
	assert_almost_eq(float(state.trade.start_gdp["BBB"]), 900.0, 0.001)
	assert_true(state.diplomacy.treaties.is_empty())
	assert_true(state.puppets.is_empty())
	assert_false(state.diplomacy.relation_changes.keys().any(func(key: Variant) -> bool: return str(key).contains("CCC")))
	assert_eq(state.diplomacy.claims.size(), 0, "union pacifique : pas de revendication")
	assert_almost_eq(state.diplomacy.world_tension, tension, 0.001, "ni tension")
	var annexed := state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == CountryLifecycle.EVENT_ANNEXED)
	assert_eq(annexed.size(), 1)


func test_player_cannot_be_absorbed() -> void:
	var state := _world()
	assert_eq(CountryLifecycle.annex_refusal(state, "BBB", "AAA"), "ANNEX_PLAYER")
	assert_false(CountryLifecycle.annex(state, "BBB", "AAA"))
	assert_not_null(state.get_country("AAA"))
	assert_true(CountryLifecycle.annex(state, "AAA", "BBB"), "le joueur peut absorber")


func test_script_effects_and_conditions() -> void:
	var state := _world()
	var scope := {"country": "BBB", "from": "CCC"}
	assert_true(ScriptConditions.evaluate(state, scope, {"country_exists": "from", "owns_province": "1"}))
	ScriptEffects.apply(state, scope, {"annex_country": "from",
		"rename_country": {"name_key": "COUNTRY_UNION", "color": "#123456"}})
	assert_true(ScriptConditions.evaluate(state, scope, {"is_dissolved": "CCC", "owns_province": "3",
		"not": {"country_exists": "CCC"}}))
	assert_eq(str(state.country_overrides["BBB"]["name_key"]), "COUNTRY_UNION")
	assert_eq(str(state.country_overrides["BBB"]["color"]), "#123456")
	ScriptEffects.apply(state, {"country": "AAA", "from": ""}, {"join_country": "BBB"})
	assert_not_null(state.get_country("AAA"), "le joueur ne disparaît pas")
	assert_eq(ScriptEffects.validate({"rename_country": "x"}, "x", []).size(), 1)


func test_purge_helpers() -> void:
	var table := {"AAA|CCC": 1, "CCC>BBB": 2, "truce|AAA|CCC": 3, "AAA|BBB": 4, "CCC": 5}
	CountryLifecycle.purge_keys(table, "CCC")
	assert_eq(table.keys(), ["AAA|BBB"])
	var nested := {"AAA": {"CCC": 1, "BBB": 2}, "CCC": {"AAA": 3}}
	CountryLifecycle.purge_nested(nested, "CCC")
	assert_eq(nested, {"AAA": {"BBB": 2}})


## Le vrai monde : unions (dont un pays en guerre) puis quelques mois de simulation complète.
func test_real_world_keeps_running_after_unions() -> void:
	GameState.new_game(21, &"FRA")
	var state := GameState.sim
	var unions := [["FRA", "BEL"], ["DEU", "AUT"], ["KOR", "PRK"], ["POL", "UKR"], ["RUS", "BLR"]]
	for pair: Array in unions:
		assert_true(CountryLifecycle.annex(state, pair[0], pair[1]), "%s absorbe %s" % pair)
		assert_null(state.get_country(pair[1]))
		assert_true((state.provinces_by_owner.get(pair[1], []) as Array).is_empty())
	assert_true(WarSystem.wars_of(state, "UKR").is_empty())
	for _hour: int in MONTHS * 31 * GameDate.HOURS_PER_DAY:
		GameState.advance_hour()
	assert_null(state.get_country("UKR"))
	for province_id: Variant in state.province_owner.keys():
		assert_not_null(state.get_country(str(state.province_owner[province_id])), "propriétaire vivant")
	for war: War in state.wars.values():
		for tag: String in war.attackers + war.defenders:
			assert_true(state.get_country(tag) != null or WarSystem.is_rebel(state, tag), "belligérant vivant")


## Naissance de pays dans le vrai monde : part de la population et du PIB, partis, dirigeants, frontières,
## commerce ; puis la simulation continue, et un pays né peut être absorbé à son tour.
func test_real_world_secessions() -> void:
	GameState.new_game(22, &"FRA")
	var state := GameState.sim
	var gbr := state.get_country("GBR")
	var population := gbr.economy.population
	var gdp := TradeSystem.current_gdp(state, "GBR")
	assert_eq(CountryFactory.parent_of(state, "scotland"), "GBR")
	assert_eq(CountryFactory.release(state, "scotland"), "SCO")
	var sco := state.get_country("SCO")
	assert_not_null(sco)
	assert_eq(CountryFactory.release_refusal(state, "scotland"), "RELEASE_INVALID", "déjà indépendante")
	assert_eq(ControlSystem.owner(state, "1233"), "SCO")
	assert_eq(sco.economy.population + gbr.economy.population, population, "population partagée")
	assert_between(float(sco.economy.population) / population, 0.05, 0.12)
	assert_almost_eq(TradeSystem.current_gdp(state, "SCO") + TradeSystem.current_gdp(state, "GBR"), gdp, gdp * 0.01)
	assert_false(sco.politics.parties.is_empty())
	for party_id: Variant in sco.politics.parties.keys():
		assert_true(str(party_id).begins_with("pty_sco_"))
	assert_false(sco.politics.head_of_state.is_empty())
	assert_eq(str(GovernmentSystem.character(state, sco.politics.head_of_state).get("party", "")),
		sco.politics.ruling_party())
	assert_false(sco.cabinet.is_empty(), "un gouvernement")
	assert_true((state.land_neighbors["SCO"] as Dictionary).has("GBR"))
	assert_true(state.trade.start_flows.has("SCO"))
	assert_gt(float((state.trade.start_flows["GBR"] as Dictionary).get("SCO", 0.0)), 0.0)
	assert_eq(sco.economy.currency, gbr.economy.currency)
	assert_eq(sco.focus_tree, "generic")
	assert_eq(CountryFactory.release(state, "catalonia"), "CAT")
	assert_eq(CountryFactory.release(state, "tibet"), "TIB")
	assert_eq(state.get_country("TIB").politics.regime, "theocracy")
	for _hour: int in MONTHS * 31 * GameDate.HOURS_PER_DAY:
		GameState.advance_hour()
	assert_not_null(state.get_country("CAT"))
	assert_true(CountryLifecycle.annex(state, "GBR", "SCO"), "un pays né peut être réabsorbé")
	assert_eq(ControlSystem.owner(state, "1233"), "GBR")
	for province_id: Variant in state.province_owner.keys():
		assert_not_null(state.get_country(str(state.province_owner[province_id])), "propriétaire vivant")

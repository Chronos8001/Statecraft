extends GutTest
## Nucléaire : alerte, programmes (découverte, aboutissement, abandon), frappe (dévastation, effondrement
## diplomatique), riposte sous parapluie, doctrine de l'IA.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 2000000},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 500},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 400},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 3000000},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4], "center": [184.0, 90.0], "population": 4000000},
	"7": {"owner": "CCC", "controller": "CCC", "neighbors": [], "center": [100.0, 40.0], "population": 600},
	"8": {"owner": "DDD", "controller": "DDD", "neighbors": [], "center": [120.0, 40.0], "population": 600},
}
const BUILDINGS := {"coal_plant": {"source": "coal", "capacity_gw": 1.0}}
const WARHEADS := {"AAA": 50, "BBB": 0, "CCC": 20, "DDD": 0}

var _defines: Dictionary
var _goals: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_goals = JSON.parse_string(FileAccess.get_file_as_string(WAR_GOALS_PATH))


func _country(warheads: int) -> Dictionary:
	var branches := {"land": {"share": 0.7, "level": 3.0, "training": 54.0, "morale": 60.0},
		"air": {"share": 0.3, "level": 3.0, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic", "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": 400000, "reserve_personnel": 100000},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": 30},
			"nuclear_warheads": warheads}}


func _world(start: Dictionary = {}) -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"DDD")
	var countries: Dictionary = {}
	for tag: String in WARHEADS.keys():
		countries[tag] = _country(int(WARHEADS[tag]))
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": start, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"], "war_goals": _goals})
	state.military_settings = state.military_settings.duplicate(true)
	state.energy_definitions["provinces"] = PROVINCES
	state.energy_definitions["buildings"] = BUILDINGS
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	ArmyGroupModel.setup_start(state, countries)
	NuclearSystem.setup_start(state)
	EnergySystem.add_building(state, "4", "coal_plant", 1)
	state.get_country("BBB").energy.capacity["coal"] = 1.0
	return state


func _at_war(state: SimState) -> War:
	var provinces: Array[String] = ["4"]
	TensionSystem.add_claim(state, "AAA", "BBB", provinces)
	return WarSystem.declare(state, "AAA", "BBB", "annex")


func test_alert() -> void:
	var state := _world()
	assert_eq(NuclearAlertCommand.new(&"BBB", 1).refusal_reason(state), "NUCLEAR_NO_WARHEADS")
	var tension := state.diplomacy.world_tension
	var command := NuclearAlertCommand.new(&"AAA", 3)
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	assert_eq(state.get_country("AAA").military.nuclear_alert, 3)
	assert_gt(state.diplomacy.world_tension, tension, "relever l'alerte inquiète le monde")
	assert_eq(NuclearAlertCommand.new(&"AAA", 0).refusal_reason(state), "MILITARY_COOLDOWN")


func test_strike_refusals() -> void:
	var state := _world()
	assert_eq(NuclearStrikeCommand.new(&"AAA", "4").refusal_reason(state), "NUCLEAR_ALERT_TOO_LOW")
	state.get_country("AAA").military.nuclear_alert = 3
	assert_eq(NuclearStrikeCommand.new(&"AAA", "4").refusal_reason(state), "ACTION_NOT_ENEMY")
	_at_war(state)
	assert_eq(NuclearStrikeCommand.new(&"AAA", "4").refusal_reason(state), "")
	assert_eq(NuclearStrikeCommand.new(&"BBB", "3").refusal_reason(state), "NUCLEAR_NO_WARHEADS")


func test_strike_devastates_and_isolates() -> void:
	var state := _world()
	_at_war(state)
	state.get_country("AAA").military.nuclear_alert = 3
	var victim := state.get_country("BBB")
	var population := victim.economy.population
	var gdp := victim.economy.real_gdp
	var relation := state.diplomacy.relation("AAA", "DDD")
	NuclearStrikeCommand.new(&"AAA", "4").execute(state)
	assert_lt(victim.economy.population, population, "victimes")
	assert_lt(victim.economy.real_gdp, gdp)
	assert_eq(EnergySystem.building_count(state, "4", "coal_plant"), 0, "bâtiments détruits")
	assert_true(state.devastated.has("4"))
	assert_gt(float(state.infrastructure_damage.get("4", 0.0)), 0.0)
	assert_lt(state.diplomacy.relation("AAA", "DDD"), relation, "effondrement diplomatique")
	assert_almost_eq(state.diplomacy.world_tension, TensionSystem.LIMIT, 0.001)
	assert_eq(NuclearSystem.warheads(state, "AAA"), 50 - int(_defines["military"]["nuclear"]["strike_warheads"]))


func test_umbrella_retaliation() -> void:
	var state := _world()
	DiplomacySystem.add_treaty(state, "mutual_defense", "BBB", "CCC", true)
	(state.military_settings["nuclear"] as Dictionary)["umbrella_chance"] = 1.0
	var war := _at_war(state)
	state.get_country("AAA").military.nuclear_alert = 3
	var population := state.get_country("AAA").economy.population
	NuclearSystem.strike(state, "AAA", "4")
	assert_true(war.defenders.has("CCC"), "la puissance protectrice entre en guerre")
	assert_lt(state.get_country("AAA").economy.population, population, "riposte sur l'attaquant")
	assert_true(state.devastated.has("1"), "province la plus peuplée de l'attaquant")
	var strikes := state.events.filter(func(event: Dictionary) -> bool: return event["type"] == NuclearSystem.EVENT_STRIKE)
	assert_eq(strikes.size(), 2, "une frappe, une riposte, pas d'escalade sans fin")


func test_programs() -> void:
	var state := _world({"nuclear_programs": {"BBB": {"months_left": 2, "detected": false}}})
	assert_true(state.nuclear_programs.has("BBB"), "programme de départ")
	assert_eq(NuclearProgramCommand.new(&"AAA").refusal_reason(state), "NUCLEAR_ALREADY_ARMED")
	assert_eq(NuclearProgramCommand.new(&"DDD", false).refusal_reason(state), "NUCLEAR_NO_PROGRAM")
	(state.military_settings["nuclear"]["program"] as Dictionary)["detection_chance"] = 1.0
	var relation := state.diplomacy.relation("BBB", "AAA")
	NuclearSystem.update_month(state)
	assert_true(bool(state.nuclear_programs["BBB"]["detected"]))
	assert_lt(state.diplomacy.relation("BBB", "AAA"), relation, "les puissances nucléaires s'en inquiètent")
	NuclearSystem.update_month(state)
	assert_false(state.nuclear_programs.has("BBB"))
	assert_eq(NuclearSystem.warheads(state, "BBB"), int(_defines["military"]["nuclear"]["program"]["completed_warheads"]))
	NuclearProgramCommand.new(&"DDD").execute(state)
	assert_true(state.nuclear_programs.has("DDD"))
	NuclearProgramCommand.new(&"DDD", false).execute(state)
	assert_false(state.nuclear_programs.has("DDD"))


func test_ai_doctrine() -> void:
	var state := _world()
	var war := _at_war(state)
	var ai: MilitaryAI = state.military.ai
	ai.nuclear_doctrine(state.get_country("AAA"), state)
	assert_eq(state.get_country("AAA").military.nuclear_alert, 0, "BBB n'a pas d'arme : pas d'alerte")
	assert_false(ai.existential(state, war, "AAA"))
	ControlSystem.set_controller(state, "1", "BBB")
	assert_true(ai.existential(state, war, "AAA"), "province la plus peuplée prise")
	(state.military_settings["nuclear"]["ai"] as Dictionary)["use_chance"] = 1.0
	FrontSystem.refresh(state)
	ai.nuclear_doctrine(state.get_country("AAA"), state)
	assert_eq(state.get_country("AAA").military.nuclear_alert, 3, "alerte maximale")
	assert_eq(state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == NuclearSystem.EVENT_STRIKE).size(), 1, "frappe sur le front")

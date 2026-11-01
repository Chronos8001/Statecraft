extends GutTest
## Occupation (résistance : pertes, infrastructures), gouvernements fantoches (installation, tribut, pas de guerre
## avec le suzerain, indépendance) et conversion des données militaires pour un modèle détaillé.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 4000000},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 3000000},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 3000000},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 2000000},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4], "center": [184.0, 90.0], "population": 8000000},
}

var _defines: Dictionary
var _goals: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_goals = JSON.parse_string(FileAccess.get_file_as_string(WAR_GOALS_PATH))


func _country(personnel: int) -> Dictionary:
	var branches := {"land": {"share": 0.6, "level": 3.0, "training": 54.0, "morale": 60.0},
		"air": {"share": 0.2, "level": 3.0, "training": 54.0, "morale": 60.0},
		"sea": {"share": 0.2, "level": 3.0, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic", "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": personnel, "reserve_personnel": personnel / 4},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": 30},
			"nuclear_warheads": 0}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"CCC")
	var countries := {"AAA": _country(2000000), "BBB": _country(200000), "CCC": _country(200000)}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"], "war_goals": _goals})
	state.energy_definitions["provinces"] = PROVINCES
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	ArmyGroupModel.setup_start(state, countries)
	for tag: String in countries.keys():
		state.military.model.update_country(state.get_country(tag), state)
	return state


func _war(state: SimState, goal: String) -> War:
	var provinces: Array[String] = ["4"]
	TensionSystem.add_claim(state, "AAA", "BBB", provinces)
	state.diplomacy.world_tension = 80.0
	state.diplomacy.change_relation("AAA", "BBB", -90.0)
	return WarSystem.declare(state, "AAA", "BBB", goal)


func test_resistance_bleeds_the_occupier() -> void:
	var state := _world()
	var war := _war(state, "annex")
	ControlSystem.set_controller(state, "4", "AAA")
	var losses := state.get_country("AAA").military.losses
	OccupationSystem.update_month(state)
	assert_gt(float(state.resistance.get("4", 0.0)), 0.0, "résistance dans la province occupée")
	assert_gt(state.get_country("AAA").military.losses, losses, "l'occupant perd des soldats")
	assert_gt(float(state.infrastructure_damage.get("4", 0.0)), 0.0, "ravitaillement gêné")
	assert_gt(float(war.casualties.get("AAA", 0.0)), 0.0)
	WarSystem.end_war(state, war)
	OccupationSystem.update_month(state)
	assert_true(state.resistance.is_empty(), "plus d'occupation, plus de résistance")


func test_puppet_government() -> void:
	var state := _world()
	var war := _war(state, "regime_change")
	ControlSystem.set_controller(state, "4", "AAA")
	state.get_country("AAA").politics.ideology = "liberal"
	var demands := WarEnd.available_demands(state, war, "AAA")
	assert_true(demands.has({"type": OccupationSystem.PUPPET}), "but de changement de régime")
	WarEnd.sign_peace(state, war, "AAA", [{"type": OccupationSystem.PUPPET}])
	assert_eq(OccupationSystem.overlord_of(state, "BBB"), "AAA")
	assert_eq(state.get_country("BBB").politics.ideology, "liberal", "gouvernement aligné")
	assert_true(ControlSystem.allied(state, "BBB", "AAA"), "défense mutuelle imposée")
	assert_true(state.diplomacy.has_treaty("AAA", "BBB", "military_access"), "base du suzerain")
	var debt := state.get_country("BBB").economy.local_debt
	OccupationSystem.update_month(state)
	assert_gt(state.get_country("BBB").economy.local_debt, debt, "tribut versé")
	state.diplomacy.cooldowns.clear()
	assert_eq(WarSystem.declare_refusal(state, "BBB", "AAA", "reparations"), "WAR_ALLIED", "pas de guerre contre le suzerain")
	DeclareIndependenceCommand.new(&"BBB").execute(state)
	assert_false(OccupationSystem.is_puppet(state, "BBB"), "indépendance proclamée")
	assert_false(ControlSystem.allied(state, "BBB", "AAA"))
	assert_eq(DeclareIndependenceCommand.new(&"BBB").refusal_reason(state), "PUPPET_NOT_PUPPET")


func test_export_for_detailed_model() -> void:
	var state := _world()
	NavalModel.setup_start(state)
	var data := state.military.model.export_country(state, "AAA")
	assert_eq(int(data["version"]), int(_defines["military"]["export"]["version"]))
	assert_true((data["branches"] as Dictionary).has("land"))
	assert_gt(int((data["estimated_units"] as Dictionary)["divisions"]), 0)
	assert_eq((data["army_groups"] as Array).size(), ArmyGroupModel.groups_of(state, "AAA").size())
	var land := float((data["branches"]["land"] as Dictionary)["personnel"])
	assert_eq(int(data["estimated_units"]["divisions"]), roundi(land / float(_defines["military"]["export"]["personnel_per_division"])))
	var world := state.military.model.export_world(state)
	assert_eq((world["countries"] as Dictionary).size(), 3)

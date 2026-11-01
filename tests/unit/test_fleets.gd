extends GutTest
## Flottes : placement au départ, trajets par la mer (détroits fermés), contrôle des mers et combat naval,
## réparation, repli des flottes endommagées.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
## AAA 1-2-3 | BBB 4-5. Mers : 100 (côtes 1, 2), 101 (côtes 3, 4), 102 (côte 5), 104 au-delà d'un détroit, 103 un lac.
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 900},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 500},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 400},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 300},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4], "center": [184.0, 90.0], "population": 800},
}
const SEA_ZONES := {
	"100": {"kind": "sea", "center": [180.5, 92.0], "neighbors": [101], "coasts": [1, 2]},
	"101": {"kind": "sea", "center": [182.5, 92.0], "neighbors": [100, 102], "coasts": [3, 4]},
	"102": {"kind": "sea", "center": [184.0, 92.0], "neighbors": [101], "coasts": [5]},
	"104": {"kind": "sea", "center": [190.0, 92.0], "neighbors": [], "coasts": []},
	"103": {"kind": "lake", "center": [181.0, 88.0], "neighbors": [], "coasts": [1]},
}
const STRAITS := {"narrows": {"sea_zones": [102, 104]}}

var _defines: Dictionary
var _goals: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_goals = JSON.parse_string(FileAccess.get_file_as_string(WAR_GOALS_PATH))


func _country() -> Dictionary:
	var branches := {"land": {"share": 0.6, "level": 3.0, "training": 54.0, "morale": 60.0},
		"air": {"share": 0.2, "level": 3.0, "training": 54.0, "morale": 60.0},
		"sea": {"share": 0.2, "level": 3.0, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic", "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": 400000, "reserve_personnel": 100000},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": 30},
			"nuclear_warheads": 0}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"AAA")
	var countries := {"AAA": _country(), "BBB": _country()}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"], "war_goals": _goals, "sea_zones": SEA_ZONES, "straits": STRAITS})
	state.energy_definitions["provinces"] = PROVINCES
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	NavalModel.setup_start(state)
	return state


func _war(state: SimState) -> War:
	var provinces: Array[String] = ["4"]
	TensionSystem.add_claim(state, "AAA", "BBB", provinces)
	return WarSystem.declare(state, "AAA", "BBB", "annex")


func test_sea_network() -> void:
	var state := _world()
	assert_true(NavalModel.is_sea(state, "101"))
	assert_false(NavalModel.is_sea(state, "103"), "les lacs sont exclus")
	assert_true((state.sea_links["102"] as Array).has("104"), "liaison par le détroit")
	assert_eq(NavalModel.coastal_zones(state, "AAA").keys(), ["100", "101"])


func test_fleets_placed_in_home_seas() -> void:
	var state := _world()
	var fleets := NavalModel.fleets_of(state, "AAA")
	assert_eq(fleets.size(), 2, "80 000 marins : 2 flottes")
	assert_eq(fleets[0].zone, "100", "mer la plus peuplée d'abord")
	assert_eq(fleets[1].zone, "101")
	assert_almost_eq(fleets[0].share + fleets[1].share, 1.0, 0.0001)
	assert_eq(NavalModel.fleets_of(state, "BBB")[0].zone, "102")


func test_fleet_moves_by_sea() -> void:
	var state := _world()
	var fleet := NavalModel.fleets_of(state, "AAA")[0]
	assert_eq(MoveFleetCommand.new(&"AAA", fleet.id, "103").refusal_reason(state), "FLEET_NOT_SEA")
	assert_eq(MoveFleetCommand.new(&"BBB", fleet.id, "102").refusal_reason(state), "FLEET_INVALID")
	assert_eq(MoveFleetCommand.new(&"AAA", fleet.id, "100").refusal_reason(state), "FLEET_ALREADY_THERE")
	var command := MoveFleetCommand.new(&"AAA", fleet.id, "104")
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	assert_eq(fleet.path, ["101", "102", "104"])
	for _day: int in 30:
		NavalModel.update_day(state)
	assert_eq(fleet.zone, "104")
	state.closed_straits["narrows"] = true
	assert_eq(MoveFleetCommand.new(&"AAA", fleet.id, "100").refusal_reason(state), "FLEET_UNREACHABLE",
		"détroit fermé")


func test_sea_control_and_naval_combat() -> void:
	var state := _world()
	var resolver := NavalResolver.new()
	resolver.resolve_day(state)
	assert_true(state.sea_control.is_empty(), "en paix, personne ne se dispute les mers")
	var war := _war(state)
	var ours := NavalModel.fleets_of(state, "AAA")[1]
	var theirs := NavalModel.fleets_of(state, "BBB")[1]
	assert_eq(theirs.zone, "101")
	resolver.resolve_day(state)
	assert_true(bool((state.sea_control["101"] as Dictionary).get("contested", false)), "forces égales : mer disputée")
	assert_lt(ours.condition, 1.0, "combat naval")
	assert_lt(theirs.condition, 1.0)
	theirs.zone = "102"
	ours.condition = 1.0
	resolver.resolve_day(state)
	assert_eq(NavalResolver.controller(state, "101"), "AAA", "flotte de AAA contre la seule défense côtière de BBB")
	assert_lt(ours.condition, 1.0, "la défense côtière abîme quand même la flotte")
	assert_true(NavalResolver.hostile_to(state, "101", "BBB"))
	assert_false(NavalResolver.hostile_to(state, "101", "AAA"))
	assert_false(state.sea_control.has("100"), "mer sans ennemi : hors de la guerre")
	assert_not_null(war)


func test_damage_repair_and_retreat() -> void:
	var state := _world()
	_war(state)
	var fleet := NavalModel.fleets_of(state, "AAA")[1]
	fleet.condition = 0.32
	var theirs := NavalModel.fleets_of(state, "BBB")[1]
	theirs.condition = 1.0
	var resolver := NavalResolver.new()
	for _day: int in 3:
		resolver.resolve_day(state)
	assert_true(fleet.damage_reported)
	assert_eq(state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == NavalResolver.EVENT_DAMAGED and event["tag"] == "AAA").size(), 1, "signalée une fois")
	MilitaryAI.new().retreat_damaged_fleets("AAA", state)
	assert_eq(fleet.destination, "100", "repli vers une mer sûre")
	fleet.zone = "100"
	fleet.path.clear()
	var before := fleet.condition
	NavalModel.repair_month(state)
	assert_almost_eq(fleet.condition, before + float(_defines["military"]["navy"]["repair_per_month"]), 0.0001)

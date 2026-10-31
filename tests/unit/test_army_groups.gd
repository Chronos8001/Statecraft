extends GutTest
## Contrôle des provinces (front disputé, changement progressif de contrôleur) et groupes d'armées (placement
## selon les menaces, déplacements par voie de terre).

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
## Une ligne de provinces d'ouest en est (1 degré ≈ 111 km) : AAA 1-2-3 | BBB 4-5, plus une île de AAA (6).
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 900},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 500},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 400},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 300},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4], "center": [184.0, 90.0], "population": 800},
	"6": {"owner": "AAA", "controller": "AAA", "neighbors": [], "center": [150.0, 60.0], "population": 100},
}
const FRONT := {"list": [[4, "AAA", 0.4]]}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country() -> Dictionary:
	var branches := {"land": {"share": 0.7, "level": 3.0, "training": 54.0, "morale": 60.0},
		"air": {"share": 0.3, "level": 3.0, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic", "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": 400000, "reserve_personnel": 100000},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": 30},
			"nuclear_warheads": 0}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(), &"AAA")
	var countries := {"AAA": _country(), "BBB": _country()}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {"front": FRONT}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"]})
	state.energy_definitions["provinces"] = PROVINCES
	ControlSystem.setup_start(state)
	ArmyGroupModel.setup_start(state, countries)
	return state


func _days(state: SimState, count: int) -> void:
	var system := MilitarySystem.new()
	for _index: int in count:
		system.on_day(state)


func test_start_control_and_front() -> void:
	var state := _world()
	assert_eq(ControlSystem.controller(state, "4"), "BBB")
	assert_almost_eq(ControlSystem.share_held(state, "4", "AAA"), 0.4, 0.0001)
	assert_almost_eq(ControlSystem.share_held(state, "4", "BBB"), 0.6, 0.0001)
	assert_almost_eq(ControlSystem.occupied_share(state, "4"), 0.4, 0.0001, "province en partie occupée")
	assert_eq(ControlSystem.neighbors(state, "3"), ["2", "4"], "voisins en texte")


func test_control_changes_progressively() -> void:
	var state := _world()
	ControlSystem.advance(state, "4", "AAA", 0.3)
	assert_eq(ControlSystem.controller(state, "4"), "BBB", "pas encore entière")
	ControlSystem.advance(state, "4", "AAA", 0.3)
	assert_eq(ControlSystem.controller(state, "4"), "AAA", "à 100 %, le contrôleur change")
	assert_false(state.contested.has("4"))
	var changes: Array = state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == ControlSystem.EVENT_CONTROL)
	assert_eq(changes.size(), 1)
	ControlSystem.advance(state, "4", "BBB", 0.5)
	assert_almost_eq(ControlSystem.share_held(state, "4", "BBB"), 0.5, 0.0001, "contre-attaque")
	ControlSystem.advance(state, "4", "AAA", 0.6)
	assert_false(state.contested.has("4"), "contre-attaque repoussée")


func test_groups_are_placed_on_the_front() -> void:
	var state := _world()
	var groups := ArmyGroupModel.groups_of(state, "AAA")
	assert_eq(groups.size(), 2, "280 000 soldats terrestres : 2 groupes")
	assert_eq(groups[0].province, "3", "le premier groupe garde le front")
	assert_eq(groups[1].province, "1", "le second reste à la capitale")
	assert_gt(groups[0].share, groups[1].share, "le front reçoit plus de forces")
	assert_almost_eq(groups[0].share + groups[1].share, 1.0, 0.0001)
	assert_eq(ArmyGroupModel.groups_of(state, "BBB")[0].province, "4", "BBB défend la province disputée")
	assert_false(ArmyGroupModel.groups_of(state, "AAA").any(func(group: ArmyGroup) -> bool: return group.province == "6"))


func test_move_overland() -> void:
	var state := _world()
	var group := ArmyGroupModel.groups_of(state, "AAA")[1]
	assert_eq(MoveArmyGroupCommand.new(&"AAA", group.id, "5").refusal_reason(state), "ARMY_NOT_CONTROLLED")
	assert_eq(MoveArmyGroupCommand.new(&"AAA", group.id, "6").refusal_reason(state), "ARMY_UNREACHABLE")
	assert_eq(MoveArmyGroupCommand.new(&"BBB", group.id, "2").refusal_reason(state), "ARMY_INVALID")
	assert_eq(MoveArmyGroupCommand.new(&"AAA", group.id, "1").refusal_reason(state), "ARMY_ALREADY_THERE")
	var command := MoveArmyGroupCommand.new(&"AAA", group.id, "3")
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	assert_eq(group.path, ["2", "3"])
	assert_eq(group.days_left, 3, "111 km à 40 km par jour")
	_days(state, 3)
	assert_eq(group.province, "2", "étape franchie")
	_days(state, 3)
	assert_eq(group.province, "3")
	assert_false(group.is_moving())
	var arrivals: Array = state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == ArmyGroupModel.EVENT_ARRIVED)
	assert_eq(arrivals.size(), 1)


func test_lost_province_stops_the_march() -> void:
	var state := _world()
	var group := ArmyGroupModel.groups_of(state, "AAA")[1]
	MoveArmyGroupCommand.new(&"AAA", group.id, "3").execute(state)
	ControlSystem.set_controller(state, "2", "BBB")
	_days(state, 1)
	assert_false(group.is_moving(), "chemin coupé")
	assert_eq(group.province, "1")


func test_groups_follow_mobilization() -> void:
	var state := _world()
	var group := ArmyGroupModel.groups_of(state, "AAA")[0]
	var military := state.get_country("AAA").military
	var before := group.personnel(military, ArmyGroupModel.reserve_share(state))
	MobilizeCommand.new(&"AAA", 2).execute(state)
	assert_gt(group.personnel(military, ArmyGroupModel.reserve_share(state)), before, "les réservistes renforcent les groupes")

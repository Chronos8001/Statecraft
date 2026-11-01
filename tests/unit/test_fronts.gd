extends GutTest
## Fronts et combats : détection des fronts, forces engagées (groupes et garnison), posture, terrain, aviation,
## avance et prise des provinces, pertes, répartition automatique, IA de base, issue des guerres civiles.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const TERRAINS_PATH := "res://data/terrains/terrains.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
## AAA 1-2-3 | BBB 4-5 (4 en montagne), CCC 7 isolé.
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 900,
		"terrain": "plains", "infrastructure": 8},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 500,
		"terrain": "plains", "infrastructure": 8},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 400,
		"terrain": "plains", "infrastructure": 8},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 300,
		"terrain": "mountains", "infrastructure": 4},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4], "center": [184.0, 90.0], "population": 800,
		"terrain": "plains", "infrastructure": 6},
	"7": {"owner": "CCC", "controller": "CCC", "neighbors": [], "center": [100.0, 40.0], "population": 600,
		"terrain": "plains", "infrastructure": 5},
}
const TAGS := ["AAA", "BBB", "CCC"]

var _defines: Dictionary
var _goals: Dictionary
var _terrains: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_goals = JSON.parse_string(FileAccess.get_file_as_string(WAR_GOALS_PATH))
	_terrains = JSON.parse_string(FileAccess.get_file_as_string(TERRAINS_PATH))


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


func _world(start: Dictionary = {}) -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"CCC")
	var countries: Dictionary = {}
	for tag: String in TAGS:
		countries[tag] = _country()
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": start, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"], "war_goals": _goals, "terrains": _terrains})
	state.energy_definitions["provinces"] = PROVINCES
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	WarSystem.setup_forces(state)
	ArmyGroupModel.setup_start(state, countries)
	return state


## AAA déclare la guerre à BBB (revendication sur 4).
func _at_war(state: SimState) -> War:
	var provinces: Array[String] = ["4"]
	TensionSystem.add_claim(state, "AAA", "BBB", provinces)
	DeclareWarCommand.new(&"AAA", "BBB", "annex").execute(state)
	FrontSystem.refresh(state)
	return WarSystem.war_between(state, "AAA", "BBB")


func _front(state: SimState) -> Front:
	return FrontSystem.fronts_of(state, "AAA")[0]


func _days(state: SimState, count: int) -> void:
	var system := MilitarySystem.new()
	for _index: int in count:
		system.on_day(state)


## Groupes de AAA sur le front (déplacement immédiat).
func _deploy(state: SimState, tag: String) -> void:
	AutoDeployCommand.new(StringName(tag)).execute(state)
	for group: ArmyGroup in ArmyGroupModel.groups_of(state, tag):
		if group.is_moving():
			group.province = group.destination
			group.path.clear()
			group.days_left = 0


func test_fronts_follow_the_contact_line() -> void:
	var state := _world()
	FrontSystem.refresh(state)
	assert_true(state.fronts.is_empty(), "pas de guerre, pas de front")
	var war := _at_war(state)
	assert_eq(state.fronts.size(), 1)
	var front := _front(state)
	assert_eq(front.war_id, war.id)
	assert_eq([front.a, front.b], ["AAA", "BBB"])
	assert_eq(front.provinces_of("AAA"), ["3"])
	assert_eq(front.provinces_of("BBB"), ["4"])
	assert_eq(front.posture_of("AAA"), "defensive", "posture par défaut")
	front.postures["AAA"] = "offensive"
	ControlSystem.advance(state, "4", "AAA", 0.3)
	assert_true(state.fronts_dirty)
	FrontSystem.refresh(state)
	front = _front(state)
	assert_eq(front.contested, ["4"])
	assert_eq(front.provinces_of("AAA"), ["3", "4"], "la province disputée compte des deux côtés")
	assert_eq(front.posture_of("AAA"), "offensive", "posture gardée au recalcul")


func test_engaged_forces() -> void:
	var state := _world()
	_at_war(state)
	var land := FrontSystem.land_personnel(state, "AAA")
	var garrison := land * float(_defines["military"]["combat"]["garrison_share"])
	var key := _front(state).key
	var before := float(FrontSystem.engaged_personnel(state, "AAA")[key])
	assert_eq(FrontSystem.groups_on(state, _front(state), "AAA").size(), 1, "un groupe déjà au front, l'autre à la capitale")
	assert_gt(before, garrison)
	assert_almost_eq(float(FrontSystem.engaged_personnel(state, "BBB")[key]),
		FrontSystem.land_personnel(state, "BBB") * float(_defines["military"]["combat"]["garrison_share"]), 1.0,
		"BBB n'a que sa garnison sur le front")
	_deploy(state, "AAA")
	assert_eq(FrontSystem.groups_on(state, _front(state), "AAA").size(), 2, "tous les groupes sur l'unique front")
	assert_almost_eq(float(FrontSystem.engaged_personnel(state, "AAA")[key]), land + garrison, 1.0)


func test_offensive_takes_ground_and_provinces() -> void:
	var state := _world()
	var war := _at_war(state)
	_deploy(state, "AAA")
	var front := _front(state)
	front.postures["AAA"] = "offensive"
	_days(state, 10)
	var held := ControlSystem.share_held(state, "4", "AAA")
	assert_gt(held, 0.0, "AAA progresse")
	assert_lt(held, 0.1, "lentement")
	assert_gt(float(_front(state).progress["AAA"]), 0.0)
	state.contested["4"] = {"by": "AAA", "share": 0.9999}
	_days(state, 1)
	assert_eq(ControlSystem.controller(state, "4"), "AAA", "province prise")
	var group := ArmyGroupModel.groups_of(state, "BBB")[0]
	group.province = "4"
	ArmyGroupModel.evacuate(state, "4")
	assert_eq(group.province, "5", "le groupe de BBB recule")
	var taken: Array = state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == WarResolver.EVENT_PROVINCE_TAKEN)
	assert_eq(taken.size(), 1)
	assert_true(war.casualties.has("AAA") and war.casualties.has("BBB"))


func test_postures_and_terrain() -> void:
	var state := _world()
	_at_war(state)
	_deploy(state, "AAA")
	var front := _front(state)
	front.postures["AAA"] = "hold"
	_days(state, 5)
	assert_almost_eq(ControlSystem.share_held(state, "4", "AAA"), 0.0, 0.000001, "« tenir » n'attaque pas")
	assert_gt(WarResolver.terrain_defense(state, "4"), WarResolver.terrain_defense(state, "3"), "la montagne défend mieux")
	assert_eq(WarResolver.target_province(state, _front(state), "AAA"), "4")
	assert_eq(WarResolver.target_province(state, _front(state), "BBB"), "3")


func test_air_and_supply() -> void:
	var state := _world()
	var war := _at_war(state)
	var airs := {War.ATTACKERS: 3.0, War.DEFENDERS: 1.0}
	assert_almost_eq(WarResolver.air_factor(state, war, "AAA", airs), 1.125, 0.0001)
	assert_almost_eq(WarResolver.air_factor(state, war, "BBB", airs), 0.875, 0.0001)
	var front := _front(state)
	var near := WarResolver.supply(state, front, "AAA", "1")
	assert_almost_eq(near, 0.94, 0.0001, "infrastructures 8, front proche")
	assert_lt(WarResolver.supply(state, front, "BBB", "5"), near, "infrastructures 4")


func test_losses_wear_the_army() -> void:
	var state := _world()
	var war := _at_war(state)
	_deploy(state, "AAA")
	_front(state).postures["AAA"] = "offensive"
	var military := state.get_country("AAA").military
	var level := float((military.branches["land"] as Dictionary)["level"])
	var before := FrontSystem.land_personnel(state, "AAA")
	_days(state, 1)
	assert_gt(military.losses, 0.0)
	assert_lt(FrontSystem.land_personnel(state, "AAA"), before)
	assert_lt(float((military.branches["land"] as Dictionary)["level"]), level, "équipement usé")
	assert_gt(float(war.casualties["BBB"]), 0.0)
	var losses := military.losses
	state.military.model.update_country(state.get_country("AAA"), state)
	assert_lt(military.losses, losses, "pertes remplacées chaque mois")


func test_ai_postures_and_deployment() -> void:
	var state := _world()
	_at_war(state)
	var ai := MilitaryAI.new()
	ai.decide_week("AAA", state)
	ai.choose_postures("BBB", state)
	var front := _front(state)
	assert_true(ArmyGroupModel.groups_of(state, "AAA").all(func(group: ArmyGroup) -> bool:
		return group.province == "3" or group.destination == "3"), "groupes envoyés au front")
	_deploy(state, "AAA")
	ai.choose_postures("AAA", state)
	ai.choose_postures("BBB", state)
	assert_eq(front.posture_of("AAA"), "offensive", "bien plus fort")
	assert_eq(front.posture_of("BBB"), "hold", "bien plus faible")
	assert_eq(SetFrontPostureCommand.new(&"AAA", front.key, "offensive").refusal_reason(state), "MILITARY_ALREADY")
	assert_eq(SetFrontPostureCommand.new(&"CCC", front.key, "hold").refusal_reason(state), "WAR_INVALID")
	assert_eq(AutoDeployCommand.new(&"CCC").refusal_reason(state), "MILITARY_NO_FRONT")


func test_civil_war_outcomes() -> void:
	var start := {"rebels": {"list": [["BBB", "BBB_REB", [[4, 1.0]], "2025-01-01", 0.5]]}}
	var state := _world(start)
	var faction: RebelFaction = state.rebels["BBB_REB"]
	assert_almost_eq(faction.personnel, FrontSystem.land_personnel(state, "BBB") * 0.5, 1.0, "forces de départ")
	var war := WarSystem.civil_war_of(state, "BBB")
	assert_eq(war.seat, "5")
	FrontSystem.refresh(state)
	assert_eq(FrontSystem.fronts_of(state, "BBB_REB").size(), 1)
	faction.personnel = 1.0
	WarSystem.check_civil_wars(state)
	assert_null(WarSystem.civil_war_of(state, "BBB"), "rebelles écrasés")
	assert_eq(ControlSystem.controller(state, "4"), "BBB")


func test_rebels_lose_their_last_province() -> void:
	var start := {"rebels": {"list": [["BBB", "BBB_REB", [[4, 0.2]], "2025-01-01", 0.5]]}}
	var state := _world(start)
	ControlSystem.advance(state, "4", "BBB", 0.5)
	WarSystem.check_civil_wars(state)
	assert_null(WarSystem.civil_war_of(state, "BBB"), "plus de terrain, plus de guerre")
	assert_false(WarSystem.is_rebel(state, "BBB_REB"))

extends GutTest
## Actions ponctuelles : stock de missiles, frappes (bâtiment, infrastructures, front), opérations spéciales,
## cyberattaques (effets, découverte), durées et reconstitution mensuelle.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 900,
		"infrastructure": 8},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 500,
		"infrastructure": 8},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 400,
		"infrastructure": 8},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 3000000,
		"infrastructure": 6},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4], "center": [184.0, 90.0], "population": 800,
		"infrastructure": 6},
	"7": {"owner": "CCC", "controller": "CCC", "neighbors": [], "center": [100.0, 40.0], "population": 600},
}
const BUILDINGS := {"coal_plant": {"source": "coal", "capacity_gw": 1.0}}

var _defines: Dictionary
var _goals: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_goals = JSON.parse_string(FileAccess.get_file_as_string(WAR_GOALS_PATH))


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
	state.setup(9, GameDate.new(2026, 1, 1), &"CCC")
	var countries := {"AAA": _country(), "BBB": _country(), "CCC": _country()}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"], "war_goals": _goals})
	state.military_settings = state.military_settings.duplicate(true)
	state.energy_definitions["provinces"] = PROVINCES
	state.energy_definitions["buildings"] = BUILDINGS
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	ArmyGroupModel.setup_start(state, countries)
	MilitaryActions.setup_start(state)
	EnergySystem.add_building(state, "4", "coal_plant", 1)
	state.get_country("BBB").energy.capacity["coal"] = 1.0
	return state


func _at_war(state: SimState) -> void:
	var provinces: Array[String] = ["4"]
	TensionSystem.add_claim(state, "AAA", "BBB", provinces)
	WarSystem.declare(state, "AAA", "BBB", "annex")
	FrontSystem.refresh(state)


## Rend toutes les actions sûres (chance 1) ou vouées à l'échec (chance 0).
func _force(state: SimState, value: float) -> void:
	for section: String in ["missiles", "special", "cyber"]:
		var rules: Dictionary = state.military_settings["actions"][section]
		rules["min"] = value
		rules["max"] = value


func test_missile_stock_and_air_defense() -> void:
	var state := _world()
	var military := state.get_country("AAA").military
	assert_almost_eq(military.missile_stock, 40.0 * float(_defines["military"]["actions"]["missiles"]["stock_per_point"]),
		0.001)
	var weak := MilitaryActions.chance(state, "AAA", MilitaryActions.CYBER, MilitaryActions.ECONOMY, "BBB")
	state.get_country("BBB").military.special["cyber"] = 90.0
	assert_lt(MilitaryActions.chance(state, "AAA", MilitaryActions.CYBER, MilitaryActions.ECONOMY, "BBB"), weak,
		"une meilleure cyberdéfense protège")
	assert_gt(MilitaryActions.air_defense(state, "BBB"), 0.0)


func test_refusals() -> void:
	var state := _world()
	assert_eq(MilitaryActions.refusal(state, "AAA", MilitaryActions.STRIKE, MilitaryActions.BUILDING, "4", "coal_plant"),
		"ACTION_NOT_ENEMY", "pas en guerre")
	_at_war(state)
	assert_eq(MilitaryActions.refusal(state, "AAA", MilitaryActions.STRIKE, MilitaryActions.BUILDING, "5", "coal_plant"),
		"ACTION_NO_BUILDING")
	assert_eq(MilitaryActions.refusal(state, "AAA", MilitaryActions.STRIKE, MilitaryActions.BUILDING, "4", "coal_plant"), "")
	assert_eq(MilitaryActions.refusal(state, "AAA", MilitaryActions.CYBER, MilitaryActions.ECONOMY, "AAA"), "ACTION_INVALID")
	assert_eq(MilitaryActions.refusal(state, "AAA", MilitaryActions.CYBER, MilitaryActions.ECONOMY, "CCC"), "",
		"cyberattaque possible en paix")
	state.get_country("AAA").military.missile_stock = 0.5
	assert_eq(MilitaryActions.refusal(state, "AAA", MilitaryActions.STRIKE, MilitaryActions.INFRASTRUCTURE, "4"),
		"ACTION_NO_MISSILES")


func test_strike_destroys_a_power_plant() -> void:
	var state := _world()
	_at_war(state)
	_force(state, 1.0)
	var stock := state.get_country("AAA").military.missile_stock
	var opinion := state.diplomacy.opinion("CCC", "AAA")
	var result := MilitaryActionCommand.new(&"AAA", MilitaryActions.STRIKE, MilitaryActions.BUILDING, "4", "coal_plant")
	assert_eq(result.refusal_reason(state), "")
	result.execute(state)
	assert_eq(EnergySystem.building_count(state, "4", "coal_plant"), 0, "centrale détruite")
	assert_almost_eq(float(state.get_country("BBB").energy.capacity["coal"]), 0.0, 0.001)
	assert_almost_eq(state.get_country("AAA").military.missile_stock, stock - 1.0, 0.001)
	assert_lt(state.diplomacy.opinion("CCC", "AAA"), opinion, "victimes civiles dans une province très peuplée")


func test_strike_on_front_and_infrastructure() -> void:
	var state := _world()
	_at_war(state)
	_force(state, 1.0)
	var front: Front = FrontSystem.fronts_of(state, "AAA")[0]
	MilitaryActions.execute(state, "AAA", MilitaryActions.STRIKE, MilitaryActions.FRONT, front.key)
	var penalty := float(_defines["military"]["actions"]["missiles"]["front_penalty"])
	assert_almost_eq(MilitaryActions.front_penalty(state, front, "BBB"), penalty, 0.0001, "camp ennemi affaibli")
	assert_almost_eq(MilitaryActions.front_penalty(state, front, "AAA"), 0.0, 0.0001)
	for _day: int in int(_defines["military"]["actions"]["missiles"]["front_days"]):
		MilitaryActions.update_day(state)
	assert_almost_eq(MilitaryActions.front_penalty(state, front, "BBB"), 0.0, 0.0001, "effet temporaire")
	var supply := WarResolver.supply(state, front, "BBB", "5")
	MilitaryActions.execute(state, "AAA", MilitaryActions.STRIKE, MilitaryActions.INFRASTRUCTURE, "4")
	assert_lt(WarResolver.supply(state, front, "BBB", "5"), supply, "ravitaillement gêné")
	for _month: int in 3:
		MilitaryActions.update_month(state)
	assert_false(state.infrastructure_damage.has("4"), "infrastructures réparées")


func test_cyberattack_effects_and_discovery() -> void:
	var state := _world()
	_force(state, 1.0)
	var rules: Dictionary = state.military_settings["actions"]["cyber"]
	rules["discovery_base"] = 1.0
	var relation := state.diplomacy.relation("AAA", "CCC")
	var result := MilitaryActions.execute(state, "AAA", MilitaryActions.CYBER, MilitaryActions.ECONOMY, "CCC")
	assert_true(bool(result["success"]))
	assert_true(bool(result["discovered"]))
	assert_lt(state.get_country("CCC").economy.attack_growth, 0.0, "croissance touchée")
	assert_lt(state.diplomacy.relation("AAA", "CCC"), relation, "découverte : relations dégradées")
	assert_eq(MilitaryActions.refusal(state, "AAA", MilitaryActions.CYBER, MilitaryActions.GRID, "CCC"), "MILITARY_COOLDOWN")
	for _month: int in int(rules["economy_months"]):
		MilitaryActions.update_month(state)
	assert_almost_eq(state.get_country("CCC").economy.attack_growth, 0.0, 0.0001, "effet passé")
	var morale := float(state.get_country("CCC").military.branches["land"]["morale"])
	state.get_country("AAA").military.action_cooldowns.clear()
	MilitaryActions.execute(state, "AAA", MilitaryActions.CYBER, MilitaryActions.ARMY, "CCC")
	assert_lt(float(state.get_country("CCC").military.branches["land"]["morale"]), morale)


func test_failed_special_operation() -> void:
	var state := _world()
	_at_war(state)
	_force(state, 0.0)
	var front: Front = FrontSystem.fronts_of(state, "AAA")[0]
	var before := MilitaryActions.gauge(state, "AAA", "special_forces")
	var result := MilitaryActions.execute(state, "AAA", MilitaryActions.SPECIAL, MilitaryActions.FRONT, front.key)
	assert_false(bool(result["success"]))
	assert_lt(MilitaryActions.gauge(state, "AAA", "special_forces"), before, "forces spéciales usées")
	assert_almost_eq(MilitaryActions.front_penalty(state, front, "BBB"), 0.0, 0.0001)


func test_monthly_missile_regeneration() -> void:
	var state := _world()
	var military := state.get_country("AAA").military
	military.missile_stock = 0.0
	MilitaryActions.update_month(state)
	assert_almost_eq(military.missile_stock, MilitaryActions.max_missiles(state, "AAA")
		* float(_defines["military"]["actions"]["missiles"]["regen_share"]), 0.001)

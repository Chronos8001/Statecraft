extends GutTest
## Guerre navale : blocus (commerce maritime), détroits fermés par les combats, débarquements (tête de pont,
## échec, rembarquement), IA navale.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
## AAA 1-2-3 | BBB 4-5. Mers : 100 (côte 2), 101 (côtes 3, 4), 102 (côte 5), 104 au-delà d'un détroit. 1 est
## à l'intérieur des terres.
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 900,
		"sea_neighbors": []},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 500,
		"sea_neighbors": [100]},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 400,
		"sea_neighbors": [101]},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 300,
		"sea_neighbors": [101]},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4], "center": [184.0, 90.0], "population": 800,
		"sea_neighbors": [102], "terrain": "plains"},
}
const SEA_ZONES := {
	"100": {"kind": "sea", "center": [180.5, 92.0], "neighbors": [101], "coasts": [2]},
	"101": {"kind": "sea", "center": [182.5, 92.0], "neighbors": [100, 102], "coasts": [3, 4]},
	"102": {"kind": "sea", "center": [184.0, 92.0], "neighbors": [101], "coasts": [5]},
	"104": {"kind": "sea", "center": [190.0, 92.0], "neighbors": [], "coasts": []},
}
const STRAITS := {"narrows": {"sea_zones": [102, 104]}}

var _defines: Dictionary
var _goals: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_goals = JSON.parse_string(FileAccess.get_file_as_string(WAR_GOALS_PATH))


func _country(sea_share: float) -> Dictionary:
	var branches := {"land": {"share": 0.8 - sea_share, "level": 3.0, "training": 54.0, "morale": 60.0},
		"air": {"share": 0.2, "level": 3.0, "training": 54.0, "morale": 60.0},
		"sea": {"share": sea_share, "level": 3.0, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic", "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": 400000, "reserve_personnel": 100000},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 10, "cyber": 30},
			"nuclear_warheads": 0}}


## AAA a une grande marine, BBB une petite.
func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"AAA")
	var countries := {"AAA": _country(0.4), "BBB": _country(0.05)}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"], "war_goals": _goals, "sea_zones": SEA_ZONES, "straits": STRAITS})
	state.military_settings = state.military_settings.duplicate(true)
	state.energy_definitions["provinces"] = PROVINCES
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	ArmyGroupModel.setup_start(state, countries)
	NavalModel.setup_start(state)
	var provinces: Array[String] = ["5"]
	TensionSystem.add_claim(state, "AAA", "BBB", provinces)
	WarSystem.declare(state, "AAA", "BBB", "annex")
	return state


## Toutes les flottes de AAA dans une mer, celles de BBB au loin.
func _place_fleets(state: SimState, ours: String) -> void:
	for fleet: Fleet in state.fleets.values():
		fleet.path.clear()
		fleet.zone = ours if fleet.owner == "AAA" else "104"


func test_land_neighbors_escape_blockade() -> void:
	var state := _world()
	assert_true((state.land_neighbors["AAA"] as Dictionary).has("BBB"))
	state.trade.blockades = {"BBB": 0.5}
	assert_almost_eq(TradeModel.blockade_tariff(state.trade, "BBB", "ZZZ", state.trade_settings),
		0.5 * float(state.trade_settings.get("embargo_tariff", 0.0)), 0.001, "commerce maritime coupé de moitié")
	assert_almost_eq(TradeModel.blockade_tariff(state.trade, "BBB", "AAA", state.trade_settings), 0.0, 0.001,
		"le commerce avec un voisin terrestre continue")


func test_blockade_follows_sea_control() -> void:
	var state := _world()
	_place_fleets(state, "102")
	state.military.naval.resolve_day(state)
	NavalModel.update_blockades(state)
	assert_eq(NavalResolver.controller(state, "102"), "AAA")
	var share := float(state.trade.blockades.get("BBB", 0.0))
	assert_gt(share, 0.5, "la mer de la côte la plus peuplée de BBB est tenue par AAA")
	assert_true(state.trade.dirty)
	assert_eq(state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == NavalModel.EVENT_BLOCKADE and event["tag"] == "BBB").size(), 1)
	WarSystem.end_war(state, WarSystem.war_between(state, "AAA", "BBB"))
	state.military.naval.resolve_day(state)
	NavalModel.update_blockades(state)
	assert_false(state.trade.blockades.has("BBB"), "blocus levé à la paix")


func test_straits_close_while_contested() -> void:
	var state := _world()
	_place_fleets(state, "102")
	for fleet: Fleet in NavalModel.fleets_of(state, "BBB"):
		fleet.zone = "102"
	(state.military_settings["navy"] as Dictionary)["control_ratio"] = 1000.0
	state.military.naval.resolve_day(state)
	NavalModel.update_straits(state)
	assert_true(state.closed_straits.has("narrows"), "mer disputée : détroit fermé")
	assert_true(state.war_closed_straits.has("narrows"))
	for fleet: Fleet in NavalModel.fleets_of(state, "BBB"):
		fleet.zone = "104"
	WarSystem.end_war(state, WarSystem.war_between(state, "AAA", "BBB"))
	state.military.naval.resolve_day(state)
	NavalModel.update_straits(state)
	assert_false(state.closed_straits.has("narrows"), "rouvert une fois la mer calme")


func test_landing_refusals() -> void:
	var state := _world()
	var group := ArmyGroupModel.groups_of(state, "AAA")[0]
	group.province = "1"
	assert_eq(LandingCommand.new(&"AAA", group.id, "3").refusal_reason(state), "LANDING_NOT_ENEMY")
	assert_eq(LandingCommand.new(&"AAA", group.id, "5").refusal_reason(state), "LANDING_GROUP_INLAND")
	group.province = "3"
	_place_fleets(state, "100")
	assert_eq(LandingCommand.new(&"AAA", group.id, "5").refusal_reason(state), "LANDING_NO_FLEET")
	_place_fleets(state, "102")
	state.military.naval.resolve_day(state)
	assert_eq(LandingCommand.new(&"AAA", group.id, "5").refusal_reason(state), "")


func test_landing_success_and_evacuation() -> void:
	var state := _world()
	var rules: Dictionary = state.military_settings["navy"]["landing"]
	rules["min_chance"] = 1.0
	rules["max_chance"] = 1.0
	_place_fleets(state, "102")
	state.military.naval.resolve_day(state)
	var group := ArmyGroupModel.groups_of(state, "AAA")[0]
	group.province = "3"
	LandingCommand.new(&"AAA", group.id, "5").execute(state)
	assert_true(group.is_embarked())
	assert_gt(group.landing_days, 0)
	FrontSystem.refresh(state)
	for _day: int in group.landing_days:
		LandingSystem.update_day(state)
	assert_false(group.is_embarked())
	assert_eq(group.province, "5", "tête de pont")
	assert_almost_eq(ControlSystem.share_held(state, "5", "AAA"), float(rules["beachhead_share"]), 0.0001)
	FrontSystem.refresh(state)
	var front: Front = FrontSystem.fronts_of(state, "AAA").filter(func(candidate: Front) -> bool:
		return candidate.contested.has("5"))[0]
	assert_true(FrontSystem.groups_on(state, front, "AAA").has(group), "le groupe combat sur la tête de pont")
	ControlSystem.advance(state, "5", "BBB", 1.0)
	LandingSystem.update_day(state)
	assert_ne(group.province, "5", "tête de pont perdue : rembarquement")
	assert_eq(state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == LandingSystem.EVENT_EVACUATED).size(), 1)


func test_landing_failure() -> void:
	var state := _world()
	var rules: Dictionary = state.military_settings["navy"]["landing"]
	rules["max_chance"] = 0.0
	rules["min_chance"] = 0.0
	_place_fleets(state, "102")
	state.military.naval.resolve_day(state)
	var group := ArmyGroupModel.groups_of(state, "AAA")[0]
	group.province = "3"
	var military := state.get_country("AAA").military
	var losses := military.losses
	LandingCommand.new(&"AAA", group.id, "5").execute(state)
	for _day: int in group.landing_days:
		LandingSystem.update_day(state)
	assert_eq(group.province, "3", "le groupe reste à quai")
	assert_gt(military.losses, losses, "lourdes pertes")
	assert_almost_eq(ControlSystem.share_held(state, "5", "AAA"), 0.0, 0.0001)


func test_ai_sends_fleets_and_keeps_naval_edge() -> void:
	var state := _world()
	var ai: MilitaryAI = state.military.ai
	for fleet: Fleet in state.fleets.values():
		fleet.zone = fleet.home
	ai.deploy_fleets("AAA", state)
	assert_true(NavalModel.fleets_of(state, "AAA").any(func(fleet: Fleet) -> bool:
		return fleet.destination == "101" or fleet.destination == "102" or fleet.zone == "101"),
		"les flottes vont vers les mers ennemies")
	assert_true(ai.naval_edge(state, "AAA", "BBB"))
	assert_false(ai.naval_edge(state, "BBB", "AAA"))

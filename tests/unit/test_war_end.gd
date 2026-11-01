extends GutTest
## Fin des guerres : soutien à la guerre, score, cessez-le-feu (fronts figés), paix négociée (cession,
## réparations), refus, propositions au joueur, IA.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 900},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 500},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 400},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 300},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4], "center": [184.0, 90.0], "population": 800},
	"7": {"owner": "CCC", "controller": "CCC", "neighbors": [], "center": [100.0, 40.0], "population": 600},
}

var _defines: Dictionary
var _goals: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_goals = JSON.parse_string(FileAccess.get_file_as_string(WAR_GOALS_PATH))


func _country(personnel: int) -> Dictionary:
	var branches := {"land": {"share": 0.7, "level": 3.0, "training": 54.0, "morale": 60.0},
		"air": {"share": 0.3, "level": 3.0, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic", "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": personnel, "reserve_personnel": personnel / 4},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": 30},
			"nuclear_warheads": 0}}


func _world(player: StringName = &"CCC") -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), player)
	var countries := {"AAA": _country(2000000), "BBB": _country(200000), "CCC": _country(200000)}
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
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	ArmyGroupModel.setup_start(state, countries)
	for tag: String in countries.keys():
		state.military.model.update_country(state.get_country(tag), state)
	return state


func _war(state: SimState) -> War:
	var provinces: Array[String] = ["4"]
	TensionSystem.add_claim(state, "AAA", "BBB", provinces)
	return WarSystem.declare(state, "AAA", "BBB", "annex")


func test_support_starts_and_wears_down() -> void:
	var state := _world()
	var war := _war(state)
	var rules: Dictionary = _defines["military"]["war_end"]["support"]
	assert_almost_eq(WarEnd.support(war, "BBB"), float(rules["defender_start"]), 0.001, "ralliement du défenseur")
	assert_almost_eq(WarEnd.support(war, "AAA"), float(rules["attacker_start"]) - float(_goals["annex"]["legitimacy"])
		* float(rules["attacker_legitimacy_weight"]), 0.001, "guerre d'annexion moins soutenue")
	var before := WarEnd.support(war, "AAA")
	war.casualties["AAA"] = 50000.0
	WarEnd.update_month(state)
	assert_lt(WarEnd.support(war, "AAA"), before - 1.0, "les pertes pèsent")


func test_score_follows_the_ground() -> void:
	var state := _world()
	var war := _war(state)
	assert_almost_eq(WarEnd.score(state, war), 0.0, 0.001)
	ControlSystem.set_controller(state, "4", "AAA")
	assert_gt(WarEnd.score(state, war), 40.0, "but atteint et terrain pris")
	assert_lt(WarEnd.score_for(state, war, "BBB"), 0.0)


func test_ceasefire_freezes_the_front() -> void:
	var state := _world()
	var war := _war(state)
	assert_eq(CeasefireCommand.new(&"CCC", war.id).refusal_reason(state), "WAR_NOT_LEADER")
	war.support["BBB"] = 10.0
	CeasefireCommand.new(&"AAA", war.id).execute(state)
	assert_true(war.in_ceasefire(), "BBB, épuisé, accepte")
	assert_eq(CeasefireCommand.new(&"AAA", war.id).refusal_reason(state), "WAR_IN_CEASEFIRE")
	for front: Front in FrontSystem.fronts_of(state, "AAA"):
		front.postures["AAA"] = "offensive"
	var system := MilitarySystem.new()
	for _day: int in 10:
		system.on_day(state)
	assert_almost_eq(ControlSystem.share_held(state, "4", "AAA"), 0.0, 0.0001, "pas de combat")
	for _month: int in int(_defines["military"]["war_end"]["ceasefire"]["months"]):
		WarEnd.update_month(state)
	assert_false(war.in_ceasefire(), "fin du cessez-le-feu")


func test_negotiated_peace_cedes_and_pays() -> void:
	var state := _world()
	var war := _war(state)
	ControlSystem.set_controller(state, "4", "AAA")
	var demands := WarEnd.available_demands(state, war, "AAA")
	assert_eq(demands.size(), 2, "la province visée et des réparations")
	war.support["BBB"] = 0.0
	assert_true(WarEnd.allowance(state, war, "BBB") >= WarEnd.total_cost(state, war, demands, "BBB"))
	var command := NegotiatePeaceCommand.new(&"AAA", war.id, demands)
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	assert_false(WarSystem.at_war(state, "AAA", "BBB"), "paix signée")
	assert_eq(ControlSystem.owner(state, "4"), "AAA", "province cédée")
	assert_true((state.provinces_by_owner["AAA"] as Array).has("4"))
	assert_true(TensionSystem.is_claimed_by(state, "BBB", "4"), "le cédant garde une revendication")
	assert_eq(state.reparations.size(), 1)
	var debt := state.get_country("BBB").economy.local_debt
	WarEnd.update_month(state)
	assert_gt(state.get_country("BBB").economy.local_debt, debt, "réparations versées")


func test_greedy_demands_are_refused() -> void:
	var state := _world()
	var war := _war(state)
	ControlSystem.set_controller(state, "4", "AAA")
	war.support["BBB"] = 100.0
	var accepted := WarEnd.propose_peace(state, war, "AAA", WarEnd.available_demands(state, war, "AAA"))
	assert_false(accepted, "BBB veut encore se battre")
	assert_true(WarSystem.at_war(state, "AAA", "BBB"))
	assert_eq(ControlSystem.owner(state, "4"), "BBB")
	assert_eq(NegotiatePeaceCommand.new(&"AAA", war.id, []).refusal_reason(state), "DIPLOMACY_COOLDOWN")


func test_player_receives_peace_terms() -> void:
	var state := _world(&"BBB")
	var war := _war(state)
	ControlSystem.set_controller(state, "4", "AAA")
	var demands := WarEnd.available_demands(state, war, "AAA")
	WarEnd.propose_peace(state, war, "AAA", demands)
	assert_eq(state.peace_offers.size(), 1)
	assert_eq(str(state.peace_offers[0]["kind"]), WarEnd.PEACE)
	AnswerPeaceCommand.new(&"BBB", war.id, true).execute(state)
	assert_eq(ControlSystem.owner(state, "4"), "AAA", "le joueur accepte les conditions")


func test_ai_cashes_in_its_lead() -> void:
	var state := _world()
	var war := _war(state)
	ControlSystem.set_controller(state, "4", "AAA")
	war.days = 400
	war.support["BBB"] = 5.0
	state.military.ai.decide_month(state.get_country("AAA"), state)
	assert_eq(ControlSystem.owner(state, "4"), "AAA", "AAA monnaie son avantage")
	assert_false(WarSystem.at_war(state, "AAA", "BBB"))

extends GutTest
## Guerres : justification des buts de guerre, effets d'une déclaration, appel aux armes (IA et joueur),
## entrée en guerre, paix blanche, guerres et rebelles de départ, guerres civiles en cours de partie.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
## AAA 1-2-3 | BBB 4-5 | CCC 7, plus une île de AAA (6) et DDD (8) isolé.
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 900},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 500},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 400},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 300},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4, 7], "center": [184.0, 90.0], "population": 800},
	"6": {"owner": "AAA", "controller": "AAA", "neighbors": [], "center": [150.0, 60.0], "population": 100},
	"7": {"owner": "CCC", "controller": "CCC", "neighbors": [5], "center": [185.0, 90.0], "population": 600},
	"8": {"owner": "DDD", "controller": "DDD", "neighbors": [], "center": [100.0, 40.0], "population": 600},
}
const TAGS := ["AAA", "BBB", "CCC", "DDD"]

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


func _world(start: Dictionary = {}) -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"AAA")
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
		{"settings": _defines["military"], "war_goals": _goals})
	state.energy_definitions["provinces"] = PROVINCES
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	ArmyGroupModel.setup_start(state, countries)
	return state


func _claim(state: SimState, claimant: String, target: String, province_id: String) -> void:
	var provinces: Array[String] = [province_id]
	TensionSystem.add_claim(state, claimant, target, provinces)


func _events(state: SimState, type: StringName) -> Array:
	return state.events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _days(state: SimState, count: int) -> void:
	var system := MilitarySystem.new()
	for _index: int in count:
		system.on_day(state)


func test_war_goals_need_a_justification() -> void:
	var state := _world()
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "annex").refusal_reason(state), "WAR_NO_CLAIM")
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "liberate").refusal_reason(state), "WAR_NOT_OCCUPIED")
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "regime_change").refusal_reason(state), "TENSION_TOO_LOW",
		"tension de départ (55) sous le seuil (60)")
	state.diplomacy.world_tension = 70.0
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "regime_change").refusal_reason(state), "WAR_RELATION_TOO_HIGH")
	state.diplomacy.change_relation("AAA", "BBB", -80.0)
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "regime_change").refusal_reason(state), "")
	_claim(state, "AAA", "BBB", "4")
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "annex").refusal_reason(state), "")
	assert_eq(WarSystem.goal_provinces(state, "AAA", "BBB", "annex"), ["4"])
	assert_eq(DeclareWarCommand.new(&"AAA", "AAA", "annex").refusal_reason(state), "WAR_INVALID")
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "unknown").refusal_reason(state), "WAR_INVALID")


func test_cannot_attack_an_ally() -> void:
	var state := _world()
	_claim(state, "AAA", "BBB", "4")
	DiplomacySystem.add_treaty(state, "mutual_defense", "AAA", "BBB", true)
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "annex").refusal_reason(state), "WAR_ALLIED")


func test_declaration_effects() -> void:
	var state := _world()
	_claim(state, "AAA", "BBB", "4")
	DiplomacySystem.add_treaty(state, "non_aggression", "AAA", "BBB", true)
	var relation := state.diplomacy.relation("AAA", "BBB")
	var legitimacy := state.get_country("AAA").society.start_legitimacy
	var rally := state.get_country("BBB").society.start_stability
	var tension := state.diplomacy.world_tension
	var opinion := state.diplomacy.opinion("DDD", "AAA")
	DeclareWarCommand.new(&"AAA", "BBB", "annex").execute(state)
	assert_true(WarSystem.at_war(state, "AAA", "BBB"))
	assert_true(WarSystem.at_war(state, "BBB", "AAA"))
	assert_false(WarSystem.at_war(state, "AAA", "CCC"))
	var war := WarSystem.war_between(state, "AAA", "BBB")
	assert_eq(war.goal_provinces, ["4"])
	assert_lt(state.diplomacy.relation("AAA", "BBB"), relation)
	assert_true(state.diplomacy.treaties_between("AAA", "BBB").is_empty(), "traités rompus")
	assert_true(state.trade.trade_blocked("AAA", "BBB"), "commerce coupé")
	assert_lt(state.get_country("AAA").society.start_legitimacy, legitimacy, "guerre d'annexion : légitimité en baisse")
	assert_gt(state.get_country("BBB").society.start_stability, rally, "ralliement autour du drapeau")
	assert_gt(state.diplomacy.world_tension, tension)
	assert_lt(state.diplomacy.opinion("DDD", "AAA"), opinion, "le reste du monde désapprouve")
	assert_eq(_events(state, WarSystem.EVENT_DECLARED).size(), 1)
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "annex").refusal_reason(state), "WAR_ALREADY")


func test_allies_answer_the_call() -> void:
	var state := _world()
	_claim(state, "AAA", "BBB", "4")
	DiplomacySystem.add_treaty(state, "mutual_defense", "BBB", "CCC", true)
	DiplomacySystem.add_treaty(state, "mutual_defense", "BBB", "DDD", true)
	state.diplomacy.change_relation("BBB", "CCC", 90.0)
	state.diplomacy.change_relation("BBB", "DDD", -90.0)
	assert_eq(WarSystem.defenders_called(state, "AAA", "BBB"), ["CCC", "DDD"])
	var trust := state.diplomacy.trust("BBB", "DDD")
	DeclareWarCommand.new(&"AAA", "BBB", "annex").execute(state)
	var war := WarSystem.war_between(state, "AAA", "BBB")
	assert_eq(war.defenders, ["BBB", "CCC"], "CCC répond à l'appel, DDD refuse")
	assert_true(WarSystem.at_war(state, "AAA", "CCC"))
	assert_lt(state.diplomacy.trust("BBB", "DDD"), trust, "le refus coûte de la confiance")
	assert_eq(_events(state, WarSystem.EVENT_CALL_REFUSED).size(), 1)


func test_player_call_to_arms() -> void:
	var state := _world()
	state.player_tag = &"CCC"
	_claim(state, "AAA", "BBB", "4")
	DiplomacySystem.add_treaty(state, "mutual_defense", "BBB", "CCC", true)
	DeclareWarCommand.new(&"AAA", "BBB", "annex").execute(state)
	var war := WarSystem.war_between(state, "AAA", "BBB")
	assert_false(war.involves("CCC"), "le joueur répond lui-même")
	assert_eq(state.calls_to_arms.size(), 1)
	assert_eq(AnswerCallToArmsCommand.new(&"DDD", war.id, true).refusal_reason(state), "WAR_INVALID")
	AnswerCallToArmsCommand.new(&"CCC", war.id, true).execute(state)
	assert_true(war.defenders.has("CCC"))
	assert_true(state.calls_to_arms.is_empty())


func test_unanswered_call_is_refused() -> void:
	var state := _world()
	state.player_tag = &"CCC"
	_claim(state, "AAA", "BBB", "4")
	DiplomacySystem.add_treaty(state, "mutual_defense", "BBB", "CCC", true)
	DeclareWarCommand.new(&"AAA", "BBB", "annex").execute(state)
	var days := int((_defines["military"]["war"]["call_to_arms"] as Dictionary)["days"])
	_days(state, days - 1)
	assert_eq(state.calls_to_arms.size(), 1)
	_days(state, 1)
	assert_true(state.calls_to_arms.is_empty())
	assert_false(WarSystem.war_between(state, "AAA", "BBB").involves("CCC"))
	assert_eq(_events(state, WarSystem.EVENT_CALL_REFUSED).size(), 1)


func test_join_a_war() -> void:
	var state := _world()
	_claim(state, "AAA", "BBB", "4")
	DeclareWarCommand.new(&"AAA", "BBB", "annex").execute(state)
	var war := WarSystem.war_between(state, "AAA", "BBB")
	state.diplomacy.change_relation("DDD", "AAA", -50.0)
	assert_eq(JoinWarCommand.new(&"DDD", war.id, War.ATTACKERS).refusal_reason(state), "WAR_RELATION_TOO_LOW")
	assert_eq(JoinWarCommand.new(&"AAA", war.id, War.DEFENDERS).refusal_reason(state), "WAR_ALREADY")
	state.diplomacy.change_relation("DDD", "AAA", 100.0)
	var command := JoinWarCommand.new(&"DDD", war.id, War.ATTACKERS)
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	assert_eq(war.attackers, ["AAA", "DDD"])
	assert_true(WarSystem.at_war(state, "DDD", "BBB"))
	assert_true(state.trade.trade_blocked("DDD", "BBB"))


func test_white_peace_restores_prewar_control() -> void:
	var state := _world()
	ControlSystem.set_controller(state, "5", "AAA")
	_claim(state, "AAA", "BBB", "4")
	DeclareWarCommand.new(&"AAA", "BBB", "annex").execute(state)
	var war := WarSystem.war_between(state, "AAA", "BBB")
	assert_eq(war.prewar, {"5": "AAA"}, "province déjà tenue avant la guerre")
	ControlSystem.set_controller(state, "3", "BBB")
	ControlSystem.set_controller(state, "4", "AAA")
	WarSystem.end_war(state, war)
	assert_false(WarSystem.at_war(state, "AAA", "BBB"))
	assert_eq(ControlSystem.controller(state, "3"), "AAA", "conquête rendue")
	assert_eq(ControlSystem.controller(state, "4"), "BBB", "conquête rendue")
	assert_eq(ControlSystem.controller(state, "5"), "AAA", "situation d'avant-guerre gardée")
	assert_false(state.trade.trade_blocked("AAA", "BBB"), "commerce rétabli")
	assert_eq(DeclareWarCommand.new(&"AAA", "BBB", "annex").refusal_reason(state), "WAR_TRUCE")
	assert_eq(_events(state, WarSystem.EVENT_ENDED).size(), 1)


func test_white_peace_answer() -> void:
	var state := _world()
	_claim(state, "AAA", "BBB", "4")
	DeclareWarCommand.new(&"AAA", "BBB", "annex").execute(state)
	var war := WarSystem.war_between(state, "AAA", "BBB")
	assert_eq(WhitePeaceCommand.new(&"CCC", war.id).refusal_reason(state), "WAR_NOT_LEADER")
	var score := WarSystem.white_peace_score(state, war, "AAA")
	ControlSystem.set_controller(state, "5", "AAA")
	assert_gt(WarSystem.white_peace_score(state, war, "AAA"), score, "BBB, occupé, tient plus à la paix")
	assert_gt(WarSystem.occupied_percent(state, war, War.DEFENDERS), 0.0)
	var command := WhitePeaceCommand.new(&"BBB", war.id)
	command.execute(state)
	assert_true(WarSystem.at_war(state, "AAA", "BBB"), "AAA, qui tient du terrain, refuse")
	assert_eq(WhitePeaceCommand.new(&"BBB", war.id).refusal_reason(state), "DIPLOMACY_COOLDOWN")


func test_start_wars_and_rebels() -> void:
	var start := {"claims": {"list": [["AAA", "BBB", [4]]]},
		"wars": {"list": [["AAA", "BBB", "annex", "2025-01-01", [5]]]},
		"rebels": {"list": [["BBB", "BBB_REB", [[5, 1.0], [4, 0.5]]]]}}
	var state := _world(start)
	var war := WarSystem.war_between(state, "AAA", "BBB")
	assert_not_null(war)
	assert_eq(war.days, 365, "guerre commencée un an plus tôt")
	assert_eq(war.goal_provinces, ["4"])
	assert_true(WarSystem.at_war(state, "BBB", "BBB_REB"))
	assert_true(WarSystem.is_rebel(state, "BBB_REB"))
	assert_eq(ControlSystem.controller(state, "5"), "BBB_REB")
	assert_almost_eq(ControlSystem.share_held(state, "4", "BBB_REB"), 0.5, 0.0001)
	assert_eq(WarSystem.country_of(state, "BBB_REB"), "BBB")
	assert_eq(ArmyGroupModel.groups_of(state, "BBB")[0].province, "4", "BBB défend face aux rebelles")
	WarSystem.end_civil_war(state, "BBB")
	assert_eq(ControlSystem.controller(state, "5"), "BBB")
	assert_false(state.contested.has("4"))
	assert_false(WarSystem.is_rebel(state, "BBB_REB"))
	assert_true(WarSystem.at_war(state, "AAA", "BBB"), "la guerre entre États continue")


func test_civil_war_breaks_out() -> void:
	var state := _world()
	WarSystem.start_civil_war(state, "AAA")
	var war := WarSystem.civil_war_of(state, "AAA")
	assert_not_null(war)
	assert_true(war.civil)
	assert_eq(war.attackers, ["AAA_REB"])
	assert_almost_eq(ControlSystem.share_held(state, "6", "AAA_REB"), 0.3, 0.0001, "province la plus éloignée")
	assert_false(state.contested.has("2"))
	assert_eq(WhitePeaceCommand.new(&"AAA", war.id).refusal_reason(state), "WAR_INVALID", "pas de paix blanche avec des rebelles")


func test_real_start_data() -> void:
	var start: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/diplomacy/start.json"))
	var provinces: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/provinces/provinces.json"))
	for entry: Array in (start["rebels"] as Dictionary)["list"]:
		for hold: Array in entry[2]:
			var province: Dictionary = provinces.get(str(int(hold[0])), {})
			assert_eq(str(province.get("owner", "")), str(entry[0]), "province %d dans le bon pays" % int(hold[0]))
			assert_between(float(hold[1]), 0.0, 1.0)
	for entry: Array in (start["wars"] as Dictionary)["list"]:
		assert_true(_goals.has(str(entry[2])))

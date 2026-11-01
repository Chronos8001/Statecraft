extends GutTest
## IA militaire : choix d'une guerre (but justifié, rapport de forces, alliés de la cible), déclaration,
## recherche de la paix (avec le joueur : proposition en attente), mobilisation, entrée en guerre volontaire.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const TERRAINS_PATH := "res://data/terrains/terrains.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
## AAA 1-2-3 | BBB 4-5 ; CCC 7 voisin de BBB ; DDD 8 isolé.
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 900},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 500},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 400},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 300},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4, 7], "center": [184.0, 90.0], "population": 800},
	"7": {"owner": "CCC", "controller": "CCC", "neighbors": [5], "center": [185.0, 90.0], "population": 600},
	"8": {"owner": "DDD", "controller": "DDD", "neighbors": [], "center": [100.0, 40.0], "population": 600},
}
const PERSONNEL := {"AAA": 2000000, "BBB": 200000, "CCC": 200000, "DDD": 200000}

var _defines: Dictionary
var _goals: Dictionary
var _terrains: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_goals = JSON.parse_string(FileAccess.get_file_as_string(WAR_GOALS_PATH))
	_terrains = JSON.parse_string(FileAccess.get_file_as_string(TERRAINS_PATH))


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


func _world(player: StringName = &"DDD") -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), player)
	var countries: Dictionary = {}
	for tag: String in PERSONNEL.keys():
		countries[tag] = _country(int(PERSONNEL[tag]))
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"], "war_goals": _goals, "terrains": _terrains})
	state.energy_definitions["provinces"] = PROVINCES
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	ArmyGroupModel.setup_start(state, countries)
	for tag: String in PERSONNEL.keys():
		state.military.model.update_country(state.get_country(tag), state)
	state.military.ai.begin_month(state)
	return state


func _claim(state: SimState) -> void:
	var provinces: Array[String] = ["4"]
	TensionSystem.add_claim(state, "AAA", "BBB", provinces)


func test_borders() -> void:
	var state := _world()
	var ai: MilitaryAI = state.military.ai
	assert_eq(ai.best_war(state.get_country("BBB"), state), {}, "BBB, plus faible, ne cherche pas la guerre")
	assert_eq(ai.war_score(state, state.get_country("AAA"), "BBB"), {}, "pas de but justifié")


func test_strong_neighbor_with_claim_wants_war() -> void:
	var state := _world()
	var ai: MilitaryAI = state.military.ai
	_claim(state)
	state.diplomacy.change_relation("AAA", "BBB", -80.0)
	var best := ai.best_war(state.get_country("AAA"), state)
	assert_eq(best.get("target"), "BBB")
	assert_eq(best.get("goal"), "annex")
	assert_gt(float(best["score"]), 0.0)
	var score := float(best["score"])
	state.diplomacy.change_relation("AAA", "BBB", 100.0)
	assert_lt(float(ai.war_score(state, state.get_country("AAA"), "BBB").get("score", 0.0)), score, "de meilleures relations calment")


func test_allies_of_the_target_deter() -> void:
	var state := _world()
	var ai: MilitaryAI = state.military.ai
	_claim(state)
	state.diplomacy.change_relation("AAA", "BBB", -80.0)
	var alone := float(ai.war_score(state, state.get_country("AAA"), "BBB")["score"])
	DiplomacySystem.add_treaty(state, "mutual_defense", "BBB", "CCC", true)
	var defended := ai.war_score(state, state.get_country("AAA"), "BBB")
	assert_lt(float(defended.get("score", 0.0)), alone, "l'allié de BBB compte dans le rapport de forces")
	DiplomacySystem.add_treaty(state, "mutual_defense", "AAA", "BBB", true)
	assert_eq(ai.best_war(state.get_country("AAA"), state), {}, "on n'attaque pas un allié")


func test_declares_war() -> void:
	var state := _world()
	var ai: MilitaryAI = state.military.ai
	_claim(state)
	state.diplomacy.change_relation("AAA", "BBB", -80.0)
	state.military_settings = state.military_settings.duplicate(true)
	var rules: Dictionary = state.military_settings["ai"]["war"]
	rules["chance_per_point"] = 1.0
	rules["max_chance"] = 1.0
	ai.decide_month(state.get_country("AAA"), state)
	assert_true(WarSystem.at_war(state, "AAA", "BBB"))
	assert_eq(state.get_country("AAA").military.mobilization, 0, "mobilisation au mois suivant")
	ai.decide_month(state.get_country("AAA"), state)
	assert_eq(state.get_country("AAA").military.mobilization, 1, "en guerre, mobilisation partielle")


func test_losing_side_seeks_peace() -> void:
	var state := _world(&"AAA")
	var ai: MilitaryAI = state.military.ai
	_claim(state)
	var war := WarSystem.declare(state, "AAA", "BBB", "annex")
	assert_false(ai.wants_peace(state, war, "AAA"), "AAA, plus fort, ne veut pas la paix")
	assert_true(ai.wants_peace(state, war, "BBB"), "BBB, bien plus faible, cherche la paix")
	ai.decide_month(state.get_country("BBB"), state)
	assert_eq(state.peace_offers.size(), 0, "trop tôt (moins de 3 mois)")
	war.days = 120
	ai.decide_month(state.get_country("BBB"), state)
	assert_eq(state.peace_offers.size(), 1, "proposition au joueur")
	assert_eq(AnswerPeaceCommand.new(&"CCC", war.id, true).refusal_reason(state), "WAR_INVALID")
	AnswerPeaceCommand.new(&"AAA", war.id, false).execute(state)
	assert_true(WarSystem.at_war(state, "AAA", "BBB"))
	assert_eq(WarSystem.white_peace_refusal(state, "BBB", war.id), "DIPLOMACY_COOLDOWN", "délai avant une nouvelle offre")
	state.diplomacy.cooldowns.clear()
	WarSystem.offer_peace(state, war, "BBB")
	AnswerPeaceCommand.new(&"AAA", war.id, true).execute(state)
	assert_false(WarSystem.at_war(state, "AAA", "BBB"), "paix acceptée")


func test_unanswered_peace_offer_expires() -> void:
	var state := _world(&"AAA")
	_claim(state)
	var war := WarSystem.declare(state, "AAA", "BBB", "annex")
	WarSystem.offer_peace(state, war, "BBB")
	var days := int(_defines["military"]["ai"]["peace"]["player_days"])
	for _day: int in days:
		WarSystem.update_day(state)
	assert_true(state.peace_offers.is_empty())
	assert_true(WarSystem.at_war(state, "AAA", "BBB"))


func test_peace_between_ai_countries() -> void:
	var state := _world()
	_claim(state)
	var war := WarSystem.declare(state, "AAA", "BBB", "annex")
	ControlSystem.set_controller(state, "4", "AAA")
	WarSystem.offer_peace(state, war, "BBB")
	assert_true(WarSystem.at_war(state, "AAA", "BBB"), "AAA, qui tient du terrain, refuse")
	assert_true(state.peace_offers.is_empty())


func test_voluntary_join() -> void:
	var state := _world()
	var ai: MilitaryAI = state.military.ai
	_claim(state)
	var war := WarSystem.declare(state, "AAA", "BBB", "annex")
	assert_false(ai.join_score(state, war, "CCC", War.DEFENDERS), "relations neutres")
	state.diplomacy.change_relation("DDD", "AAA", 90.0)
	state.diplomacy.change_relation("DDD", "BBB", -90.0)
	state.diplomacy.change_relation("CCC", "BBB", 80.0)
	state.diplomacy.change_relation("CCC", "AAA", -80.0)
	assert_false(ai.join_score(state, war, "CCC", War.DEFENDERS), "AAA reste bien plus fort")
	state.diplomacy.change_relation("CCC", "AAA", 160.0)
	state.diplomacy.change_relation("CCC", "BBB", -160.0)
	assert_true(ai.join_score(state, war, "CCC", War.ATTACKERS), "ami de AAA, voisin et ennemi de BBB, camp fort")
	assert_false(ai.join_score(state, war, "DDD", War.ATTACKERS), "DDD, loin de tout, ne s'en mêle pas")
	state.get_country("BBB").military.nuclear_warheads = 10
	assert_false(ai.join_score(state, war, "CCC", War.ATTACKERS), "jamais contre une puissance nucléaire")

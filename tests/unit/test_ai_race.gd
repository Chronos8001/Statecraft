extends GutTest
## Course à l'IA : niveau de départ et classement, bonus du pays en tête, adoption progressive, régulation,
## chômage d'automatisation, désinformation, plan national, premier pays à l'IA générale.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const TECHNOLOGIES := {
	"llm": {"name_key": "TECH_LLM", "tree": "ai", "year": 2026, "cost": 100, "requires": [],
		"start": {"countries": ["AAA"]}, "effects": {}},
	"agents": {"name_key": "TECH_AGENTS", "tree": "ai", "year": 2026, "cost": 200, "requires": [], "effects": {}},
	"general_ai": {"name_key": "TECH_GENERAL_AI", "tree": "ai", "year": 2026, "cost": 500, "requires": [],
		"effects": {}},
}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(gdp: float, rd: float) -> Dictionary:
	var branches := {"land": {"share": 1.0, "level": 3.0, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": "republic", "capital": 1,
		"economy": {"gdp_billion_usd": gdp, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": 100000, "reserve_personnel": 10000},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": 40},
			"nuclear_warheads": 0},
		"research": {"rd_gdp_share": rd, "universities": 5}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"AAA")
	var countries := {"AAA": _country(2000.0, 3.0), "BBB": _country(300.0, 1.0), "CCC": _country(100.0, 0.5)}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"]},
		{"technologies": TECHNOLOGIES, "settings": (_defines["research"] as Dictionary).duplicate(true)})
	return state


func _rules(state: SimState) -> Dictionary:
	return AiRaceSystem.rules_of(state)


func test_start_level_and_leader() -> void:
	var state := _world()
	var aaa := state.get_country("AAA")
	var bbb := state.get_country("BBB")
	assert_gt(aaa.research.ai_level, bbb.research.ai_level, "technologies et points de recherche")
	assert_almost_eq(aaa.research.ai_level, AiRaceSystem.target_level(state, aaa), 0.001, "départ à sa cible")
	assert_eq(AiRaceSystem.leader(state), "AAA")
	assert_eq(AiRaceSystem.rank(state, "BBB"), 2)
	var leader: Dictionary = _rules(state)["leader"]
	assert_almost_eq(aaa.research.ai_research, float(leader["research"]), 0.001)
	assert_almost_eq(bbb.research.ai_research, 0.0, 0.001, "seul le pays en tête a le bonus")
	assert_gt(aaa.economy.ai_growth, bbb.economy.ai_growth)


func test_gradual_adoption_creates_unemployment() -> void:
	var state := _world()
	var bbb := state.get_country("BBB")
	var before := bbb.research.ai_level
	ResearchSystem.complete(state, bbb, "llm")
	var target := AiRaceSystem.target_level(state, bbb)
	assert_gt(target, before, "nouvelle technologie d'IA : cible plus haute")
	AiRaceSystem.update_country(state, bbb)
	assert_gt(bbb.research.ai_level, before)
	assert_lt(bbb.research.ai_level, target, "adoption progressive")
	assert_gt(bbb.research.ai_displaced, 0.0, "automatisation : chômage")
	var displaced := bbb.research.ai_displaced
	bbb.research.ai_level = target
	AiRaceSystem.update_country(state, bbb)
	assert_lt(bbb.research.ai_displaced, displaced, "résorbé quand le niveau ne monte plus")
	AiRaceSystem.apply_effects(state, bbb)
	assert_almost_eq(bbb.economy.ai_unemployment, bbb.research.ai_displaced, 0.0001)


func test_regulation_trades_speed_for_safety() -> void:
	var results := {}
	for option: String in ["open", "strict"]:
		var state := _world()
		var bbb := state.get_country("BBB")
		bbb.laws["ai_regulation"] = option
		var before := bbb.research.ai_level
		ResearchSystem.complete(state, bbb, "llm")
		AiRaceSystem.update_country(state, bbb)
		AiRaceSystem.apply_effects(state, bbb)
		results[option] = [bbb.research.ai_level - before, bbb.research.ai_displaced, bbb.ai_stability]
	assert_gt(float(results["open"][0]), float(results["strict"][0]), "libre : adoption plus rapide")
	assert_gt(float(results["open"][1]), float(results["strict"][1]), "libre : plus de chômage")
	assert_lt(float(results["open"][2]), float(results["strict"][2]), "libre : plus de désinformation")


func test_disinformation_depends_on_social_networks() -> void:
	var state := _world()
	var aaa := state.get_country("AAA")
	aaa.laws["social_networks"] = "free"
	AiRaceSystem.apply_effects(state, aaa)
	var free := aaa.ai_stability
	assert_lt(free, 0.0)
	assert_gt(aaa.ai_volatility, 0.0, "sondages plus agités")
	aaa.laws["social_networks"] = "restricted"
	AiRaceSystem.apply_effects(state, aaa)
	assert_gt(aaa.ai_stability, free, "réseaux restreints : moins exposé")


func test_national_plan() -> void:
	var state := _world()
	var bbb := state.get_country("BBB")
	var target := AiRaceSystem.target_level(state, bbb)
	var command := LaunchAiPlanCommand.new(&"BBB")
	assert_true(command.can_execute(state))
	command.execute(state)
	var plan: Dictionary = _rules(state)["plan"]
	assert_eq(bbb.research.ai_plan_months, int(plan["months"]))
	assert_eq(command.refusal_reason(state), "AI_PLAN_ACTIVE")
	assert_almost_eq(AiRaceSystem.target_level(state, bbb), target + float(plan["target"]), 0.001)
	assert_gt(AiRaceSystem.plan_cost(state, "BBB"), 0.0)
	AiRaceSystem.update_country(state, bbb)
	assert_eq(bbb.research.ai_plan_months, int(plan["months"]) - 1)
	assert_gt(bbb.research.ai_level, target, "le niveau dépasse son ancienne cible")


func test_first_to_general_ai() -> void:
	var state := _world()
	var bbb := state.get_country("BBB")
	state.diplomacy.change_relation("CCC", "BBB", -40.0)
	var relation := state.diplomacy.relation("CCC", "BBB")
	var tension := state.diplomacy.world_tension
	var research := bbb.research.effect(ResearchSystem.RESEARCH)
	ResearchSystem.complete(state, bbb, "general_ai")
	AiRaceSystem.check_general_ai(state)
	assert_eq(state.agi_first, "BBB")
	assert_gt(bbb.research.effect(ResearchSystem.RESEARCH), research, "grand bond")
	assert_gt(state.diplomacy.world_tension, tension, "la tension monte")
	assert_lt(state.diplomacy.relation("CCC", "BBB"), relation, "les rivaux s'inquiètent")
	var aaa := state.get_country("AAA")
	var other := aaa.research.effect(ResearchSystem.RESEARCH)
	ResearchSystem.complete(state, aaa, "general_ai")
	AiRaceSystem.check_general_ai(state)
	assert_eq(state.agi_first, "BBB", "un seul premier")
	assert_almost_eq(aaa.research.effect(ResearchSystem.RESEARCH), other, 0.001, "pas de bond pour les suivants")


func test_monthly_system_and_leader_change() -> void:
	var state := _world()
	var bbb := state.get_country("BBB")
	bbb.research.ai_level = 100.0
	for tech_id: String in TECHNOLOGIES.keys():
		bbb.research.known[tech_id] = true
	bbb.research.points = 1000.0
	AiRaceSystem.new().on_month(state)
	assert_eq(AiRaceSystem.leader(state), "BBB")
	var types: Array = state.events.map(func(event: Dictionary) -> StringName: return event["type"])
	assert_true(types.has(AiRaceSystem.EVENT_LEADER), "changement de tête annoncé")
	assert_gt(bbb.research.ai_cyber, 0.0)
	assert_almost_eq(state.get_country("AAA").research.ai_cyber, 0.0, 0.001, "l'ancien premier perd son bonus")

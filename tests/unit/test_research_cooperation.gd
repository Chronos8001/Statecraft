extends GutTest
## Coopération scientifique : diffusion par les pays proches, projets conjoints (accord, avancement commun,
## achèvement pour tous, départ d'un membre), espionnage industriel (chance, avancement, découverte, délai), IA.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const TECHNOLOGIES := {
	"base": {"name_key": "TECH_BASE", "tree": "economy", "year": 2026, "cost": 100, "requires": [],
		"start": {"countries": ["AAA"]}, "effects": {}},
	"shared": {"name_key": "TECH_SHARED", "tree": "industry", "year": 2026, "cost": 200, "requires": [],
		"effects": {}},
	"weapon": {"name_key": "TECH_WEAPON", "tree": "air", "year": 2026, "cost": 200, "requires": [], "effects": {}},
}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(regime: String, cyber: float) -> Dictionary:
	var branches := {"land": {"share": 1.0, "level": 3.0, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": regime, "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": 100000, "reserve_personnel": 10000},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": cyber},
			"nuclear_warheads": 0},
		"research": {"rd_gdp_share": 2.0, "universities": 2}}


## AAA (joueur, démocratie), BBB (démocratie), CCC (régime autoritaire, cyber élevé).
func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"AAA")
	var countries := {"AAA": _country("republic", 40.0), "BBB": _country("republic", 40.0),
		"CCC": _country("autocracy", 80.0)}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"republic": {"democratic": true, "group_influence": {}},
				"autocracy": {"democratic": false, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"]},
		{"technologies": TECHNOLOGIES, "settings": (_defines["research"] as Dictionary).duplicate(true)})
	return state


func _joint_rules(state: SimState) -> Dictionary:
	return ResearchSystem.settings_of(state)["joint"]


func _espionage_rules(state: SimState) -> Dictionary:
	return ResearchSystem.settings_of(state)["espionage"]


func test_diffusion_discount() -> void:
	var state := _world()
	var bbb := state.get_country("BBB")
	var alone := ResearchSystem.cost(state, "base", bbb)
	state.research_close["BBB"] = ["AAA"]
	var discount := float(ResearchSystem.settings_of(state)["diffusion"]["discount"])
	assert_almost_eq(ResearchSystem.cost(state, "base", bbb), alone - 100.0 * discount, 0.001, "un proche la connaît")
	assert_almost_eq(ResearchSystem.cost(state, "shared", bbb), ResearchSystem.cost(state, "shared"), 0.001,
		"aucun proche ne la connaît")


func test_joint_refusals() -> void:
	var state := _world()
	assert_eq(ResearchCooperation.joint_refusal(state, "AAA", "BBB", "shared"), "RESEARCH_RELATION_TOO_LOW")
	state.diplomacy.change_relation("AAA", "BBB", 60.0)
	assert_eq(ResearchCooperation.joint_refusal(state, "AAA", "BBB", "shared"), "")
	assert_eq(ResearchCooperation.joint_refusal(state, "BBB", "AAA", "base"), "RESEARCH_PARTNER_CANNOT",
		"le partenaire la connaît déjà")
	assert_eq(ResearchCooperation.joint_refusal(state, "AAA", "AAA", "shared"), "RESEARCH_INVALID")
	assert_eq(ResearchCooperation.joint_refusal(state, "AAA", "BBB", "weapon"), "RESEARCH_NOT_ALLIED",
		"armement : alliés seulement")
	var command := JointProjectCommand.new(&"AAA", "BBB", "shared")
	assert_true(command.can_execute(state))
	assert_eq(command.to_dict()["partner"], "BBB")


func test_joint_acceptance_depends_on_relations() -> void:
	var state := _world()
	state.diplomacy.change_relation("AAA", "BBB", 30.0)
	var score := ResearchCooperation.joint_score(state, "BBB", "AAA")
	state.diplomacy.change_relation("AAA", "BBB", 40.0)
	assert_gt(ResearchCooperation.joint_score(state, "BBB", "AAA"), score)
	assert_true(ResearchCooperation.propose_joint(state, "AAA", "BBB", "shared"), "bonnes relations : accepté")
	assert_false(ResearchCooperation.propose_joint(state, "BBB", "AAA", "base"), "le joueur ne reçoit pas de proposition")


func test_joint_project_progress_and_completion() -> void:
	var state := _world()
	var aaa := state.get_country("AAA")
	var bbb := state.get_country("BBB")
	state.diplomacy.change_relation("AAA", "BBB", 80.0)
	JointProjectCommand.new(&"AAA", "BBB", "shared").execute(state)
	assert_eq(state.joint_projects.size(), 1)
	assert_true(aaa.research.slots.has("shared") and bbb.research.slots.has("shared"), "un emplacement chacun")
	assert_eq(ResearchCooperation.partner_of(state, "AAA", "shared"), "BBB")
	var project: Dictionary = state.joint_projects[0]
	ResearchSystem.advance(state, aaa)
	var after_one := float(project["progress"])
	assert_gt(after_one, 0.0)
	ResearchSystem.advance(state, bbb)
	assert_gt(float(project["progress"]), after_one, "avancement commun")
	for _month: int in 60:
		if state.joint_projects.is_empty():
			break
		ResearchSystem.advance(state, aaa)
		ResearchSystem.advance(state, bbb)
	assert_true(aaa.research.is_known("shared") and bbb.research.is_known("shared"), "acquise par les deux")
	assert_false(aaa.research.slots.has("shared") or bbb.research.slots.has("shared"), "emplacements libérés")


func test_joint_bonus_speeds_research() -> void:
	var state := _world()
	var aaa := state.get_country("AAA")
	state.diplomacy.change_relation("AAA", "BBB", 80.0)
	ResearchCooperation.start_joint(state, "AAA", "BBB", "shared")
	aaa.research.slots = ["shared"]
	ResearchSystem.advance(state, aaa)
	var bonus := float(_joint_rules(state)["speed_bonus"])
	assert_almost_eq(float(state.joint_projects[0]["progress"]), aaa.research.points * (1.0 + bonus), 0.001)


func test_leaving_keeps_progress() -> void:
	var state := _world()
	var aaa := state.get_country("AAA")
	var bbb := state.get_country("BBB")
	state.diplomacy.change_relation("AAA", "BBB", 80.0)
	ResearchCooperation.start_joint(state, "AAA", "BBB", "shared")
	ResearchSystem.advance(state, aaa)
	var done := float(state.joint_projects[0]["progress"])
	ResearchSystem.set_slot(state, aaa, aaa.research.slots.find("shared"), "")
	assert_true(state.joint_projects.is_empty(), "projet dissous")
	assert_almost_eq(float(bbb.research.progress["shared"]), done, 0.001, "l'autre garde l'avancement")
	assert_true(bbb.research.is_researching("shared"), "et poursuit seul")


func test_espionage_success_and_cooldown() -> void:
	var state := _world()
	var rules := _espionage_rules(state)
	rules["min"] = 1.0
	rules["max"] = 1.0
	rules["discovery_base"] = 0.0
	rules["discovery_weight"] = 0.0
	var bbb := state.get_country("BBB")
	assert_eq(StealTechnologyCommand.new(&"BBB", "AAA", "shared").refusal_reason(state), "RESEARCH_TARGET_UNKNOWN")
	var command := StealTechnologyCommand.new(&"BBB", "AAA", "base")
	assert_true(command.can_execute(state))
	var result := ResearchCooperation.steal(state, "BBB", "AAA", "base")
	assert_true(bool(result["success"]))
	assert_false(bool(result["discovered"]))
	assert_almost_eq(float(bbb.research.progress["base"]),
		ResearchSystem.cost(state, "base", bbb) * float(rules["progress_share"]), 0.001)
	assert_eq(command.refusal_reason(state), "MILITARY_COOLDOWN", "délai entre deux opérations")
	ResearchCooperation.steal(state, "BBB", "AAA", "base")
	assert_true(bbb.research.is_known("base"), "deux réussites : technologie acquise")


func test_espionage_discovery_hurts_relations() -> void:
	var state := _world()
	var rules := _espionage_rules(state)
	rules["discovery_base"] = 1.0
	var relation := state.diplomacy.relation("BBB", "AAA")
	var trust := state.diplomacy.trust("BBB", "AAA")
	assert_true(bool(ResearchCooperation.steal(state, "BBB", "AAA", "base")["discovered"]))
	assert_lt(state.diplomacy.relation("BBB", "AAA"), relation)
	assert_lt(state.diplomacy.trust("BBB", "AAA"), trust)


func test_espionage_chance_follows_cyber() -> void:
	var state := _world()
	assert_gt(ResearchCooperation.espionage_chance(state, "CCC", "AAA"),
		ResearchCooperation.espionage_chance(state, "AAA", "CCC"))
	assert_gt(ResearchCooperation.discovery_chance(state, "CCC"), ResearchCooperation.discovery_chance(state, "AAA"))


func test_ai_espionage_only_for_hostile_autocracies() -> void:
	var state := _world()
	_espionage_rules(state)["ai_chance"] = 1.0
	_joint_rules(state)["ai_chance"] = 0.0
	ResearchCooperation.decide_month(state, state.get_country("BBB"))
	assert_eq(state.get_country("BBB").research.espionage_cooldown, 0, "une démocratie n'espionne pas")
	ResearchCooperation.decide_month(state, state.get_country("CCC"))
	assert_eq(state.get_country("CCC").research.espionage_cooldown, 0, "pas sans hostilité")
	state.diplomacy.change_relation("CCC", "AAA", -50.0)
	ResearchCooperation.decide_month(state, state.get_country("CCC"))
	assert_gt(state.get_country("CCC").research.espionage_cooldown, 0, "régime autoritaire hostile : il espionne")


func test_ai_joint_project_with_close_country() -> void:
	var state := _world()
	_joint_rules(state)["ai_chance"] = 1.0
	_espionage_rules(state)["ai_chance"] = 0.0
	state.diplomacy.change_relation("BBB", "CCC", 80.0)
	state.research_close["BBB"] = ["AAA", "CCC"]
	ResearchCooperation.decide_month(state, state.get_country("BBB"))
	assert_eq(state.joint_projects.size(), 1, "projet avec un proche de l'IA (jamais imposé au joueur)")
	assert_false((state.joint_projects[0]["members"] as Array).has("AAA"))
	assert_eq(str(state.joint_projects[0]["tech"]), "shared", "pas d'armement sans alliance")

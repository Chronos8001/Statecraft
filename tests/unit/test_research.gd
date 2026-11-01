extends GutTest
## Recherche : connaissances de départ (indice, armée, liste de pays), points et emplacements, disponibilité,
## avancement et effets, rattrapage, choix de l'IA.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const TECHNOLOGIES := {
	"base": {"name_key": "TECH_BASE", "tree": "economy", "year": 2026, "cost": 100, "requires": [],
		"start": {"index": 60}, "effects": {"growth": 0.5}},
	"next": {"name_key": "TECH_NEXT", "tree": "land", "year": 2026, "cost": 60, "requires": ["base"],
		"effects": {"military:land": 0.5, "special:cyber": 10.0, "stability": 2.0}},
	"future": {"name_key": "TECH_FUTURE", "tree": "economy", "year": 2030, "cost": 50, "requires": [], "effects": {}},
	"exclusive": {"name_key": "TECH_EXCLUSIVE", "tree": "air", "year": 2026, "cost": 400, "requires": [],
		"start": {"countries": ["BBB"]}, "effects": {}},
	"army": {"name_key": "TECH_ARMY", "tree": "land", "year": 2026, "cost": 80, "requires": [],
		"start": {"military": ["land", 3.0]}, "effects": {}},
}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(gdp: float, rd: float, universities: int, level: float) -> Dictionary:
	var branches := {"land": {"share": 0.7, "level": level, "training": 54.0, "morale": 60.0},
		"air": {"share": 0.3, "level": level, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic", "capital": 1,
		"economy": {"gdp_billion_usd": gdp, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": 100000, "reserve_personnel": 10000},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": 30},
			"nuclear_warheads": 0},
		"research": {"rd_gdp_share": rd, "universities": universities}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"AAA")
	var countries := {"AAA": _country(800.0, 3.0, 10, 3.5), "BBB": _country(20.0, 0.2, 0, 2.0)}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"]}, {"technologies": TECHNOLOGIES, "settings": _defines["research"]})
	return state


func test_starting_knowledge() -> void:
	var state := _world()
	var rich := state.get_country("AAA").research
	var poor := state.get_country("BBB").research
	assert_gt(ResearchSystem.tech_index(state, state.get_country("AAA")), ResearchSystem.tech_index(state, state.get_country("BBB")))
	assert_true(rich.is_known("base"), "indice suffisant")
	assert_false(poor.is_known("base"))
	assert_true(poor.is_known("exclusive"), "liste de pays")
	assert_false(rich.is_known("exclusive"))
	assert_true(rich.is_known("army"), "armée de terre au niveau demandé")
	assert_false(poor.is_known("army"))
	assert_false(rich.is_known("future"), "pas avant son année")


func test_points_and_slots() -> void:
	var state := _world()
	var rich := state.get_country("AAA")
	var poor := state.get_country("BBB")
	assert_gt(rich.research.points, poor.research.points)
	var rules: Dictionary = _defines["research"]
	assert_eq(poor.research.slots.size(), int(rules["slots"]["min"]))
	var before := ResearchSystem.monthly_points(state, rich)
	rich.economy.budget.effects["research"] = 10.0
	assert_gt(ResearchSystem.monthly_points(state, rich), before, "le budget de la recherche compte")


func test_availability_and_command() -> void:
	var state := _world()
	var poor := state.get_country("BBB")
	assert_eq(ResearchSystem.availability(state, poor, "next"), "RESEARCH_MISSING_PREREQUISITE")
	assert_eq(ResearchSystem.availability(state, poor, "future"), "RESEARCH_TOO_EARLY")
	assert_eq(ResearchSystem.availability(state, poor, "exclusive"), "RESEARCH_ALREADY_KNOWN")
	assert_eq(SetResearchCommand.new(&"AAA", 0, "next").refusal_reason(state), "")
	SetResearchCommand.new(&"AAA", 0, "next").execute(state)
	assert_eq(SetResearchCommand.new(&"AAA", 1, "next").refusal_reason(state), "RESEARCH_ALREADY")
	assert_eq(SetResearchCommand.new(&"AAA", 9, "base").refusal_reason(state), "RESEARCH_INVALID")


func test_completion_applies_effects() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	SetResearchCommand.new(&"AAA", 0, "next").execute(state)
	var stability := country.society.start_stability
	for _month: int in 24:
		ResearchSystem.advance(state, country)
	assert_true(country.research.is_known("next"), "technologie achevée")
	assert_eq(country.research.slots[0], "", "emplacement libéré")
	assert_almost_eq(country.military.tech_levels["land"], 0.5, 0.0001)
	assert_almost_eq(country.military.tech_special["cyber"], 10.0, 0.0001)
	assert_almost_eq(country.society.start_stability, stability + 2.0, 0.0001)
	var level := float((country.military.branches["land"] as Dictionary)["level"])
	state.military.model.update_country(country, state)
	assert_gt(float((country.military.branches["land"] as Dictionary)["level"]), level, "l'équipement progresse")


func test_growth_effect_is_scaled() -> void:
	var state := _world()
	var poor := state.get_country("BBB")
	ResearchSystem.complete(state, poor, "base")
	assert_almost_eq(poor.economy.research_growth, 0.5 * float(_defines["research"]["growth_scale"]), 0.0001)


func test_catch_up_and_ai() -> void:
	var state := _world()
	ResearchSystem.refresh_known_counts(state)
	assert_lt(ResearchSystem.cost(state, "base"), 100.0, "déjà connue ailleurs : moins chère")
	assert_almost_eq(ResearchSystem.cost(state, "future"), 50.0, 0.001)
	var poor := state.get_country("BBB")
	ResearchSystem.choose_research(state, poor)
	assert_true(poor.research.slots.has("base") or poor.research.slots.has("army"), "l'IA remplit ses emplacements")
	assert_false(poor.research.slots.has("future"), "jamais une technologie trop précoce")

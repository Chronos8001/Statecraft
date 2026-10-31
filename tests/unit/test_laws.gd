extends GutTest
## Lois : situation de départ, effets, votes et délais.

const DEFINES_PATH := "res://data/defines.json"
const LAWS_PATH := "res://data/laws/laws.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const GROUPS := {
	"workers": {"influence": 1.0, "affinity": {"left": 15},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
	"elites": {"influence": 4.0, "affinity": {"conservative": 15},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
}
const REGIMES := {"parliamentary_republic": {"democratic": true, "group_influence": {}},
	"one_party_state": {"democratic": false, "group_influence": {}, "legitimacy": 50.0}}
const IDEOLOGIES := {"socialist": {"party_group": "left"}, "conservative": {"party_group": "conservative"}}
const PARTIES := {"pty_aaa_1": {"ideology": "socialist"}, "pty_aaa_2": {"ideology": "conservative"}}

var _defines: Dictionary
var _laws: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_laws = JSON.parse_string(FileAccess.get_file_as_string(LAWS_PATH))


func _world(regime: String, government_seats: int, tag: String = "AAA") -> SimState:
	var state := SimState.new()
	state.setup(4, GameDate.new(), StringName(tag))
	var parliament := {"seats": 100, "government": ["pty_aaa_1"], "other_seats": 0, "other_vote": 0.0,
		"other_poll": 0.0, "election": {"year": 2023, "month": 1}, "term_years": 5,
		"system": {"type": "proportional", "threshold": 5.0}, "next_election": {"year": 2028, "month": 1},
		"parties": {"pty_aaa_1": {"seats": government_seats, "vote": 50.0, "poll": 50.0},
			"pty_aaa_2": {"seats": 100 - government_seats, "vote": 50.0, "poll": 50.0}}}
	var country := {"population": 10000000, "currency": "usd", "regime": regime, "ideology": "socialist",
		"economy": {"gdp_billion_usd": 400.0, "debt_to_gdp": 0.6, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 0.8, "elites": 0.2}, "stability": 60.0, "corruption": 30.0,
			"democracy": 8.0, "approval": 40.0}, "parliament": parliament}
	WorldSetup.populate(state, {tag: country}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, _defines["investment"],
		{"groups": GROUPS, "regimes": REGIMES, "ideologies": IDEOLOGIES, "settings": _defines["society"]},
		{"parties": PARTIES, "characters": {}, "provinces": {}, "laws": _laws, "settings": _defines["politics"]})
	return state


func test_start_rules() -> void:
	var context := {"tag": "FRA", "democratic": true, "democracy": 8.0, "gdp_per_capita": 45000.0}
	assert_eq(LawModel.start_option(_laws["death_penalty"], context), "abolished")
	assert_eq(LawModel.start_option(_laws["working_hours"], context), "h35")
	context["tag"] = "USA"
	assert_eq(LawModel.start_option(_laws["death_penalty"], context), "active")
	assert_eq(LawModel.start_option(_laws["gun_ownership"], context), "free")
	var dictatorship := {"tag": "ZZZ", "democratic": false, "democracy": 2.0, "gdp_per_capita": 2000.0}
	assert_eq(LawModel.start_option(_laws["judicial_independence"], dictatorship), "controlled")
	assert_eq(LawModel.start_option(_laws["child_labour"], dictatorship), "tolerated")


func test_start_is_neutral() -> void:
	var country := _world("parliamentary_republic", 60).get_country("AAA")
	assert_eq(country.laws.size(), _laws.size())
	var effects := LawModel.aggregate(_laws, country.laws, country.start_laws)
	assert_true((effects[LawModel.GROUPS] as Dictionary).is_empty())
	assert_false(effects.has("growth"))


func test_majority_passes_a_law() -> void:
	var state := _world("parliamentary_republic", 60)
	var country := state.get_country("AAA")
	var command := ChangeLawCommand.new(&"AAA", "minimum_wage", "high")
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	assert_eq(country.laws["minimum_wage"], "high")
	assert_eq(state.events[0]["type"], ChangeLawCommand.EVENT_LAW_PASSED)
	assert_eq(int(state.events[0]["yes"]), 60)
	assert_lt(country.economy.law_growth, 0.0, "un salaire minimum élevé freine la croissance")
	assert_gt(float(country.law_effects[LawModel.GROUPS]["workers"]), 0.0)
	assert_eq(command.refusal_reason(state), "LAWS_ALREADY")
	assert_eq(ChangeLawCommand.new(&"AAA", "minimum_wage", "none").refusal_reason(state), "LAWS_COOLDOWN")
	for _month: int in 12:
		LawSystem.new().on_month(state)
	assert_eq(ChangeLawCommand.new(&"AAA", "minimum_wage", "none").refusal_reason(state), "")


func test_opposition_majority_rejects() -> void:
	var state := _world("parliamentary_republic", 40)
	ChangeLawCommand.new(&"AAA", "minimum_wage", "high").execute(state)
	assert_eq(state.get_country("AAA").laws["minimum_wage"], "moderate")
	assert_eq(state.events[0]["type"], ChangeLawCommand.EVENT_LAW_REJECTED)
	assert_eq(ChangeLawCommand.new(&"AAA", "minimum_wage", "high").refusal_reason(state), "LAWS_COOLDOWN")


func test_both_sides_agree() -> void:
	var state := _world("parliamentary_republic", 40)
	var result: Dictionary = ChangeLawCommand.expected_vote(state, state.get_country("AAA"), "anti_corruption", "strong")
	assert_true(bool(result["passed"]), "la gauche et la droite soutiennent une agence anticorruption forte")


func test_decree_and_effects() -> void:
	var state := _world("one_party_state", 40)
	var country := state.get_country("AAA")
	assert_null(ChangeLawCommand.expected_vote(state, country, "press_freedom", "free"))
	var corruption := country.society.corruption
	ChangeLawCommand.new(&"AAA", "press_freedom", "free").execute(state)
	assert_eq(country.laws["press_freedom"], "free", "le pouvoir décide seul")
	assert_lt(country.society.corruption, corruption)
	ChangeLawCommand.new(&"AAA", "healthcare", "universal").execute(state)
	assert_gt(country.economy.law_spending, 0.0, "la santé publique coûte au budget")

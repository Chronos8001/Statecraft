extends GutTest
## Constitution : réformes, référendums, limite des mandats, état d'urgence.

const DEFINES_PATH := "res://data/defines.json"
const REFORMS_PATH := "res://data/constitution/reforms.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const GROUPS := {
	"workers": {"influence": 1.0, "affinity": {"left": 15},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
	"elites": {"influence": 4.0, "affinity": {"conservative": 15},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
}
const REGIMES := {"parliamentary_republic": {"democratic": true, "group_influence": {}},
	"presidential_republic": {"democratic": true, "group_influence": {}},
	"one_party_state": {"democratic": false, "group_influence": {}, "legitimacy": 50.0}}
const IDEOLOGIES := {"socialist": {"party_group": "left"}, "conservative": {"party_group": "conservative"}}
const PARTIES := {"pty_aaa_1": {"ideology": "conservative", "leader": "chr_a1"},
	"pty_aaa_2": {"ideology": "socialist", "leader": "chr_a2"}}

var _defines: Dictionary
var _reforms: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_reforms = JSON.parse_string(FileAccess.get_file_as_string(REFORMS_PATH))


func _world(regime: String, government_seats: int, term_limit: String = "two", terms_served: int = 1) -> SimState:
	var state := SimState.new()
	state.setup(8, GameDate.new(), &"AAA")
	state.date.year = 2026
	state.date.month = 2
	var parliament := {"seats": 100, "government": ["pty_aaa_1"], "other_seats": 0, "other_vote": 0.0,
		"other_poll": 0.0, "election": {"year": 2023, "month": 1}, "term_years": 5,
		"system": {"type": "proportional", "threshold": 5.0}, "next_election": {"year": 2026, "month": 4},
		"parties": {"pty_aaa_1": {"seats": government_seats, "vote": 50.0, "poll": 55.0},
			"pty_aaa_2": {"seats": 100 - government_seats, "vote": 50.0, "poll": 45.0}}}
	if regime == "presidential_republic":
		parliament["presidency"] = {"election": {"year": 2021, "month": 3}, "term_years": 5, "two_rounds": true,
			"next_election": {"year": 2026, "month": 3}}
	var country := {"population": 10000000, "currency": "usd", "regime": regime, "ideology": "conservative",
		"head_of_state": "chr_a1", "constitution": {"term_limit": term_limit, "terms_served": terms_served},
		"economy": {"gdp_billion_usd": 400.0, "debt_to_gdp": 0.6, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 0.8, "elites": 0.2}, "stability": 60.0, "corruption": 30.0,
			"democracy": 8.0, "approval": 50.0}, "parliament": parliament}
	WorldSetup.populate(state, {"AAA": country}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, _defines["investment"],
		{"groups": GROUPS, "regimes": REGIMES, "ideologies": IDEOLOGIES, "settings": _defines["society"]},
		{"parties": PARTIES, "characters": {"chr_a1": {"party": "pty_aaa_1"}}, "provinces": {}, "laws": {},
			"constitution": _reforms, "settings": _defines["politics"]})
	return state


func test_start_options() -> void:
	var country := _world("presidential_republic", 60).get_country("AAA")
	assert_eq(country.constitution["presidential_term_limit"], "two")
	assert_eq(country.constitution["presidential_term"], "t5")
	assert_eq(country.constitution["electoral_system"], "proportional")
	assert_eq(country.constitution["threshold"], "medium")
	assert_eq(country.constitution["executive"], "presidential")
	assert_eq(country.politics.term_limit, 2)


func test_two_thirds_required() -> void:
	var weak := _world("parliamentary_republic", 60)
	ConstitutionalReformCommand.new(&"AAA", "electoral_system", "majoritarian").execute(weak)
	assert_eq(weak.get_country("AAA").constitution["electoral_system"], "proportional", "60 % ne suffit pas")
	assert_eq(weak.events[0]["type"], ConstitutionSystem.EVENT_REFORM_REJECTED)
	var strong := _world("parliamentary_republic", 70)
	ConstitutionalReformCommand.new(&"AAA", "electoral_system", "majoritarian").execute(strong)
	var politics := strong.get_country("AAA").politics
	assert_eq(politics.system_type, PoliticsState.SYSTEM_MAJORITARIAN)
	assert_eq(ConstitutionalReformCommand.new(&"AAA", "electoral_system", "mixed").refusal_reason(strong), "LAWS_COOLDOWN")


func test_referendum() -> void:
	var state := _world("parliamentary_republic", 60)
	var command := ConstitutionalReformCommand.new(&"AAA", "electoral_system", "majoritarian",
		ConstitutionalReformCommand.METHOD_REFERENDUM)
	command.execute(state)
	var country := state.get_country("AAA")
	assert_eq(country.politics.pending_referendum["month"], 4)
	assert_eq(ConstitutionalReformCommand.new(&"AAA", "threshold", "low").refusal_reason(state),
		"CONSTITUTION_REFERENDUM_PENDING")
	ConstitutionSystem.new().on_month(state)
	assert_false(country.politics.pending_referendum.is_empty(), "pas encore")
	state.date.month = 4
	ConstitutionSystem.new().on_month(state)
	var held: Array = state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == ConstitutionSystem.EVENT_REFERENDUM_HELD)
	assert_eq(held.size(), 1)
	assert_true(bool(held[0]["passed"]), "la droite, majoritaire dans les sondages, soutient le scrutin majoritaire")
	assert_eq(country.politics.system_type, PoliticsState.SYSTEM_MAJORITARIAN)
	assert_eq(ConstitutionalReformCommand.new(&"AAA", "threshold", "low", ConstitutionalReformCommand.METHOD_REFERENDUM)
		.refusal_reason(_world("one_party_state", 60)), "CONSTITUTION_NO_REFERENDUM")


func test_term_limit_blocks_incumbent_bonus() -> void:
	var state := _world("presidential_republic", 60, "two", 2)
	var politics := state.get_country("AAA").politics
	assert_true(ElectionSystem.term_limited(politics))
	state.date.month = 3
	ElectionSystem.new().on_month(state)
	assert_eq(politics.terms_served, 1, "nouveau président")
	var free := _world("presidential_republic", 60, "none", 3)
	free.date.month = 3
	ElectionSystem.new().on_month(free)
	assert_eq(free.get_country("AAA").politics.terms_served, 4, "réélu sans limite")


func test_executive_reform_creates_a_presidency() -> void:
	var state := _world("parliamentary_republic", 70)
	ConstitutionalReformCommand.new(&"AAA", "executive", "presidential").execute(state)
	var politics := state.get_country("AAA").politics
	assert_eq(politics.regime, "presidential_republic")
	assert_true(politics.has_presidency)
	assert_eq(politics.executive, PoliticsState.EXECUTIVE_PRESIDENTIAL)
	assert_eq(politics.next_presidential_month, 8)


func test_emergency() -> void:
	var weak := _world("parliamentary_republic", 40)
	assert_eq(EmergencyCommand.new(&"AAA").refusal_reason(weak), "CONSTITUTION_NO_MAJORITY")
	var state := _world("parliamentary_republic", 60)
	var country := state.get_country("AAA")
	EmergencyCommand.new(&"AAA").execute(state)
	var legitimacy := country.society.start_legitimacy
	for month: int in 3:
		state.date.month = 3 + month
		ConstitutionSystem.new().on_month(state)
		SocietySystem.new().on_month(state)
		ElectionSystem.new().on_month(state)
	assert_gt(country.society.stability, 60.0)
	assert_lt(country.economy.emergency_growth, 0.0)
	assert_lt(country.society.start_legitimacy, legitimacy)
	assert_eq(country.politics.election_year, 2023, "élections d'avril repoussées")
	EmergencyCommand.new(&"AAA", false).execute(state)
	ElectionSystem.new().on_month(state)
	assert_eq(country.politics.election_year, 2026, "puis tenues")


func test_decree() -> void:
	var state := _world("one_party_state", 40)
	assert_eq(ConstitutionalReformCommand.new(&"AAA", "presidential_term_limit", "none").refusal_reason(state),
		"CONSTITUTION_NO_PRESIDENCY")
	assert_eq(ConstitutionalReformCommand.new(&"AAA", "legislative_term", "t4").refusal_reason(state), "")
	ConstitutionalReformCommand.new(&"AAA", "legislative_term", "t4").execute(state)
	assert_eq(state.get_country("AAA").politics.term_years, 4, "le pouvoir décide seul")

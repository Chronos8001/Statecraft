extends GutTest
## Crises : grèves, réponses, guerre civile, coup d'État.

const DEFINES_PATH := "res://data/defines.json"
const CRISES_PATH := "res://data/crises/crises.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const GROUPS := {
	"workers": {"influence": 1.0, "affinity": {"left": 15},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
	"military": {"influence": 2.0, "affinity": {},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
}
const REGIMES := {"parliamentary_republic": {"democratic": true, "group_influence": {}},
	"authoritarian": {"democratic": false, "group_influence": {}, "legitimacy": 45.0},
	"military_junta": {"democratic": false, "group_influence": {"military": 5.0}, "legitimacy": 25.0}}
const IDEOLOGIES := {"socialist": {"party_group": "left"}}
const PARTIES := {"pty_aaa_1": {"ideology": "socialist"}}

var _defines: Dictionary
var _crises: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_crises = JSON.parse_string(FileAccess.get_file_as_string(CRISES_PATH))
	for crisis: Dictionary in _crises.values():
		crisis["chance"] = 1.0


func _world(regime: String, player: String = "ZZZ", democracy: float = 8.0) -> SimState:
	var state := SimState.new()
	state.setup(21, GameDate.new(), StringName(player))
	var parliament := {"seats": 100, "government": ["pty_aaa_1"], "other_seats": 40, "other_vote": 40.0,
		"other_poll": 40.0, "election": {"year": 2023, "month": 1}, "term_years": 5,
		"system": {"type": "proportional", "threshold": 5.0}, "next_election": {"year": 2030, "month": 1},
		"parties": {"pty_aaa_1": {"seats": 60, "vote": 60.0, "poll": 60.0}}}
	var country := {"population": 10000000, "currency": "usd", "regime": regime, "ideology": "socialist",
		"economy": {"gdp_billion_usd": 400.0, "debt_to_gdp": 0.6, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 0.8, "military": 0.2}, "stability": 50.0, "corruption": 30.0,
			"democracy": democracy, "approval": 50.0}, "parliament": parliament}
	var settings: Dictionary = _defines["politics"].duplicate(true)
	(settings["crises"] as Dictionary)["start_civil_wars"] = []
	(settings["crises"] as Dictionary)["max_group_chance"] = 1.0
	WorldSetup.populate(state, {"AAA": country}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, _defines["investment"],
		{"groups": GROUPS, "regimes": REGIMES, "ideologies": IDEOLOGIES, "settings": _defines["society"]},
		{"parties": PARTIES, "characters": {}, "provinces": {}, "laws": {}, "constitution": {}, "crises": _crises,
			"settings": settings})
	return state


func _strike(state: SimState) -> Dictionary:
	var country := state.get_country("AAA")
	country.society.satisfaction["workers"] = float(country.society.start_satisfaction["workers"]) - 12.0
	CrisisSystem.update_country(country, state)
	for crisis: Dictionary in country.crises:
		if crisis["type"] == "strike":
			return crisis
	return {}


func test_no_crisis_at_start() -> void:
	var state := _world("parliamentary_republic")
	CrisisSystem.update_country(state.get_country("AAA"), state)
	assert_true(state.get_country("AAA").crises.is_empty(), "pas de crise sans dégradation")


func test_strike_and_ai_negotiation() -> void:
	var state := _world("parliamentary_republic")
	var crisis := _strike(state)
	assert_false(crisis.is_empty())
	assert_eq(crisis["response"], "negotiate", "l'IA négocie en démocratie")
	var country := state.get_country("AAA")
	assert_gt(float(country.society.bonuses["workers"]), 0.0)
	assert_lt(country.economy.crisis_growth, 0.0)
	assert_lt(float(country.crisis_effects["stability"]), 0.0)


func test_player_responses() -> void:
	var state := _world("parliamentary_republic", "AAA")
	var crisis := _strike(state)
	assert_false(crisis.has("response"), "le joueur choisit")
	var country := state.get_country("AAA")
	var legitimacy := country.society.start_legitimacy
	var command := CrisisResponseCommand.new(&"AAA", int(crisis["id"]), "repress")
	assert_true(command.can_execute(state))
	command.execute(state)
	assert_true(country.crises.is_empty(), "réprimée, la grève s'arrête")
	assert_lt(country.society.start_legitimacy, legitimacy)
	var second := _strike(state)
	CrisisResponseCommand.new(&"AAA", int(second["id"]), "concede").execute(state)
	assert_almost_eq(float(country.society.bonuses["workers"]), 8.0, 0.001)
	for _month: int in 12:
		country.society.satisfaction["workers"] = float(country.society.start_satisfaction["workers"])
		CrisisSystem.update_country(country, state)
	assert_almost_eq(float(country.society.bonuses["workers"]), 0.0, 0.001, "la concession s'épuise")


func test_civil_war_after_six_months_of_collapse() -> void:
	var state := _world("authoritarian")
	var country := state.get_country("AAA")
	for month: int in 6:
		country.society.stability = 5.0
		country.society.legitimacy = 10.0
		CrisisSystem.update_country(country, state)
	assert_true(CrisisSystem.has_crisis(country, CrisisSystem.CIVIL_WAR))
	assert_lt(country.economy.crisis_growth, -5.0)


func test_coup_installs_a_junta() -> void:
	var state := _world("authoritarian", "ZZZ", 3.0)
	var country := state.get_country("AAA")
	CrisisSystem.install_junta(country, state)
	var politics := country.politics
	assert_eq(politics.regime, "military_junta")
	assert_false(politics.democratic)
	assert_true(politics.suspended, "plus d'élections")
	assert_true(politics.government.is_empty())
	assert_almost_eq(country.society.legitimacy, 25.0, 0.001)
	assert_gt(float(country.society.influence["military"]), 0.5, "l'armée domine")


func test_initial_civil_wars_are_neutral() -> void:
	var state := _world("authoritarian")
	var country := state.get_country("AAA")
	CrisisSystem.start_civil_war(country, state, _crises["civil_war"], true)
	CrisisSystem.refresh_effects(country, state)
	assert_eq(country.economy.crisis_growth, 0.0, "déjà comprise dans la situation de 2026")
	assert_eq(int(country.crisis_effects["severity"]), 5)

extends GutTest
## Gouvernement : ministres, compétence, nominations, scandales.

const DEFINES_PATH := "res://data/defines.json"
const PORTFOLIOS_PATH := "res://data/portfolios/portfolios.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const GROUPS := {
	"workers": {"influence": 1.0, "affinity": {"left": 15},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
	"military": {"influence": 2.0, "affinity": {},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
}
const REGIMES := {"parliamentary_republic": {"democratic": true, "group_influence": {}}}
const IDEOLOGIES := {"socialist": {"name_key": "X", "color": "#FF0000", "party_group": "left"},
	"conservative": {"name_key": "Y", "color": "#0000FF", "party_group": "conservative"}}
const PARTIES := {"pty_aaa_1": {"ideology": "socialist"}, "pty_aaa_2": {"ideology": "conservative"}}

var _defines: Dictionary
var _repository: DataRepository


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_repository = DataRepository.new()
	_repository.load_roots(PackedStringArray(["res://data"]))


func _world() -> SimState:
	var state := SimState.new()
	state.setup(12, GameDate.new(), &"AAA")
	var parliament := {"seats": 100, "government": ["pty_aaa_1", "pty_aaa_2"], "other_seats": 0, "other_vote": 0.0,
		"other_poll": 0.0, "election": {"year": 2023, "month": 1}, "term_years": 5,
		"system": {"type": "proportional", "threshold": 5.0}, "next_election": {"year": 2028, "month": 1},
		"parties": {"pty_aaa_1": {"seats": 75, "vote": 70.0, "poll": 70.0},
			"pty_aaa_2": {"seats": 25, "vote": 30.0, "poll": 30.0}}}
	var country := {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic",
		"ideology": "socialist", "culture": "french",
		"economy": {"gdp_billion_usd": 400.0, "debt_to_gdp": 0.6, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 0.8, "military": 0.2}, "stability": 60.0, "corruption": 40.0,
			"democracy": 8.0, "approval": 50.0}, "parliament": parliament}
	var names := {"cultures": _repository.get_category("names/cultures"),
		"party_styles": _repository.get_category("names/party_styles"), "ideologies": IDEOLOGIES,
		"traits": _repository.get_category("traits"), "settings": _repository.get_value("defines", "characters", {})}
	WorldSetup.populate(state, {"AAA": country}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, _defines["investment"],
		{"groups": GROUPS, "regimes": REGIMES, "ideologies": IDEOLOGIES, "settings": _defines["society"]},
		{"parties": PARTIES, "characters": {}, "provinces": {}, "laws": {}, "constitution": {},
			"portfolios": JSON.parse_string(FileAccess.get_file_as_string(PORTFOLIOS_PATH)), "names": names,
			"settings": _defines["politics"]})
	return state


func test_cabinet_is_formed_and_neutral() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	assert_eq(country.cabinet.size(), 8)
	var parties: Dictionary = {}
	var names: Dictionary = {}
	for portfolio_id: Variant in country.cabinet.keys():
		var minister := GovernmentSystem.character(state, str(country.cabinet[portfolio_id]))
		parties[minister["party"]] = int(parties.get(minister["party"], 0)) + 1
		assert_false(names.has(minister["last_name"]), "pas d'homonyme")
		names[minister["last_name"]] = true
		assert_between(int(minister["loyalty"]), 0, 100)
	assert_eq(int(parties["pty_aaa_1"]), 6, "75 % des sièges, 6 portefeuilles sur 8")
	assert_eq(int(parties["pty_aaa_2"]), 2)
	assert_almost_eq(country.economy.cabinet_growth, 0.0, 0.0001)
	assert_almost_eq(country.society.corruption, 40.0, 0.0001)


func test_candidates_are_stable_until_appointment() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	var first := GovernmentSystem.candidates(country, state, "finance")
	assert_eq(first.size(), 3)
	assert_eq(first[0]["last_name"], GovernmentSystem.candidates(country, state, "finance")[0]["last_name"])
	var stability := country.society.stability
	var command := AppointMinisterCommand.new(&"AAA", "finance", 1)
	assert_true(command.can_execute(state))
	command.execute(state)
	assert_eq(GovernmentSystem.character(state, str(country.cabinet["finance"]))["last_name"], first[1]["last_name"])
	assert_lt(country.society.stability, stability, "un remaniement coûte un peu de stabilité")
	assert_ne(GovernmentSystem.candidates(country, state, "finance")[0]["last_name"], first[0]["last_name"],
		"nouveaux candidats")
	assert_false(AppointMinisterCommand.new(&"AAA", "unknown", 0).can_execute(state))


func test_competence_drives_effects() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	var portfolios: Dictionary = state.politics_definitions["portfolios"]
	var settings := GovernmentModel.settings_of(state)
	var expert := {"skills": {"economy": 8}, "traits": ["economist"], "corruption": 0}
	assert_eq(GovernmentModel.competence(expert, portfolios["finance"], settings), 10.0)
	GovernmentSystem.appoint(country, state, "finance", expert)
	var expected := 0.05 * (10.0 - float(country.start_competence["finance"]))
	assert_almost_eq(country.economy.cabinet_growth, expected, 0.0001)
	assert_lt(country.society.corruption, 40.0, "un ministre intègre fait baisser la corruption")


func test_scandals_replace_corrupt_ministers() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	for portfolio_id: Variant in country.cabinet.keys():
		(state.characters[country.cabinet[portfolio_id]] as Dictionary)["corruption"] = 100
	country.politics.media_factor = 10.0
	var first := str(country.cabinet["justice"])
	var scandals := 0
	for _month: int in 24:
		GovernmentSystem.new().on_month(state)
		for event: Dictionary in state.events:
			if event["type"] == GovernmentSystem.EVENT_SCANDAL:
				scandals += 1
		state.events.clear()
	assert_gt(scandals, 3)
	assert_lt(country.society.start_stability, 60.0)
	assert_eq(country.cabinet.size(), 8, "le ministre est aussitôt remplacé")
	assert_true(first != str(country.cabinet["justice"]) or scandals > 0)

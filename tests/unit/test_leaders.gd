extends GutTest
## Dirigeants : mortalité selon l'âge, succession (même parti, dynastie dans une monarchie), chef de parti
## remplacé, action « leader_died » pour les événements.

const DEFINES_PATH := "res://data/defines.json"
const PORTFOLIOS_PATH := "res://data/portfolios/portfolios.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const GROUPS := {"workers": {"influence": 1.0, "affinity": {},
	"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}}
const REGIMES := {"parliamentary_republic": {"democratic": true, "group_influence": {}},
	"absolute_monarchy": {"democratic": false, "group_influence": {}}}
const IDEOLOGIES := {"socialist": {"name_key": "X", "color": "#FF0000", "party_group": "left"}}
const PARTIES := {"pty_aaa_1": {"ideology": "socialist", "leader": "chr_pm"}}
const CHARACTERS := {
	"chr_pm": {"first_name": "Jean", "last_name": "Martin", "birth_year": 1950, "gender": "male", "party": "pty_aaa_1"},
	"chr_king": {"first_name": "Louis", "last_name": "Bourbon", "birth_year": 1940, "gender": "male"},
}

var _defines: Dictionary
var _repository: DataRepository


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_repository = DataRepository.new()
	_repository.load_roots(PackedStringArray(["res://data"]))


func _world(regime: String = "parliamentary_republic") -> SimState:
	var state := SimState.new()
	state.setup(3, GameDate.new(2026, 1, 1), &"BBB")
	var parliament := {"seats": 100, "government": ["pty_aaa_1"], "other_seats": 0, "other_vote": 0.0,
		"other_poll": 0.0, "election": {"year": 2023, "month": 1}, "term_years": 5,
		"system": {"type": "proportional", "threshold": 5.0}, "next_election": {"year": 2028, "month": 1},
		"parties": {"pty_aaa_1": {"seats": 100, "vote": 100.0, "poll": 100.0}}}
	var country := {"population": 10000000, "currency": "usd", "regime": regime, "ideology": "socialist",
		"culture": "french",
		"economy": {"gdp_billion_usd": 400.0, "debt_to_gdp": 0.6, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 1.0}, "stability": 60.0, "corruption": 40.0, "democracy": 8.0,
			"approval": 50.0}, "parliament": parliament}
	var names := {"cultures": _repository.get_category("names/cultures"),
		"party_styles": _repository.get_category("names/party_styles"), "ideologies": IDEOLOGIES,
		"traits": _repository.get_category("traits"), "settings": _repository.get_value("defines", "characters", {})}
	WorldSetup.populate(state, {"AAA": country}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {},
		_defines["investment"], {"groups": GROUPS, "regimes": REGIMES, "ideologies": IDEOLOGIES,
			"settings": _defines["society"]},
		{"parties": PARTIES, "characters": CHARACTERS.duplicate(true), "provinces": {}, "laws": {}, "constitution": {},
			"portfolios": JSON.parse_string(FileAccess.get_file_as_string(PORTFOLIOS_PATH)), "names": names,
			"settings": _defines["politics"], "leader_settings": _defines["leaders"]})
	var politics := state.get_country("AAA").politics
	politics.head_of_state = "chr_king" if regime == "absolute_monarchy" else "chr_pm"
	politics.head_of_government = "chr_pm"
	return state


func test_mortality_grows_with_age() -> void:
	var settings: Dictionary = _defines["leaders"]
	var at_50 := LeaderSystem.monthly_death_chance(50, settings)
	var at_70 := LeaderSystem.monthly_death_chance(70, settings)
	var at_90 := LeaderSystem.monthly_death_chance(90, settings)
	assert_lt(at_50, at_70)
	assert_lt(at_70, at_90)
	var annual_70 := 1.0 - pow(1.0 - at_70, 12.0)
	assert_almost_eq(annual_70, float(settings["mortality_at_reference"]) * float(settings["office_factor"]), 0.001,
		"mortalité annuelle de référence à 70 ans")
	assert_lt(1.0 - pow(1.0 - LeaderSystem.monthly_death_chance(130, settings), 12.0),
		float(settings["max_annual"]) + 0.001, "plafonnée")


func test_death_and_succession() -> void:
	var state := _world()
	state.event_actions = {"leader_died": ["x"]}
	var country := state.get_country("AAA")
	var stability := country.society.stability
	assert_true(LeaderSystem.kill(state, country, LeaderSystem.HEAD_OF_GOVERNMENT, "natural"))
	var successor_id := country.politics.head_of_government
	assert_ne(successor_id, "chr_pm")
	assert_eq(country.politics.head_of_state, successor_id, "il occupait les deux fonctions")
	var successor := GovernmentSystem.character(state, successor_id)
	assert_eq(str(successor["party"]), "pty_aaa_1", "successeur du même parti")
	assert_between(state.date.year - int(successor["birth_year"]), 30, 80, "âge plausible")
	assert_true(state.dead_characters.has("chr_pm"))
	assert_eq(LeaderSystem.party_leader(state, "pty_aaa_1"), successor_id, "il prend la tête du parti")
	assert_lt(country.society.stability, stability + 0.001)
	assert_eq(state.action_queue.size(), 1, "action « leader_died » pour les événements")
	assert_eq(str(state.action_queue[0]["cause"]), "natural")


func test_monarchy_keeps_dynasty() -> void:
	var state := _world("absolute_monarchy")
	var country := state.get_country("AAA")
	country.politics.democratic = false
	var stability := country.society.stability
	assert_true(LeaderSystem.kill(state, country, LeaderSystem.HEAD_OF_STATE, "event"))
	assert_eq(country.politics.head_of_government, "chr_pm", "le chef du gouvernement reste")
	assert_eq(str(GovernmentSystem.character(state, country.politics.head_of_state)["last_name"]), "Bourbon")
	assert_almost_eq(country.society.stability, stability - float(_defines["leaders"]["autocratic_shock"]["stability"]),
		0.001)


func test_old_leaders_die_over_time() -> void:
	var state := _world()
	(state.politics_definitions["characters"]["chr_pm"] as Dictionary)["birth_year"] = 1920
	var system := LeaderSystem.new()
	for _month: int in 240:
		system.on_month(state)
	assert_ne(state.get_country("AAA").politics.head_of_government, "chr_pm", "un dirigeant de 106 ans finit par mourir")


func test_kill_leader_effect() -> void:
	var state := _world()
	ScriptEffects.apply(state, {"country": "AAA", "from": ""},
		{"kill_leader": {"role": "head_of_state", "cause": "assassination"}})
	assert_ne(state.get_country("AAA").politics.head_of_state, "chr_pm")
	assert_eq(ScriptEffects.validate({"kill_leader": "king"}, "x", []).size(), 1)

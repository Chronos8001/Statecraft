extends GutTest
## Élections : votes régionaux, répartition des sièges, formation du gouvernement, présidentielle, calendrier.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const GROUPS := {
	"workers": {"influence": 1.0, "affinity": {"left": 15, "conservative": -5},
		"reactions": {"unemployment": -4.0, "inflation": -2.0, "growth": 1.0, "blackout": -50.0, "public_ownership": 20.0}},
	"elites": {"influence": 4.0, "affinity": {"left": -20, "conservative": 15},
		"reactions": {"unemployment": 0.0, "inflation": -1.0, "growth": 3.0, "blackout": -40.0, "public_ownership": -60.0}},
}
const REGIMES := {"parliamentary_republic": {"democratic": true, "group_influence": {}},
	"presidential_republic": {"democratic": true, "group_influence": {}},
	"one_party_state": {"democratic": false, "group_influence": {}, "legitimacy": 50.0}}
const IDEOLOGIES := {"socialist": {"party_group": "left"}, "conservative": {"party_group": "conservative"},
	"green": {"party_group": "green"}}
const PARTIES := {"pty_aaa_1": {"ideology": "socialist", "leader": "chr_a1"},
	"pty_aaa_2": {"ideology": "conservative", "leader": "chr_a2"}, "pty_aaa_3": {"ideology": "green", "leader": "chr_a3"}}
const CHARACTERS := {"chr_a1": {"party": "pty_aaa_1"}, "chr_a2": {"party": "pty_aaa_2"}, "chr_a3": {"party": "pty_aaa_3"}}
const PROVINCES := [["1", 5000000, 100.0], ["2", 3000000, 20000.0], ["3", 2000000, 50000.0]]

var _defines: Dictionary
var _settings: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_settings = _defines["politics"]["elections"]


func _parliament(polls: Array, system: Dictionary, next: Array) -> Dictionary:
	return {"seats": 100, "government": ["pty_aaa_1"], "other_seats": 0, "other_vote": 0.0, "other_poll": 0.0,
		"election": {"year": 2022, "month": 3}, "term_years": 4, "system": system,
		"next_election": {"year": next[0], "month": next[1]}, "parties": {
			"pty_aaa_1": {"seats": 52, "vote": 45.0, "poll": polls[0]},
			"pty_aaa_2": {"seats": 40, "vote": 40.0, "poll": polls[1]},
			"pty_aaa_3": {"seats": 8, "vote": 15.0, "poll": polls[2]}}}


func _world(regime: String, polls: Array, system: Dictionary = {"type": "proportional", "threshold": 5.0},
		presidency: Dictionary = {}) -> SimState:
	var state := SimState.new()
	state.setup(3, GameDate.new(), &"AAA")
	state.date.year = 2026
	state.date.month = 3
	var parliament := _parliament(polls, system, [2026, 3])
	if not presidency.is_empty():
		parliament["presidency"] = presidency
	var country := {"population": 10000000, "currency": "usd", "regime": regime, "ideology": "socialist",
		"head_of_state": "chr_a1", "economy": {"gdp_billion_usd": 1000.0, "debt_to_gdp": 0.6, "growth": 2.0,
			"inflation": 2.0, "unemployment": 5.0, "budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0,
			"sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 0.8, "elites": 0.2}, "stability": 60.0, "corruption": 30.0,
			"democracy": 7.5, "approval": 40.0}, "parliament": parliament}
	WorldSetup.populate(state, {"AAA": country}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {},
		_defines["investment"], {"groups": GROUPS, "regimes": REGIMES, "ideologies": IDEOLOGIES,
			"settings": _defines["society"]},
		{"parties": PARTIES, "characters": CHARACTERS, "provinces": {"AAA": PROVINCES}, "settings": _defines["politics"]})
	return state


func test_dhondt_respects_threshold() -> void:
	var seats := ElectionModel.dhondt({"a": 48.0, "b": 40.0, "c": 8.0, "d": 4.0}, 100, 5.0)
	assert_eq(seats["d"], 0, "sous le seuil")
	assert_eq(int(seats["a"]) + int(seats["b"]) + int(seats["c"]), 100)
	assert_gt(int(seats["a"]), 48, "D'Hondt avantage légèrement les grands partis")


func test_majoritarian_gives_a_bonus_to_the_leader() -> void:
	var regional := {"1": {"a": 40.0, "b": 35.0, "c": 25.0}, "2": {"a": 40.0, "b": 35.0, "c": 25.0},
		"3": {"a": 40.0, "b": 35.0, "c": 25.0}}
	var seats := ElectionModel.majoritarian(regional, PROVINCES, 100, 2.0)
	assert_eq(int(seats["a"]) + int(seats["b"]) + int(seats["c"]), 100)
	assert_gt(int(seats["a"]), 45, "prime au premier")
	assert_lt(int(seats["c"]), 20, "le troisième est sous-représenté")


func test_regional_votes_match_the_national_result() -> void:
	var national := {"pty_aaa_1": 45.0, "pty_aaa_2": 40.0, "pty_aaa_3": 15.0}
	var groups_of := {"pty_aaa_1": "left", "pty_aaa_2": "conservative", "pty_aaa_3": "green"}
	var regional := ElectionModel.regional_votes(national, groups_of, PROVINCES, 0.0, _settings)
	var back := ElectionModel.national_votes(regional, PROVINCES)
	for party_id: String in national.keys():
		assert_almost_eq(float(back[party_id]), float(national[party_id]), 0.3, party_id)
	assert_gt(float(regional["1"]["pty_aaa_3"]), float(regional["3"]["pty_aaa_3"]), "les écologistes sont plus forts en ville")
	assert_gt(float(regional["3"]["pty_aaa_2"]), float(regional["1"]["pty_aaa_2"]), "les conservateurs à la campagne")


func test_government_formation() -> void:
	var parties := {"left": [20, 0.0], "green": [15, 1.0], "center": [10, 3.5], "right": [45, 6.0], "far": [10, 8.0]}
	assert_eq(ElectionModel.form_government(parties, 100, ["right", "far"], _settings), ["right", "far"] as Array[String],
		"le gouvernement sortant garde sa majorité")
	var formed := ElectionModel.form_government(parties, 100, ["left"], _settings)
	assert_eq(formed[0], "right", "le premier parti forme le gouvernement")
	assert_true(formed.has("far"), "puis s'allie au plus proche")
	var cordon := parties.duplicate(true)
	cordon["far"] = [10, 8.0, true]
	assert_false(ElectionModel.form_government(cordon, 100, ["left"], _settings).has("far"), "cordon sanitaire")


func test_presidential_two_rounds() -> void:
	var scores := {"a": 35.0, "b": 30.0, "c": 20.0, "d": 15.0}
	var positions := {"a": 0.0, "b": 6.0, "c": 7.0, "d": 1.0}
	var outcome := ElectionModel.presidential(scores, positions, true, _settings)
	assert_eq((outcome["rounds"] as Array).size(), 2)
	assert_eq(outcome["winner"], "b", "la droite rassemble au second tour")
	var single := ElectionModel.presidential(scores, positions, false, _settings)
	assert_eq((single["rounds"] as Array).size(), 1)


func test_legislative_election_changes_government() -> void:
	var state := _world("parliamentary_republic", [30.0, 55.0, 15.0])
	var country := state.get_country("AAA")
	var start_elites := float(country.society.start_satisfaction["elites"])
	ElectionSystem.new().on_month(state)
	var politics := country.politics
	var total := politics.other_seats
	for party: PartyState in politics.parties.values():
		total += party.seats
	assert_eq(total, 100)
	assert_eq(politics.ruling_party(), "pty_aaa_2", "alternance")
	assert_eq(politics.ideology, "conservative")
	assert_eq(politics.head_of_government, "chr_a2")
	assert_gt(float(country.society.start_satisfaction["elites"]), start_elites, "les élites attendent beaucoup de la droite")
	assert_eq(politics.election_year, 2026)
	assert_eq(politics.next_election_year, 2030)
	assert_eq(state.events[0]["type"], ElectionSystem.EVENT_ELECTION)


func test_managed_elections_keep_seats() -> void:
	var state := _world("one_party_state", [30.0, 55.0, 15.0])
	ElectionSystem.new().on_month(state)
	var politics := state.get_country("AAA").politics
	assert_eq(politics.ruling_party(), "pty_aaa_1")
	assert_eq((politics.parties["pty_aaa_1"] as PartyState).seats, 52)
	assert_true(bool(state.events[0]["managed"]))


func test_presidential_election_replaces_head_of_state() -> void:
	var presidency := {"election": {"year": 2021, "month": 3}, "term_years": 5, "two_rounds": true,
		"next_election": {"year": 2026, "month": 3}}
	var state := _world("presidential_republic", [30.0, 55.0, 15.0], {"type": "majoritarian"}, presidency)
	var politics := state.get_country("AAA").politics
	politics.next_election_year = 2028
	ElectionSystem.new().on_month(state)
	assert_eq(politics.head_of_state, "chr_a2")
	assert_eq(politics.ruling_party(), "pty_aaa_2", "le président choisit son gouvernement")
	assert_eq(politics.next_presidential_year, 2031)


func test_early_election() -> void:
	var state := _world("parliamentary_republic", [45.0, 40.0, 15.0])
	var politics := state.get_country("AAA").politics
	politics.next_election_year = 2028
	var command := CallEarlyElectionCommand.new(&"AAA")
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	assert_true(politics.dissolved)
	assert_eq([politics.next_election_year, politics.next_election_month], [2026, 5])
	ElectionSystem.new().on_month(state)
	assert_eq(politics.election_year, 2022, "pas encore")
	state.date.month = 5
	ElectionSystem.new().on_month(state)
	assert_eq(politics.election_month, 5)
	assert_false(politics.dissolved)
	assert_eq(CallEarlyElectionCommand.new(&"AAA").refusal_reason(state), "POLITICS_EARLY_TOO_SOON")
	var presidential := _world("presidential_republic", [45.0, 40.0, 15.0])
	assert_eq(CallEarlyElectionCommand.new(&"AAA").refusal_reason(presidential), "POLITICS_EARLY_NOT_ALLOWED")

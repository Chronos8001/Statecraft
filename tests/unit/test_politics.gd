extends GutTest
## Chambre basse, gouvernement et sondages.

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
	"one_party_state": {"democratic": false, "group_influence": {}, "legitimacy": 50.0}}
const IDEOLOGIES := {"socialist": {"party_group": "left"}, "conservative": {"party_group": "conservative"},
	"green": {"party_group": "green"}}
const PARTIES := {"pty_aaa_1": {"ideology": "socialist"}, "pty_aaa_2": {"ideology": "conservative"},
	"pty_aaa_3": {"ideology": "green"}, "pty_bbb_1": {"ideology": "socialist"}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(regime: String, parliament: Dictionary) -> Dictionary:
	return {"population": 10000000, "currency": "usd", "regime": regime, "ideology": "socialist",
		"economy": {"gdp_billion_usd": 1000.0, "debt_to_gdp": 0.6, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 0.8, "elites": 0.2}, "stability": 60.0, "corruption": 30.0,
			"democracy": 7.5, "approval": 40.0},
		"parliament": parliament}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(), &"AAA")
	var aaa := {"seats": 100, "government": ["pty_aaa_1"], "other_seats": 4, "other_vote": 4.0, "other_poll": 2.0,
		"election": {"year": 2023, "month": 5}, "term_years": 4, "parties": {
			"pty_aaa_1": {"seats": 52, "vote": 45.0, "poll": 40.0},
			"pty_aaa_2": {"seats": 40, "vote": 41.0, "poll": 44.0},
			"pty_aaa_3": {"seats": 4, "vote": 10.0, "poll": 14.0}}}
	var bbb := {"seats": 300, "government": ["pty_bbb_1"], "other_seats": 30, "other_vote": 10.0, "other_poll": 10.0,
		"election": {"year": 2023, "month": 3}, "term_years": 5, "parties": {
			"pty_bbb_1": {"seats": 270, "vote": 90.0, "poll": 90.0}}}
	WorldSetup.populate(state, {"AAA": _country("parliamentary_republic", aaa), "BBB": _country("one_party_state", bbb)},
		CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, _defines["investment"],
		{"groups": GROUPS, "regimes": REGIMES, "ideologies": IDEOLOGIES, "settings": _defines["society"]},
		{"parties": PARTIES, "settings": _defines["politics"]})
	return state


func _months(state: SimState, count: int) -> void:
	for _month: int in count:
		SocietySystem.new().on_month(state)
		PoliticsSystem.new().on_month(state)


func test_setup_reads_parliament() -> void:
	var politics := _world().get_country("AAA").politics
	assert_eq(politics.seats, 100)
	assert_eq(politics.government_seats(), 52)
	assert_true(politics.has_majority())
	assert_true(politics.polls_published)
	assert_false(_world().get_country("BBB").politics.polls_published, "parti unique : sondages non publiés")
	var party: PartyState = politics.parties["pty_aaa_3"]
	assert_eq(party.party_group, "green")
	assert_almost_eq(party.poll, 14.0, 0.001)


func test_start_polls_are_calibrated() -> void:
	var state := _world()
	var politics := state.get_country("AAA").politics
	var values := PoliticsModel.polls(politics, state.get_country("AAA").society, GROUPS, _defines["politics"])
	assert_almost_eq(float(values["pty_aaa_1"]), 40.0, 0.001)
	assert_almost_eq(float(values["pty_aaa_2"]), 44.0, 0.001)
	assert_almost_eq(float(values["pty_aaa_3"]), 14.0, 0.001)


func test_polls_add_up_and_stay_near_start() -> void:
	var state := _world()
	_months(state, 24)
	var politics := state.get_country("AAA").politics
	var total := politics.other_poll
	for party: PartyState in politics.parties.values():
		total += party.poll
		assert_between(party.poll, party.start_poll * 0.6, party.start_poll * 1.4, "bruit limité : %s" % party.id)
	assert_almost_eq(total, 100.0, 0.001)


func test_government_loses_when_its_voters_suffer() -> void:
	var state := _world()
	var reference := _world()
	state.get_country("AAA").economy.unemployment += 6.0
	_months(state, 36)
	_months(reference, 36)
	var hit: PartyState = state.get_country("AAA").politics.parties["pty_aaa_1"]
	var calm: PartyState = reference.get_country("AAA").politics.parties["pty_aaa_1"]
	assert_lt(hit.poll, calm.poll - 3.0, "le chômage coûte des voix au gouvernement")
	var opposition: PartyState = state.get_country("AAA").politics.parties["pty_aaa_2"]
	var calm_opposition: PartyState = reference.get_country("AAA").politics.parties["pty_aaa_2"]
	assert_gt(opposition.poll, calm_opposition.poll, "l'opposition en profite")


func test_polls_are_reproducible() -> void:
	var first := _world()
	var second := _world()
	_months(first, 12)
	_months(second, 12)
	var a: PartyState = first.get_country("AAA").politics.parties["pty_aaa_2"]
	var b: PartyState = second.get_country("AAA").politics.parties["pty_aaa_2"]
	assert_eq(a.poll, b.poll)


func test_seats_do_not_change_between_elections() -> void:
	var state := _world()
	state.get_country("AAA").economy.unemployment += 6.0
	_months(state, 24)
	assert_eq(state.get_country("AAA").politics.government_seats(), 52)

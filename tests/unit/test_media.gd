extends GutTest
## Médias et opinion : presse, réseaux sociaux, propagande, désinformation.

const DEFINES_PATH := "res://data/defines.json"
const LAWS_PATH := "res://data/laws/laws.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const GROUPS := {
	"workers": {"influence": 1.0, "affinity": {"left": 15},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
}
const REGIMES := {"parliamentary_republic": {"democratic": true, "group_influence": {}},
	"one_party_state": {"democratic": false, "group_influence": {}, "legitimacy": 50.0}}
const IDEOLOGIES := {"socialist": {"party_group": "left"}, "conservative": {"party_group": "conservative"}}
const PARTIES := {"pty_aaa_1": {"ideology": "socialist"}, "pty_aaa_2": {"ideology": "conservative"},
	"pty_bbb_1": {"ideology": "socialist"}}

var _defines: Dictionary
var _laws: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_laws = JSON.parse_string(FileAccess.get_file_as_string(LAWS_PATH))


func _country(tag: String, regime: String) -> Dictionary:
	var parties := {"pty_%s_1" % tag.to_lower(): {"seats": 60, "vote": 55.0, "poll": 55.0}}
	if tag == "AAA":
		parties["pty_aaa_2"] = {"seats": 40, "vote": 45.0, "poll": 45.0}
	return {"population": 10000000, "currency": "usd", "regime": regime, "ideology": "socialist",
		"economy": {"gdp_billion_usd": 400.0, "debt_to_gdp": 0.6, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"parliament": {"seats": 100, "government": ["pty_%s_1" % tag.to_lower()], "other_seats": 0, "other_vote": 0.0,
			"other_poll": 0.0, "election": {"year": 2023, "month": 1}, "term_years": 5,
			"system": {"type": "proportional", "threshold": 5.0}, "next_election": {"year": 2030, "month": 1},
			"parties": parties}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(31, GameDate.new(), &"AAA")
	WorldSetup.populate(state, {"AAA": _country("AAA", "parliamentary_republic"), "BBB": _country("BBB", "one_party_state")},
		CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, _defines["investment"],
		{"groups": GROUPS, "regimes": REGIMES, "ideologies": IDEOLOGIES, "settings": _defines["society"]},
		{"parties": PARTIES, "characters": {}, "provinces": {}, "laws": _laws, "constitution": {}, "crises": {},
			"settings": _defines["politics"]})
	return state


func test_press_law_sets_media_factor() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	assert_eq(country.politics.media_factor, 0.8, "presse encadrée au départ")
	ChangeLawCommand.new(&"AAA", "press_freedom", "censored").execute(state)
	MediaSystem.new().on_month(state)
	assert_eq(country.politics.media_factor, 0.4)
	ChangeLawCommand.new(&"AAA", "social_networks", "restricted").execute(state)
	MediaSystem.new().on_month(state)
	assert_lt(country.politics.volatility, 1.0, "des réseaux bridés rendent l'opinion moins volatile")


func test_propaganda() -> void:
	var state := _world()
	var reference := _world()
	var country := state.get_country("AAA")
	var debt := country.economy.local_debt
	var legitimacy := country.society.start_legitimacy
	SetPropagandaCommand.new(&"AAA", 3).execute(state)
	for _month: int in 6:
		for world: SimState in [state, reference]:
			MediaSystem.new().on_month(world)
			SocietySystem.new().on_month(world)
			PoliticsSystem.new().on_month(world)
	assert_gt(country.economy.local_debt, debt, "la propagande coûte")
	assert_gt(float(country.society.satisfaction["workers"]),
		float(reference.get_country("AAA").society.satisfaction["workers"]))
	var ruling: PartyState = country.politics.parties["pty_aaa_1"]
	assert_gt(ruling.poll, (reference.get_country("AAA").politics.parties["pty_aaa_1"] as PartyState).poll)
	assert_lt(country.society.start_legitimacy, legitimacy, "elle use la légitimité d'une démocratie")
	SetPropagandaCommand.new(&"AAA", 0).execute(state)
	MediaSystem.new().on_month(state)
	assert_true(country.media_effects.is_empty())


func test_disinformation() -> void:
	var state := _world()
	var target := state.get_country("BBB")
	var stability := target.society.stability
	var command := DisinformationCommand.new(&"AAA", "BBB", MediaSystem.KIND_DESTABILIZE)
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	assert_lt(target.society.stability, stability)
	assert_lt(float(target.society.bonuses["workers"]), 0.0)
	assert_eq(DisinformationCommand.new(&"AAA", "BBB").refusal_reason(state), "MEDIA_COOLDOWN")
	assert_eq(DisinformationCommand.new(&"BBB", "BBB").refusal_reason(state), "MEDIA_INVALID_TARGET")
	var smear := _world()
	var opposition: PartyState = smear.get_country("AAA").politics.parties["pty_aaa_2"]
	DisinformationCommand.new(&"AAA", "", MediaSystem.KIND_SMEAR).execute(smear)
	assert_lt(opposition.drift, 0.0, "l'opposition recule")
	assert_eq(DisinformationCommand.new(&"BBB", "", MediaSystem.KIND_SMEAR).refusal_reason(smear), "MEDIA_NO_OPPOSITION")

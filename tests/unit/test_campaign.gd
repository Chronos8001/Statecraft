extends GutTest
## Campagne électorale : financement, meetings, promesses et fraude.

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


func _campaign(state: SimState) -> Dictionary:
	return _defines["politics"]["campaign"]


func test_campaign_only_before_an_election() -> void:
	var state := _world("parliamentary_republic", [45.0, 40.0, 15.0])
	assert_eq(CampaignFundCommand.new(&"AAA", 1.0).refusal_reason(state), "")
	state.get_country("AAA").politics.next_election_year = 2028
	assert_eq(CampaignFundCommand.new(&"AAA", 1.0).refusal_reason(state), "CAMPAIGN_NOT_STARTED")


func test_funding_raises_the_ruling_party() -> void:
	var state := _world("parliamentary_republic", [45.0, 40.0, 15.0])
	var reference := _world("parliamentary_republic", [45.0, 40.0, 15.0])
	var country := state.get_country("AAA")
	var debt := country.economy.local_debt
	assert_eq(CampaignFundCommand.new(&"AAA", 100.0).refusal_reason(state), "CAMPAIGN_SPENDING_LIMIT")
	var command := CampaignFundCommand.new(&"AAA", 1.0)
	command.execute(state)
	assert_gt(country.economy.local_debt, debt, "payé par l'emprunt")
	PoliticsSystem.new().on_month(state)
	PoliticsSystem.new().on_month(reference)
	var funded: PartyState = country.politics.parties["pty_aaa_1"]
	var unfunded: PartyState = reference.get_country("AAA").politics.parties["pty_aaa_1"]
	assert_gt(funded.poll, unfunded.poll + 1.0)
	assert_lt(CampaignModel.spending_bonus(0.4, _campaign(state)) - CampaignModel.spending_bonus(0.2, _campaign(state)),
		CampaignModel.spending_bonus(0.2, _campaign(state)), "rendement décroissant")


func test_rallies() -> void:
	var state := _world("parliamentary_republic", [45.0, 40.0, 15.0])
	state.get_country("AAA").politics.next_election_month = 6
	var rally := RallyCommand.new(&"AAA", "2")
	assert_eq(rally.refusal_reason(state), "")
	rally.execute(state)
	assert_eq(RallyCommand.new(&"AAA", "3").refusal_reason(state), "CAMPAIGN_RALLY_THIS_MONTH")
	assert_eq(RallyCommand.new(&"AAA", "99").refusal_reason(state), "CAMPAIGN_NOT_OWN_PROVINCE")
	state.date.month = 4
	assert_eq(RallyCommand.new(&"AAA", "2").refusal_reason(state), "CAMPAIGN_RALLY_DONE")
	var leans := ElectionSystem.rally_leans(state.get_country("AAA").politics, state)
	assert_gt(float(leans["2"]["pty_aaa_1"]), 0.0)


func test_promise_kept_or_broken() -> void:
	var state := _world("parliamentary_republic", [45.0, 40.0, 15.0])
	var country := state.get_country("AAA")
	PromiseCommand.new(&"AAA", "workers").execute(state)
	PromiseCommand.new(&"AAA", "elites").execute(state)
	assert_eq(PromiseCommand.new(&"AAA", "workers").refusal_reason(state), "CAMPAIGN_ALREADY_PROMISED")
	assert_gt(float(country.society.bonuses["workers"]), 0.0)
	ElectionSystem.new().on_month(state)
	assert_false(bool(country.politics.promises[0]["pending"]))
	var start_elites := float(country.society.start_satisfaction["elites"])
	country.economy.budget.effects = {BudgetModel.GROUPS: {"workers": 5.0}}
	state.date.month = 4
	PoliticsSystem.update_promises(country, state, _campaign(state))
	assert_eq(country.politics.promises.size(), 1, "promesse aux ouvriers tenue par le budget")
	assert_almost_eq(float(country.society.bonuses["workers"]), 0.0, 0.001)
	state.date.year = 2028
	PoliticsSystem.update_promises(country, state, _campaign(state))
	assert_true(country.politics.promises.is_empty())
	assert_lt(float(country.society.start_satisfaction["elites"]), start_elites, "promesse aux élites rompue")


func test_fraud() -> void:
	var votes := CampaignModel.rigged_votes({"a": 40.0, "b": 40.0, "c": 20.0}, "a", 6.0)
	assert_almost_eq(float(votes["a"]), 46.0, 0.001)
	assert_almost_eq(float(votes["b"]) + float(votes["c"]), 54.0, 0.001)
	var settings := _campaign(null)
	assert_gt(CampaignModel.detection_chance(3, 9.0, 1.0, settings), CampaignModel.detection_chance(1, 9.0, 1.0, settings))
	assert_gt(CampaignModel.detection_chance(2, 9.0, 1.0, settings), CampaignModel.detection_chance(2, 2.0, 1.0, settings))
	var honest := _world("parliamentary_republic", [40.0, 45.0, 15.0])
	var rigged := _world("parliamentary_republic", [40.0, 45.0, 15.0])
	SetFraudCommand.new(&"AAA", 3).execute(rigged)
	ElectionSystem.new().on_month(honest)
	ElectionSystem.new().on_month(rigged)
	var honest_seats := (honest.get_country("AAA").politics.parties["pty_aaa_1"] as PartyState).seats
	var rigged_seats := (rigged.get_country("AAA").politics.parties["pty_aaa_1"] as PartyState).seats
	assert_gt(rigged_seats, honest_seats + 5)
	assert_eq(rigged.get_country("AAA").politics.fraud_level, 0, "la campagne se termine avec le scrutin")
	assert_eq(SetFraudCommand.new(&"AAA", 1).refusal_reason(_world("one_party_state", [40.0, 45.0, 15.0])),
		"CAMPAIGN_FRAUD_USELESS")

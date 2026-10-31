extends GutTest
## Actions diplomatiques et traités.

const DEFINES_PATH := "res://data/defines.json"
const TREATIES_PATH := "res://data/treaties/treaties.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const START := {
	"treaties": {"list": [["mutual_defense", "AAA", "BBB"]]},
	"no_embassy": {"list": [["AAA", "EEE"]]},
	"recognition": {"DDD": {"parent": "CCC", "recognized_by": ["BBB"]}},
}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(gdp: float, relations: Dictionary) -> Dictionary:
	return {"population": 10000000, "currency": "usd", "relations": relations,
		"economy": {"gdp_billion_usd": gdp, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(4, GameDate.new(), &"AAA")
	WorldSetup.populate(state, {
		"AAA": _country(10000.0, {"BBB": 70, "CCC": 10, "EEE": -60}), "BBB": _country(1000.0, {"AAA": 70}),
		"CCC": _country(10.0, {"AAA": 10}), "DDD": _country(5.0, {}), "EEE": _country(9000.0, {"AAA": -60})},
		CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {}, {}, {},
		{"settings": _defines["diplomacy"], "treaties": JSON.parse_string(FileAccess.get_file_as_string(TREATIES_PATH)),
			"start": START})
	return state


func test_start_situation() -> void:
	var diplomacy := _world().diplomacy
	assert_true(diplomacy.has_treaty("AAA", "BBB", "mutual_defense"))
	assert_eq(diplomacy.relation("AAA", "BBB"), 70.0, "les traités de 2026 sont déjà dans les relations")
	assert_false(diplomacy.has_embassy("AAA", "EEE"))
	assert_true(diplomacy.recognizes("BBB", "DDD"))
	assert_false(diplomacy.recognizes("AAA", "DDD"))
	assert_false(diplomacy.has_embassy("AAA", "DDD"), "pas d'ambassade dans un État non reconnu")


func test_actions() -> void:
	var state := _world()
	var improve := DiplomaticActionCommand.new(&"AAA", "CCC", "improve_relations")
	assert_eq(improve.refusal_reason(state), "")
	improve.execute(state)
	assert_eq(state.diplomacy.relation("AAA", "CCC"), 15.0)
	assert_eq(improve.refusal_reason(state), "DIPLOMACY_COOLDOWN")
	assert_eq(DiplomaticActionCommand.new(&"AAA", "EEE", "state_visit").refusal_reason(state), "DIPLOMACY_NO_EMBASSY")
	DiplomaticActionCommand.new(&"AAA", "EEE", "open_embassy").execute(state)
	assert_true(state.diplomacy.has_embassy("AAA", "EEE"))
	assert_eq(DiplomaticActionCommand.new(&"AAA", "BBB", "recognize").refusal_reason(state), "DIPLOMACY_NOT_DISPUTED")
	DiplomaticActionCommand.new(&"AAA", "DDD", "recognize").execute(state)
	assert_true(state.diplomacy.recognizes("AAA", "DDD"))
	assert_lt(state.diplomacy.relation("AAA", "CCC"), 15.0, "le pays qui revendique le territoire proteste")


func test_treaties() -> void:
	var state := _world()
	var definitions := state.treaty_definitions
	assert_gt(DiplomacyModel.treaty_score(state, "AAA", "BBB", definitions["non_aggression"]), 0.0)
	assert_lt(DiplomacyModel.treaty_score(state, "AAA", "CCC", definitions["mutual_defense"]), 0.0,
		"relations insuffisantes pour une alliance")
	ProposeTreatyCommand.new(&"AAA", "BBB", "intelligence_sharing").execute(state)
	assert_true(state.diplomacy.has_treaty("AAA", "BBB", "intelligence_sharing"))
	assert_eq(state.diplomacy.relation("AAA", "BBB"), 78.0, "un traité signé relève durablement les relations")
	ProposeTreatyCommand.new(&"AAA", "CCC", "mutual_defense").execute(state)
	assert_false(state.diplomacy.has_treaty("AAA", "CCC", "mutual_defense"))
	assert_eq(ProposeTreatyCommand.new(&"AAA", "CCC", "mutual_defense").refusal_reason(state), "DIPLOMACY_COOLDOWN")
	var trust := state.diplomacy.trust("AAA", "BBB")
	var treaty_id := state.diplomacy.treaties_between("AAA", "BBB")[0]
	CancelTreatyCommand.new(&"AAA", treaty_id).execute(state)
	assert_false(state.diplomacy.has_treaty("AAA", "BBB", "mutual_defense"))
	assert_lt(state.diplomacy.trust("AAA", "BBB"), trust - 20.0, "rompre une alliance détruit la confiance")


func test_ultimatum() -> void:
	var state := _world()
	var debt := state.get_country("CCC").economy.local_debt
	DiplomaticActionCommand.new(&"AAA", "CCC", "ultimatum").execute(state)
	assert_true(bool(state.events[-1]["accepted"]), "un pays mille fois plus petit cède")
	assert_gt(state.get_country("CCC").economy.local_debt, debt)
	DiplomaticActionCommand.new(&"AAA", "EEE", "ultimatum").execute(state)
	assert_false(bool(state.events[-1]["accepted"]), "une puissance comparable refuse")
	assert_lt(state.diplomacy.relation("AAA", "EEE"), -80.0)


func test_guarantee_angers_enemies() -> void:
	var state := _world()
	state.diplomacy.change_relation("EEE", "BBB", -60.0)
	DiplomaticActionCommand.new(&"AAA", "BBB", "guarantee").execute(state)
	assert_true(state.diplomacy.guarantees_independence("AAA", "BBB"))
	assert_lt(state.diplomacy.relation("AAA", "EEE"), -60.0)

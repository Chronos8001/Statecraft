extends GutTest
## Sphères d'influence : influence de départ, points, actions, poids dans les décisions.

const DEFINES_PATH := "res://data/defines.json"
const TREATIES_PATH := "res://data/treaties/treaties.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const START := {"treaties": {"list": [["military_access", "BIG", "HOST"]]}, "no_embassy": {"list": []},
	"recognition": {}, "security_council": {"permanent": [], "elected": {}}, "sanctions": {"list": []},
	"aid": {"list": []}}
const PARTIES := {"pty_host_1": {"ideology": "socialist"}, "pty_host_2": {"ideology": "conservative"}}
const IDEOLOGIES := {"socialist": {"party_group": "left"}, "conservative": {"party_group": "conservative"}}
const GROUPS := {"workers": {"influence": 1.0, "affinity": {"left": 10},
	"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(gdp: float, relations: Dictionary, parties: Dictionary = {}) -> Dictionary:
	var country := {"population": 1000000, "currency": "usd", "relations": relations, "regime": "parliamentary_republic",
		"ideology": "socialist",
		"economy": {"gdp_billion_usd": gdp, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"workers": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0}}
	if not parties.is_empty():
		country["parliament"] = {"seats": 100, "government": ["pty_host_1"], "other_seats": 0, "other_vote": 0.0,
			"other_poll": 0.0, "election": {"year": 2023, "month": 1}, "term_years": 5,
			"system": {"type": "proportional", "threshold": 5.0}, "next_election": {"year": 2030, "month": 1},
			"parties": parties}
	return country


func _world() -> SimState:
	var state := SimState.new()
	state.setup(5, GameDate.new(), &"BIG")
	WorldSetup.populate(state, {"BIG": _country(9000.0, {"HOST": 50, "OTHER": 30}),
		"HOST": _country(100.0, {"BIG": 50}, {"pty_host_1": {"seats": 60, "vote": 60.0, "poll": 60.0},
			"pty_host_2": {"seats": 40, "vote": 40.0, "poll": 40.0}}),
		"OTHER": _country(100.0, {"BIG": 30})},
		CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": GROUPS, "regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}},
			"ideologies": IDEOLOGIES, "settings": _defines["society"]},
		{"parties": PARTIES, "characters": {}, "provinces": {}, "laws": {}, "constitution": {}, "crises": {},
			"settings": _defines["politics"]},
		{"settings": _defines["diplomacy"], "treaties": JSON.parse_string(FileAccess.get_file_as_string(TREATIES_PATH)),
			"start": START, "organizations": {}, "organization_rules": {}, "sanctions": {}, "aid": {}})
	return state


func test_start_influence_and_points() -> void:
	var state := _world()
	assert_eq(InfluenceSystem.influence(state, "BIG", "HOST"), 15.0, "base militaire de 2026")
	assert_eq(InfluenceSystem.influence(state, "BIG", "OTHER"), 0.0)
	assert_true(state.diplomacy.bases.has("BIG>HOST"))
	var points := float(state.diplomacy.influence_points["BIG"])
	assert_gt(points, float(state.diplomacy.influence_points["HOST"]), "les grandes économies ont plus d'influence")
	InfluenceSystem.new().on_month(state)
	assert_gt(float(state.diplomacy.influence_points["BIG"]), points)


func test_actions() -> void:
	var state := _world()
	state.diplomacy.influence_points["BIG"] = 200.0
	var party: PartyState = state.get_country("HOST").politics.parties["pty_host_2"]
	var support := InfluenceCommand.new(&"BIG", "HOST", "support_party", "pty_host_2")
	assert_eq(support.refusal_reason(state), "")
	support.execute(state)
	assert_gt(party.drift, 0.0, "le parti soutenu progresse")
	assert_almost_eq(float(state.diplomacy.influence_points["BIG"]), 180.0, 0.001)
	assert_gt(InfluenceSystem.influence(state, "BIG", "HOST"), 15.0)
	assert_eq(support.refusal_reason(state), "DIPLOMACY_COOLDOWN")
	assert_eq(InfluenceCommand.new(&"BIG", "HOST", "open_base").refusal_reason(state), "DIPLOMACY_ALREADY")
	var open := InfluenceCommand.new(&"BIG", "OTHER", "open_base")
	assert_eq(open.refusal_reason(state), "INFLUENCE_BASE_REFUSED", "relations insuffisantes sans traité")
	state.diplomacy.change_relation("BIG", "OTHER", 10.0)
	open.execute(state)
	assert_eq(InfluenceSystem.influence(state, "BIG", "OTHER"), 15.0)
	state.diplomacy.influence_points["BIG"] = 0.0
	assert_eq(InfluenceCommand.new(&"BIG", "HOST", "soft_power").refusal_reason(state), "INFLUENCE_NOT_ENOUGH")


func test_influence_eases_treaties() -> void:
	var state := _world()
	var definition: Dictionary = state.treaty_definitions["non_aggression"]
	var before := DiplomacyModel.treaty_score(state, "BIG", "OTHER", definition)
	state.diplomacy.influence_changes["BIG>OTHER"] = 40.0
	assert_almost_eq(DiplomacyModel.treaty_score(state, "BIG", "OTHER", definition), before + 0.3 * 40.0, 0.001)

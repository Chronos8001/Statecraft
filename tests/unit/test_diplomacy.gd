extends GutTest
## Relations bilatérales, confiance et opinion publique étrangère.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(relations: Dictionary) -> Dictionary:
	return {"population": 1000000, "currency": "usd", "relations": relations,
		"economy": {"gdp_billion_usd": 10.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(2, GameDate.new(), &"AAA")
	WorldSetup.populate(state, {"AAA": _country({"BBB": 60, "CCC": -80}), "BBB": _country({"AAA": 60}),
		"CCC": _country({"AAA": -80})}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {}, {}, {},
		_defines["diplomacy"])
	return state


func test_start_relations_are_symmetric() -> void:
	var diplomacy := _world().diplomacy
	assert_eq(diplomacy.relation("AAA", "BBB"), 60.0)
	assert_eq(diplomacy.relation("BBB", "AAA"), 60.0)
	assert_eq(diplomacy.relation("BBB", "CCC"), 0.0, "paire absente : neutre")
	assert_almost_eq(diplomacy.trust("AAA", "BBB"), 50.0 + 0.4 * 60.0, 0.001)
	assert_almost_eq(diplomacy.trust("AAA", "CCC"), 50.0 - 0.4 * 80.0, 0.001)
	assert_between(diplomacy.opinion("CCC", "AAA"), -90.0, -70.0, "l'opinion part des relations, à quelques points près")


func test_changes_are_bounded_and_fade() -> void:
	var state := _world()
	var diplomacy := state.diplomacy
	diplomacy.change_relation("AAA", "BBB", 60.0)
	assert_eq(diplomacy.relation("AAA", "BBB"), 100.0, "plafonné à +100")
	var opinion := diplomacy.opinion("BBB", "AAA")
	DiplomacySystem.new().on_month(state)
	assert_lt(diplomacy.relation("AAA", "BBB"), 100.0, "retour progressif vers le niveau naturel")
	assert_gt(diplomacy.opinion("BBB", "AAA"), opinion, "l'opinion suit les relations avec retard")
	for _month: int in 600:
		DiplomacySystem.new().on_month(state)
	assert_almost_eq(diplomacy.relation("AAA", "BBB"), 60.0, 0.1)
	assert_true(diplomacy.relation_changes.is_empty(), "les écarts disparus ne sont plus stockés")
	assert_true(diplomacy.opinion_changes.is_empty())


func test_trust_recovers_slowly() -> void:
	var state := _world()
	state.diplomacy.change_trust("AAA", "CCC", -15.0)
	assert_eq(state.diplomacy.trust("AAA", "CCC"), 3.0)
	for _month: int in 12:
		DiplomacySystem.new().on_month(state)
	assert_between(state.diplomacy.trust("AAA", "CCC"), 3.5, 8.0)

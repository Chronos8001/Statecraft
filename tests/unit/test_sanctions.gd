extends GutTest
## Sanctions : effets, situation de 2026 neutre, levée, sanctions de l'ONU.

const DEFINES_PATH := "res://data/defines.json"
const MEASURES_PATH := "res://data/sanctions/measures.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const ORGANIZATIONS := {"un": {"name": "UN", "abbreviation": "UN", "kind": "global", "color": "#5B92E5"},
	"eu": {"name": "EU", "abbreviation": "EU", "kind": "economic_union", "color": "#003399"}}
const START := {"treaties": {"list": []}, "no_embassy": {"list": []}, "recognition": {},
	"security_council": {"permanent": ["USA", "AAA"], "elected": {"CCC": 2027}},
	"sanctions": {"list": [[["USA", "@eu"], "RRR", ["sectoral"]]]}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(organizations: Array, relations: Dictionary) -> Dictionary:
	return {"population": 1000000, "currency": "usd", "organizations": organizations, "relations": relations,
		"economy": {"gdp_billion_usd": 100.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(), &"USA")
	WorldSetup.populate(state, {
		"USA": _country(["un"], {"AAA": 50, "CCC": 50, "RRR": -60}), "AAA": _country(["un", "eu"], {"USA": 50, "RRR": -40}),
		"CCC": _country(["un", "eu"], {"USA": 50, "RRR": -40}), "RRR": _country(["un"], {"USA": -60}),
		"BBB": _country(["un"], {})},
		CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {}, {}, {},
		{"settings": _defines["diplomacy"], "treaties": {}, "start": START, "organizations": ORGANIZATIONS,
			"organization_rules": {}, "sanctions": JSON.parse_string(FileAccess.get_file_as_string(MEASURES_PATH))})
	return state


func test_start_sanctions_are_neutral() -> void:
	var state := _world()
	assert_eq(SanctionSystem.sanctioners_of(state, "RRR"), ["USA", "AAA", "CCC"] as Array[String], "@eu développé")
	assert_eq(state.get_country("RRR").economy.sanction_growth, 0.0, "déjà comprises dans la situation de 2026")
	SanctionCommand.new(&"USA", "RRR", "sectoral", false).execute(state)
	assert_gt(state.get_country("RRR").economy.sanction_growth, 0.0, "la levée soulage la cible")


func test_new_sanctions_hurt_the_target() -> void:
	var state := _world()
	var command := SanctionCommand.new(&"USA", "BBB", "total")
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	var expected := SanctionSystem.saturate(-12.0 * 0.3, 8.0)
	assert_almost_eq(state.get_country("BBB").economy.sanction_growth, expected, 0.001, "exposition financière au dollar")
	assert_gt(state.get_country("BBB").economy.sanction_inflation, 0.0)
	assert_lt(state.diplomacy.relation("USA", "BBB"), -30.0)
	assert_eq(command.refusal_reason(state), "DIPLOMACY_ALREADY")


func test_un_sanctions() -> void:
	var state := _world()
	var command := OrganizationCommand.new(&"USA", OrganizationCommand.RESOLUTION, "un", "BBB",
		OrganizationSystem.GENERAL_ASSEMBLY, OrganizationSystem.RESOLUTION_SANCTIONS)
	assert_eq(command.refusal_reason(state), "ORGANIZATION_SANCTIONS_COUNCIL")
	state.diplomacy_settings = state.diplomacy_settings.duplicate(true)
	state.diplomacy_settings["organizations"]["resolution"]["council_majority"] = 2
	state.diplomacy.change_relation("AAA", "BBB", -50.0)
	state.diplomacy.change_relation("CCC", "BBB", -50.0)
	var result := OrganizationSystem.vote_resolution(state, OrganizationSystem.SECURITY_COUNCIL, "USA", "BBB",
		OrganizationSystem.RESOLUTION_SANCTIONS)
	assert_true(bool(result["passed"]))
	assert_true(SanctionSystem.has_measure(state, "RRR", "BBB", "sectoral"), "tous les membres de l'ONU appliquent")
	assert_lt(state.get_country("BBB").economy.sanction_growth, 0.0)

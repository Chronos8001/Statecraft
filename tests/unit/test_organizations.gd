extends GutTest
## Organisations internationales et ONU.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const ORGANIZATIONS := {
	"un": {"name": "UN", "abbreviation": "UN", "kind": "global", "color": "#5B92E5"},
	"pact": {"name": "Pact", "abbreviation": "PCT", "kind": "military_alliance", "color": "#2F5DA8"},
}
const RULES := {
	"un": {"decision": "majority", "eligible": "any", "relation_bonus": 0},
	"pact": {"decision": "unanimity", "eligible": ["AAA", "BBB", "CCC", "DDD"], "relation_bonus": 35, "vote_base": -25},
}
const START := {"treaties": {"list": []}, "no_embassy": {"list": []}, "recognition": {},
	"security_council": {"permanent": ["AAA", "EEE"], "elected": {"BBB": 2026, "CCC": 2027}}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(organizations: Array, relations: Dictionary) -> Dictionary:
	return {"population": 1000000, "currency": "usd", "organizations": organizations, "relations": relations,
		"economy": {"gdp_billion_usd": 100.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(7, GameDate.new(), &"AAA")
	state.date.year = 2026
	WorldSetup.populate(state, {
		"AAA": _country(["un", "pact"], {"BBB": 80, "CCC": 60, "DDD": 50, "EEE": -60, "FFF": 0}),
		"BBB": _country(["un", "pact"], {"AAA": 80, "CCC": 50, "DDD": -20, "EEE": 0}),
		"CCC": _country(["un"], {"AAA": 60, "BBB": 50, "EEE": -40}),
		"DDD": _country(["un"], {"AAA": 50, "BBB": -20}),
		"EEE": _country(["un"], {"AAA": -60, "CCC": -40}),
		"FFF": _country(["un"], {})},
		CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {}, {}, {},
		{"settings": _defines["diplomacy"], "treaties": {}, "start": START, "organizations": ORGANIZATIONS,
			"organization_rules": RULES})
	return state


func test_start_memberships_and_council() -> void:
	var state := _world()
	assert_eq(OrganizationSystem.members(state, "pact"), ["AAA", "BBB"])
	assert_eq(OrganizationSystem.organizations_of(state, "CCC"), ["un"] as Array[String])
	assert_eq(state.diplomacy.security_council.size(), 4)


func test_join_by_unanimity() -> void:
	var state := _world()
	var welcome := OrganizationSystem.expected_join(state, "pact", "CCC")
	assert_true(bool(welcome["passed"]), "les deux membres apprécient le candidat")
	var command := OrganizationCommand.new(&"CCC", OrganizationCommand.JOIN, "pact")
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	assert_true(OrganizationSystem.is_member(state, "pact", "CCC"))
	assert_eq(state.diplomacy.relation("AAA", "CCC"), 95.0, "membres d'une même alliance")
	assert_false(bool(OrganizationSystem.expected_join(state, "pact", "DDD")["passed"]), "un membre s'y oppose")
	assert_eq(OrganizationCommand.new(&"EEE", OrganizationCommand.JOIN, "pact").refusal_reason(state),
		"ORGANIZATION_NOT_ELIGIBLE")


func test_leave_and_expel() -> void:
	var state := _world()
	OrganizationCommand.new(&"BBB", OrganizationCommand.LEAVE, "pact").execute(state)
	assert_false(OrganizationSystem.is_member(state, "pact", "BBB"))
	assert_lt(state.diplomacy.relation("AAA", "BBB"), 80.0)
	var un_vote := OrganizationSystem.expected_expulsion(state, "un", "EEE")
	assert_false(bool(un_vote["passed"]), "les deux tiers ne sont pas réunis")


func test_create_and_invite() -> void:
	var state := _world()
	assert_eq(OrganizationCommand.new(&"AAA", OrganizationCommand.CREATE, "", "", " ", "regional").refusal_reason(state),
		"ORGANIZATION_INVALID_NAME")
	OrganizationCommand.new(&"AAA", OrganizationCommand.CREATE, "", "", "Northern Forum", "regional").execute(state)
	var org_id := "custom_0"
	assert_eq(OrganizationSystem.members(state, org_id), ["AAA"])
	assert_eq(state.diplomacy.organizations[org_id]["abbreviation"], "NF")
	assert_eq(OrganizationCommand.new(&"CCC", OrganizationCommand.JOIN, org_id).refusal_reason(state),
		"ORGANIZATION_INVITATION_ONLY")
	assert_true(OrganizationSystem.invite(state, org_id, "AAA", "CCC"))
	assert_false(OrganizationSystem.invite(state, org_id, "AAA", "EEE"), "un pays hostile refuse")


func test_resolutions_and_veto() -> void:
	var state := _world()
	var assembly := OrganizationSystem.expected_resolution(state, OrganizationSystem.GENERAL_ASSEMBLY, "AAA", "EEE")
	assert_true(bool(assembly["passed"]))
	var council := OrganizationSystem.expected_resolution(state, OrganizationSystem.SECURITY_COUNCIL, "AAA", "EEE")
	assert_true(bool(council["vetoed"]), "le membre permanent visé oppose son veto")
	assert_false(bool(council["passed"]))
	var legitimacy := state.get_country("EEE").society.start_legitimacy
	OrganizationCommand.new(&"AAA", OrganizationCommand.RESOLUTION, "un", "EEE",
		OrganizationSystem.GENERAL_ASSEMBLY).execute(state)
	assert_lt(state.diplomacy.relation("BBB", "EEE"), 0.0, "les pays qui condamnent prennent leurs distances")
	assert_eq(OrganizationCommand.new(&"AAA", OrganizationCommand.RESOLUTION, "un", "EEE",
		OrganizationSystem.GENERAL_ASSEMBLY).refusal_reason(state), "DIPLOMACY_COOLDOWN")
	assert_eq(OrganizationCommand.new(&"DDD", OrganizationCommand.RESOLUTION, "un", "EEE",
		OrganizationSystem.SECURITY_COUNCIL).refusal_reason(state), "ORGANIZATION_NOT_IN_COUNCIL")
	assert_almost_eq(state.get_country("EEE").society.start_legitimacy, legitimacy - 2.0, 0.001,
		"une condamnation de l'Assemblée générale coûte de la légitimité")


func test_council_renewal() -> void:
	var state := _world()
	state.date.year = 2027
	state.date.month = 1
	OrganizationSystem.new().on_month(state)
	var council := state.diplomacy.security_council
	assert_false(council.has("BBB"), "mandat terminé")
	assert_true(council.has("CCC"))
	assert_eq(council.size(), 5, "2 permanents, CCC et les 2 seuls candidats possibles (DDD, FFF)")

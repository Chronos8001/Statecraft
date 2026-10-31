extends GutTest
## Aide internationale : versements, prêts, armes, effets, programmes de 2026.

const DEFINES_PATH := "res://data/defines.json"
const AID_PATH := "res://data/aid/aid_kinds.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const START := {"treaties": {"list": []}, "no_embassy": {"list": []}, "recognition": {},
	"security_council": {"permanent": [], "elected": {}}, "sanctions": {"list": []},
	"aid": {"list": [["DON", "POR", "economic", 12.0, 24]]}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(gdp: float, relations: Dictionary) -> Dictionary:
	return {"population": 1000000, "currency": "usd", "relations": relations,
		"economy": {"gdp_billion_usd": gdp, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(3, GameDate.new(), &"DON")
	WorldSetup.populate(state, {"DON": _country(2000.0, {"POR": 40, "ENE": -50}), "POR": _country(100.0, {"DON": 40}),
		"ENE": _country(100.0, {"DON": -50})}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {}, {}, {},
		{"settings": _defines["diplomacy"], "treaties": {}, "start": START, "organizations": {}, "organization_rules": {},
			"sanctions": {}, "aid": JSON.parse_string(FileAccess.get_file_as_string(AID_PATH))})
	return state


func _debt(state: SimState, tag: String) -> float:
	return state.get_country(tag).economy.local_debt


func test_start_programs_pay_without_effect() -> void:
	var state := _world()
	var donor_debt := _debt(state, "DON")
	var recipient_debt := _debt(state, "POR")
	AidSystem.new().on_month(state)
	assert_almost_eq(_debt(state, "DON") - donor_debt, 1.0, 0.001, "12 Md$ par an : 1 par mois")
	assert_almost_eq(recipient_debt - _debt(state, "POR"), 1.0, 0.001)
	assert_eq(state.get_country("POR").economy.aid_growth, 0.0, "déjà compris dans la situation de 2026")


func test_new_economic_aid() -> void:
	var state := _world()
	var relation := state.diplomacy.relation("DON", "POR")
	AidCommand.new(&"DON", "POR", "economic", 2.0, 12).execute(state)
	assert_eq(state.events[-1]["type"], AidSystem.EVENT_AID)
	assert_almost_eq(state.get_country("POR").economy.aid_growth, 0.3 * 2.0, 0.001, "2 % du PIB × 0,3")
	assert_almost_eq(state.diplomacy.relation("DON", "POR"), relation + 20.0, 0.001, "plafond de +20")
	for _month: int in 12:
		AidSystem.new().on_month(state)
	assert_eq(state.get_country("POR").economy.aid_growth, 0.0, "le programme est terminé")


func test_refusal_and_humanitarian() -> void:
	var state := _world()
	AidCommand.new(&"DON", "ENE", "economic", 1.0, 1).execute(state)
	assert_eq(state.events[-1]["type"], AidSystem.EVENT_AID_REFUSED)
	AidCommand.new(&"DON", "ENE", "humanitarian", 1.0, 1).execute(state)
	assert_eq(state.events[-1]["type"], AidSystem.EVENT_AID, "l'aide humanitaire passe malgré l'hostilité")
	assert_eq(AidCommand.new(&"DON", "ENE", "economic", 1.0, 7).refusal_reason(state), "AID_INVALID_AMOUNT")


func test_loan_is_repaid_with_interest() -> void:
	var state := _world()
	var donor_debt := _debt(state, "DON")
	AidCommand.new(&"DON", "POR", "loan", 10.0, 1).execute(state)
	for _month: int in 70:
		AidSystem.new().on_month(state)
	# Le donateur paie aussi son programme de 2026 (24 Md$) ; le prêt lui rapporte des intérêts.
	assert_lt(_debt(state, "DON") - donor_debt - 24.0, 0.0, "le prêteur récupère plus qu'il n'a prêté")
	assert_true(AidSystem.programs_between(state, "DON", "POR").all(func(program: Dictionary) -> bool:
		return program["kind"] != "loan"), "prêt remboursé")


func test_arms_sale_and_gift() -> void:
	var state := _world()
	var buyer_debt := _debt(state, "POR")
	AidCommand.new(&"DON", "POR", "arms_sale", 1.2, 1).execute(state)
	AidSystem.new().on_month(state)
	assert_almost_eq(_debt(state, "POR") - buyer_debt, 1.2 - 1.0, 0.001, "l'acheteur paie (moins le programme de 2026)")
	assert_almost_eq(float(state.diplomacy.arms_received["POR"]), 1.2, 0.001)

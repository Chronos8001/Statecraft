extends GutTest
## Entreprises publiques, investissements étrangers et fonds souverains.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(fund: float) -> Dictionary:
	var investment := {"public_ownership": {"energy": 0.2, "industry": 0.1}, "fdi_inflow": 2.0, "fdi_policy": "open"}
	if fund > 0.0:
		investment["sovereign_fund"] = fund
	return {"population": 10000000, "currency": "usd", "investment": investment,
		"economy": {"gdp_billion_usd": 1000.0, "debt_to_gdp": 0.6, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0,
			"sectors": {"energy": 0.2, "industry": 0.3, "services": 0.5}}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(6, GameDate.new(), &"AAA")
	WorldSetup.populate(state, {"AAA": _country(0.0), "BBB": _country(600.0)}, CURRENCIES, _defines["economy"], {}, {}, {},
		{}, {}, _defines["investment"])
	return state


func _debt(state: SimState, tag: String) -> float:
	var economy := state.get_country(tag).economy
	return economy.total_debt(state.get_currency(economy.currency))


func test_start_is_neutral() -> void:
	var state := _world()
	InvestmentSystem.new().on_month(state)
	var economy := state.get_country("AAA").economy
	assert_almost_eq(economy.investment.fdi_inflow, 2.0, 0.0001)
	assert_eq(economy.investment_growth, 0.0)
	assert_eq(economy.public_revenue, 0.0)
	assert_eq(economy.investment.public_ownership["services"], 0.0, "secteur absent des données : privé")


func test_compensated_nationalization() -> void:
	var state := _world()
	var debt := _debt(state, "AAA")
	var command := SetOwnershipCommand.new(&"AAA", "energy", 1.0, true)
	assert_true(command.can_execute(state))
	assert_false(SetOwnershipCommand.new(&"AAA", "energy", 0.2).can_execute(state), "déjà à ce niveau")
	assert_false(SetOwnershipCommand.new(&"AAA", "unknown", 0.5).can_execute(state))
	command.execute(state)
	var economy := state.get_country("AAA").economy
	var expected := 0.8 * 0.2 * 1000.0 * float(_defines["investment"]["valuation_multiple"])
	assert_almost_eq(_debt(state, "AAA") - debt, expected, 0.5, "rachat financé par la dette")
	assert_gt(economy.public_revenue, 0.0, "bénéfices pour l'État")
	assert_lt(economy.investment_growth, 0.0, "moins d'efficacité")
	assert_eq(state.events.back()["type"], InvestmentSystem.EVENT_NATIONALIZED)


func test_expropriation() -> void:
	var state := _world()
	var economy := state.get_country("AAA").economy
	var rating := economy.rating
	var debt := _debt(state, "AAA")
	SetOwnershipCommand.new(&"AAA", "energy", 1.0, false).execute(state)
	assert_almost_eq(_debt(state, "AAA"), debt, 0.001, "rien à payer")
	assert_eq(economy.rating, rating - int(_defines["investment"]["expropriation"]["rating_notches"]))
	for month: int in 12:
		InvestmentSystem.new().on_month(state)
	assert_lt(economy.investment.fdi_inflow, 2.0, "les investisseurs fuient")
	assert_eq(state.events.back()["type"], InvestmentSystem.EVENT_EXPROPRIATED)


func test_privatization_reduces_debt() -> void:
	var state := _world()
	var debt := _debt(state, "AAA")
	SetOwnershipCommand.new(&"AAA", "energy", 0.0).execute(state)
	assert_lt(_debt(state, "AAA"), debt)
	assert_gt(state.get_country("AAA").economy.investment_growth, 0.0, "gain d'efficacité")


func test_fdi_policy_and_attractiveness() -> void:
	var state := _world()
	var command := SetFdiPolicyCommand.new(&"AAA", InvestmentState.RESTRICTED)
	assert_true(command.can_execute(state))
	assert_false(SetFdiPolicyCommand.new(&"AAA", "unknown").can_execute(state))
	command.execute(state)
	for month: int in 24:
		InvestmentSystem.new().on_month(state)
	var economy := state.get_country("AAA").economy
	assert_lt(economy.investment.fdi_inflow, 2.0)
	assert_lt(economy.investment_growth, 0.0)
	var investment := InvestmentState.new()
	investment.start_fdi_inflow = 2.0
	investment.start_growth = 2.0
	var settings: Dictionary = _defines["investment"]
	assert_gt(InvestmentModel.fdi_target(investment, 5.0, 0, 0.0, settings), 2.0, "croissance plus forte")
	assert_lt(InvestmentModel.fdi_target(investment, 2.0, 0, 10.0, settings), 2.0, "impôt plus lourd")


func test_sovereign_fund() -> void:
	var state := _world()
	var economy := state.get_country("BBB").economy
	var currency := state.get_currency("usd")
	assert_lt(economy.rating_debt_ratio(currency), economy.debt_ratio(currency), "dette nette du fonds")
	InvestmentSystem.new().on_month(state)
	assert_gt(economy.investment.sovereign_fund, 600.0, "rendement")
	var fund := economy.investment.sovereign_fund
	var debt := _debt(state, "BBB")
	assert_false(FundTransferCommand.new(&"BBB", -10000.0).can_execute(state), "plus que le fonds")
	FundTransferCommand.new(&"BBB", -100.0).execute(state)
	assert_almost_eq(economy.investment.sovereign_fund, fund - 100.0, 0.001)
	assert_almost_eq(_debt(state, "BBB"), debt - 100.0, 0.001, "retrait qui rembourse la dette")
	FundTransferCommand.new(&"AAA", 50.0).execute(state)
	assert_almost_eq(state.get_country("AAA").economy.investment.sovereign_fund, 50.0, 0.001)

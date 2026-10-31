extends GutTest
## Marché mondial des ressources : formules, prix d'équilibre, détroits, effets sur les pays.

const DEFINES_PATH := "res://data/defines.json"
const SETTINGS := {"price_bounds": [0.1, 20.0], "price_adjustment": 1.0, "solver_iterations": 50,
	"terms_of_trade_effect": 0.3, "cost_passthrough": 0.3, "supply_chain_penalty": 20.0, "max_economic_effect": 4.0}
const OIL := {"base_price": 60.0, "unit_value": 20.0, "price_unit_key": "UNIT_PRICE_OIL",
	"quantity_unit_key": "UNIT_QUANTITY_OIL", "demand_elasticity": 0.1, "supply_elasticity": 0.1,
	"income_elasticity": 0.0, "demand_trend": 0.0, "supply_trend": 0.0}
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}


func _market() -> MarketState:
	var market := MarketState.new()
	market.base_price = 60.0
	market.price = 60.0
	market.demand_elasticity = 0.1
	market.supply_elasticity = 0.1
	return market


func _country(production: float, consumption: float, sectors: Dictionary = {"industry": 1.0}) -> Dictionary:
	return {"population": 10000000, "currency": "usd", "resources": {"oil": {"production": production,
		"consumption": consumption}}, "water": {"renewable": 10.0, "withdrawal_ratio": 0.2},
		"economy": {"gdp_billion_usd": 1000.0, "debt_to_gdp": 0.5, "growth": 0.0, "inflation": 2.0, "unemployment": 5.0,
		"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": sectors}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(5, GameDate.new())
	var economy_settings: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH)) as Dictionary)["economy"]
	WorldSetup.populate(state, {"EXP": _country(10.0, 0.0, {"energy": 1.0}), "IMP": _country(0.0, 10.0)}, CURRENCIES,
		economy_settings, {}, {"oil": {"market": OIL}}, {
			"straits": {"strait_a": {"trade": {"oil": {"EXP": 1.0}}}},
			"sectors": {"industry": {"inputs": {"oil": 0.5}}, "energy": {"inputs": {}}},
			"settings": SETTINGS})
	return state


func test_supply_and_demand_respond_to_price() -> void:
	assert_almost_eq(ResourceModel.supply(10.0, 2.0, 0.1), 10.0 * pow(2.0, 0.1), 0.0001)
	assert_almost_eq(ResourceModel.demand(10.0, 2.0, 0.1), 10.0 * pow(2.0, -0.1), 0.0001)
	assert_eq(ResourceModel.shortage(0.5, 0.1), 0.0, "pas de pénurie quand le prix baisse")
	assert_almost_eq(ResourceModel.shortage(2.0, 0.1), 1.0 - pow(2.0, -0.1), 0.0001)


func test_equilibrium_of_balanced_market_is_base_price() -> void:
	var entries := [{"capacity": 10.0, "needs": 0.0, "blocked": 0.0}, {"capacity": 0.0, "needs": 10.0, "blocked": 0.0}]
	assert_almost_eq(ResourceModel.equilibrium_ratio(entries, _market(), [0.1, 20.0], 50), 1.0, 0.001)


func test_supply_cut_raises_price() -> void:
	var entries := [{"capacity": 10.0, "needs": 0.0, "blocked": 0.2}, {"capacity": 0.0, "needs": 10.0, "blocked": 0.0}]
	var ratio := ResourceModel.equilibrium_ratio(entries, _market(), [0.1, 20.0], 50)
	assert_almost_eq(ratio, pow(1.0 / 0.8, 1.0 / 0.2), 0.01, "offre -20 %, élasticités 0,1 + 0,1")


func test_start_is_neutral() -> void:
	var state := _world()
	ResourceSystem.new().on_month(state)
	assert_almost_eq(state.markets["oil"].price, 60.0, 0.01)
	for tag: String in ["EXP", "IMP"]:
		assert_almost_eq(state.get_country(tag).economy.resource_growth, 0.0, 0.001, tag)
		assert_almost_eq(state.get_country(tag).economy.resource_inflation, 0.0, 0.001, tag)


func test_closed_strait_blocks_exports_and_raises_price() -> void:
	var state := _world()
	var command := SetStraitClosedCommand.new("strait_a", true)
	assert_true(command.can_execute(state))
	command.execute(state)
	assert_false(SetStraitClosedCommand.new("strait_a", true).can_execute(state), "déjà fermé")
	assert_false(SetStraitClosedCommand.new("unknown", true).can_execute(state))
	ResourceSystem.new().on_month(state)
	var market: MarketState = state.markets["oil"]
	assert_gt(market.price, 60.0 * 5.0, "flambée")
	var exporter := state.get_country("EXP")
	var importer := state.get_country("IMP")
	assert_lt(exporter.economy.resource_growth, 0.0, "l'exportateur ne peut plus vendre")
	assert_lt(importer.economy.resource_growth, 0.0, "pénurie dans l'industrie")
	assert_gt(importer.economy.resource_inflation, 0.0, "prix plus élevés")
	assert_gt(float(importer.resources.shortage["oil"]), 0.0)
	assert_eq(state.events.back()["type"], ResourceSystem.EVENT_STRAIT_CLOSED)


func test_price_boom_helps_unblocked_exporter() -> void:
	var state := _world()
	state.markets["oil"].price = 120.0
	ResourceSystem.apply_effects(state.get_country("EXP"), state, SETTINGS)
	assert_gt(state.get_country("EXP").economy.resource_growth, 0.0)
	assert_almost_eq(state.get_country("EXP").economy.resource_price_index, 2.0, 0.001, "taxes sur les ressources")


func test_reopening_brings_price_back() -> void:
	var state := _world()
	SetStraitClosedCommand.new("strait_a", true).execute(state)
	var system := ResourceSystem.new()
	system.on_month(state)
	SetStraitClosedCommand.new("strait_a", false).execute(state)
	system.on_month(state)
	assert_almost_eq(state.markets["oil"].price, 60.0, 0.5)

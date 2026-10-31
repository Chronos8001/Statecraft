extends GutTest
## Commerce : droits de douane effectifs, surtaxes, embargos, accords, effets et commandes.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const BUDGET := {"taxes": {"customs": {"rate": 5.0, "revenue": 0.5}}, "spending": {"administration": 10.0}}
const AGREEMENTS := {"fta": {"kind": "free_trade", "members": ["AAA", "BBB"]}}
const OIL := {"market": {"base_price": 60.0, "unit_value": 20.0, "price_unit_key": "UNIT_PRICE_OIL",
	"quantity_unit_key": "UNIT_QUANTITY_OIL", "demand_elasticity": 0.1, "supply_elasticity": 0.1,
	"income_elasticity": 0.0, "demand_trend": 0.0, "supply_trend": 0.0}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(partners: Dictionary, oil_production: float, oil_consumption: float, surcharges: Dictionary = {}) -> Dictionary:
	return {"population": 10000000, "currency": "usd", "budget": BUDGET,
		"trade": {"exports": 20.0, "imports": 20.0, "partners": partners, "surcharges": surcharges},
		"resources": {"oil": {"production": oil_production, "consumption": oil_consumption}},
		"water": {"renewable": 10.0, "withdrawal_ratio": 0.1},
		"economy": {"gdp_billion_usd": 1000.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"industry": 1.0}}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new())
	var countries := {
		"AAA": _country({"BBB": 100.0, "CCC": 50.0}, 0.0, 10.0),
		"BBB": _country({"AAA": 100.0}, 5.0, 0.0),
		"CCC": _country({"AAA": 80.0}, 5.0, 0.0, {"AAA": 20.0}),
	}
	var budget_definitions := {"taxes": {"customs": {"name_key": "TAX_CUSTOMS", "unit": "percent", "min": 0, "max": 100,
		"elasticity": 1.0, "default_revenue_per_point": 0.1, "effects": {}}},
		"spending": {"administration": {"name_key": "SPENDING_ADMINISTRATION", "max": 40, "effects": {}}},
		"settings": _defines["budget"]}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], budget_definitions, {"oil": OIL},
		{"straits": {}, "sectors": {"industry": {"inputs": {"oil": 0.5}}}, "settings": _defines["resources"]},
		{"agreements": AGREEMENTS, "settings": _defines["trade"]})
	return state


func test_effective_tariffs() -> void:
	var state := _world()
	var trade := state.trade
	var settings := state.trade_settings
	assert_eq(TradeModel.tariff(trade, "BBB", "AAA", 5.0, settings), 0.0, "libre-échange")
	assert_eq(TradeModel.tariff(trade, "CCC", "AAA", 5.0, settings), 5.0, "droit habituel")
	assert_eq(TradeModel.tariff(trade, "AAA", "CCC", 5.0, settings), 25.0, "surtaxe de départ")
	trade.surcharges["AAA"] = {"default": 10.0}
	assert_eq(TradeModel.tariff(trade, "CCC", "AAA", 5.0, settings), 15.0, "surtaxe sur tous")


func test_start_is_neutral() -> void:
	var state := _world()
	TradeSystem.update_trade(state)
	assert_true(state.trade.tariff_changes.is_empty())
	for tag: String in ["AAA", "BBB", "CCC"]:
		assert_eq(state.get_country(tag).economy.trade_growth, 0.0, tag)
		assert_eq(state.get_country(tag).economy.trade_inflation, 0.0, tag)


func test_tariff_raises_prices_and_revenue_and_hurts_both() -> void:
	var state := _world()
	var command := SetTariffCommand.new(&"AAA", "CCC", 20.0)
	assert_true(command.can_execute(state))
	assert_false(SetTariffCommand.new(&"AAA", "AAA", 20.0).can_execute(state), "pas contre soi-même")
	command.execute(state)
	var importer := state.get_country("AAA").economy
	var exporter := state.get_country("CCC").economy
	assert_gt(importer.trade_inflation, 0.0)
	assert_gt(importer.trade_customs, 0.0, "recettes douanières")
	assert_lt(importer.trade_growth, 0.0)
	assert_lt(exporter.trade_growth, 0.0)
	assert_lt(TradeSystem.current_flow(state, "CCC", "AAA"), 50.0, "moins d'échanges")


func test_removing_start_surcharge_helps() -> void:
	var state := _world()
	SetTariffCommand.new(&"CCC", "AAA", 0.0).execute(state)
	assert_gt(state.get_country("CCC").economy.trade_growth, 0.0)
	assert_lt(state.get_country("CCC").economy.trade_inflation, 0.0)
	var limit := float(state.trade_settings["max_trade_gain"])
	assert_lte(TradeSystem.current_flow(state, "AAA", "CCC"), 80.0 * limit + 0.001, "hausse plafonnée")


func test_leaving_agreement_restores_tariffs() -> void:
	var state := _world()
	var command := LeaveAgreementCommand.new(&"AAA", "fta")
	assert_true(command.can_execute(state))
	assert_false(LeaveAgreementCommand.new(&"CCC", "fta").can_execute(state), "pas membre")
	command.execute(state)
	assert_false(state.trade.agreements.has("fta"), "accord dissous avec un seul membre")
	assert_eq(state.trade.tariff_change("BBB", "AAA"), 5.0)
	assert_lt(state.get_country("BBB").economy.trade_growth, 0.0)
	assert_eq(state.events.back()["type"], TradeSystem.EVENT_AGREEMENT_LEFT)


func test_full_embargo_blocks_trade() -> void:
	var state := _world()
	var command := SetEmbargoCommand.new(&"AAA", "BBB")
	assert_true(command.can_execute(state))
	command.execute(state)
	assert_false(SetEmbargoCommand.new(&"AAA", "BBB").can_execute(state), "déjà en place")
	assert_true(state.trade.trade_blocked("BBB", "AAA"))
	assert_almost_eq(TradeSystem.current_flow(state, "BBB", "AAA"), 100.0 * exp(-4.0), 1.0, "commerce presque nul")
	assert_lt(state.get_country("BBB").economy.trade_growth, 0.0)
	SetEmbargoCommand.new(&"AAA", "BBB", TradeState.ALL_GOODS, false).execute(state)
	assert_false(state.trade.trade_blocked("BBB", "AAA"))
	assert_true(state.trade.tariff_changes.is_empty(), "retour à la normale")


func test_resource_embargo() -> void:
	var state := _world()
	var shares := TradeModel.supplier_shares(state, "AAA", "oil")
	assert_almost_eq(float(shares["BBB"]) + float(shares["CCC"]), 1.0, 0.001)
	assert_gt(float(shares["BBB"]), float(shares["CCC"]), "liens commerciaux plus forts")
	assert_false(SetEmbargoCommand.new(&"AAA", "BBB", "unknown").can_execute(state))
	SetEmbargoCommand.new(&"AAA", "BBB", "oil").execute(state)
	assert_false(TradeModel.supplier_shares(state, "AAA", "oil").has("BBB"))
	ResourceSystem.new().on_month(state)
	assert_gt(float(state.get_country("BBB").resources.blocked_share.get("oil", 0.0)), 0.0, "débouché perdu")
	assert_gt(float(state.get_country("AAA").resources.shortage.get("oil", 0.0)), 0.0, "pénurie de transition")
	assert_gt(state.markets["oil"].price, 60.0)

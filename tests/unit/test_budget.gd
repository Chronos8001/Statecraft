extends GutTest
## Budget de l'État : recettes, effets, système mensuel, règle de l'IA et commande du joueur.

const DEFINES_PATH := "res://data/defines.json"
const TAXES_PATH := "res://data/budget_taxes/taxes.json"
const SPENDING_PATH := "res://data/budget_spending/spending.json"
const BUDGET := {
	"taxes": {
		"income_tax": {"brackets": [0.0, 20.0, 30.0, 45.0], "revenue": 10.0},
		"corporate_tax": {"rate": 25.0, "revenue": 3.0},
		"vat": {"rate": 20.0, "revenue": 8.0},
		"carbon_tax": {"rate": 0.0, "revenue": 0.0},
		"customs": {"rate": 3.0, "revenue": 0.5},
		"social_contributions": {"rate": 40.0, "revenue": 12.0},
		"resource_taxes": {"rate": 50.0, "revenue": 0.5},
	},
	"spending": {"health": 8.0, "education": 5.0, "pensions": 12.0, "defense": 2.0, "administration": 10.0},
}
const CURRENCIES := {
	"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 4.0, "inflation_target": 2.0, "peg": "", "independent": true,
		"issuer": "AAA"},
	"bbc": {"code": "BBC", "usd_rate": 20.0, "policy_rate": 12.0, "inflation_target": 5.0, "peg": "",
		"independent": false, "issuer": "BBB"},
}

var _economy_settings: Dictionary
var _definitions: Dictionary


func before_all() -> void:
	var defines: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_economy_settings = defines["economy"]
	_definitions = {
		"taxes": JSON.parse_string(FileAccess.get_file_as_string(TAXES_PATH)),
		"spending": JSON.parse_string(FileAccess.get_file_as_string(SPENDING_PATH)),
		"settings": defines["budget"],
	}


func _country(currency: String, balance: float) -> Dictionary:
	return {"population": 60000000, "currency": currency, "budget": BUDGET, "economy": {"gdp_billion_usd": 3000.0,
		"debt_to_gdp": 1.0, "growth": 1.0, "inflation": 2.0, "unemployment": 7.0, "budget_balance": balance,
		"rating": "AA", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}}}


func _world(player: StringName = &"AAA") -> SimState:
	var state := SimState.new()
	var date := GameDate.new()
	date.year = 2026
	date.month = 1
	date.day = 1
	state.setup(3, date, player)
	WorldSetup.populate(state, {"AAA": _country("usd", -5.0), "BBB": _country("bbc", -3.0)}, CURRENCIES,
		_economy_settings, _definitions)
	return state


func _run_months(state: SimState, months: int) -> void:
	var budget_system := BudgetSystem.new()
	var economy_system := EconomySystem.new()
	for month: int in months:
		state.date.month = month % 12 + 1
		budget_system.on_month(state)
		economy_system.on_month(state)


func _economy(state: SimState, tag: String) -> EconomyState:
	return state.get_country(tag).economy


func test_tax_revenue_shrinks_above_start_rate() -> void:
	assert_almost_eq(BudgetModel.tax_revenue(20.0, 20.0, 0.4, 0.5), 8.0, 0.0001)
	assert_almost_eq(BudgetModel.tax_revenue(30.0, 20.0, 0.4, 0.5), 30.0 * 0.4 * 0.95, 0.0001)
	assert_eq(BudgetModel.tax_revenue(0.0, 20.0, 0.4, 0.5), 0.0)


func test_average_income_rate() -> void:
	var brackets: Array[float] = [0.0, 20.0, 40.0, 60.0]
	assert_almost_eq(BudgetModel.average_income_rate(brackets, [0.25, 0.25, 0.25, 0.25]), 30.0, 0.0001)


func test_setup_matches_starting_balance() -> void:
	var state := _world()
	var economy := _economy(state, "AAA")
	var currency := state.get_currency("usd")
	BudgetSystem.update_budget(state.get_country("AAA"), state)
	assert_almost_eq(economy.budget.total_revenue(), 34.0, 0.001, "recettes de départ")
	assert_almost_eq(economy.budget_balance(currency), -5.0, 0.001, "dépenses ajustées sur le solde réel")
	assert_eq(economy.budget_growth, 0.0, "budget de départ neutre")
	assert_eq((economy.budget.effects["groups"] as Dictionary).size(), 0)


func test_spending_effects() -> void:
	var state := _world()
	var budget := _economy(state, "AAA").budget
	budget.spending["education"] = float(budget.start_spending["education"]) + 1.0
	BudgetSystem.update_budget(state.get_country("AAA"), state)
	var education: Dictionary = (_definitions["spending"]["education"] as Dictionary)["effects"]
	assert_almost_eq(float(budget.effects["growth"]), float(education["growth"]), 0.0001)
	assert_almost_eq(float(budget.effects["research"]), float(education["research"]), 0.0001)
	assert_gt(float((budget.effects["groups"] as Dictionary)["youth"]), 0.0)


func test_top_bracket_hits_elites() -> void:
	var state := _world()
	var budget := _economy(state, "AAA").budget
	budget.income_brackets[3] += 10.0
	BudgetSystem.update_budget(state.get_country("AAA"), state)
	assert_lt(float((budget.effects["groups"] as Dictionary)["elites"]), 0.0)
	assert_false((budget.effects["groups"] as Dictionary).has("workers"), "tranches basses inchangées")


func test_player_budget_command() -> void:
	var state := _world()
	var economy := _economy(state, "AAA")
	var currency := state.get_currency("usd")
	var balance := economy.budget_balance(currency)
	var brackets: Array[float] = [0.0, 20.0, 30.0, 45.0]
	var command := SetBudgetCommand.new(&"AAA", brackets, {"vat": 25.0}, {"defense": 4.0})
	assert_true(command.can_execute(state))
	command.execute(state)
	assert_eq(float(economy.budget.tax_rates["vat"]), 25.0)
	assert_gt(economy.budget.total_revenue(), 34.0, "TVA plus haute")
	assert_ne(economy.budget_balance(currency), balance)
	assert_false(SetBudgetCommand.new(&"AAA", brackets, {"unknown": 1.0}).can_execute(state))
	var clamped := SetBudgetCommand.new(&"AAA", brackets, {"vat": 99.0})
	clamped.execute(state)
	assert_eq(float(economy.budget.tax_rates["vat"]), 40.0, "taux plafonné")


func test_spending_more_boosts_growth_then_debt() -> void:
	var calm := _world()
	var spender := _world()
	var spending := {}
	for line_id: Variant in _economy(spender, "AAA").budget.spending.keys():
		spending[line_id] = float(_economy(spender, "AAA").budget.spending[line_id]) * 1.1
	SetBudgetCommand.new(&"AAA", [] as Array[float], {}, spending).execute(spender)
	_run_months(calm, 12)
	_run_months(spender, 12)
	var usd_calm := calm.get_currency("usd")
	var usd_spender := spender.get_currency("usd")
	assert_gt(_economy(spender, "AAA").growth, _economy(calm, "AAA").growth, "relance budgétaire")
	assert_gt(_economy(spender, "AAA").debt_ratio(usd_spender), _economy(calm, "AAA").debt_ratio(usd_calm))


func test_money_printing() -> void:
	var state := _world(&"BBB")
	assert_false(SetBudgetCommand.new(&"AAA", [] as Array[float], {}, {}, 2.0).can_execute(state),
		"banque centrale indépendante")
	var command := SetBudgetCommand.new(&"BBB", [] as Array[float], {}, {}, 3.0)
	assert_true(command.can_execute(state))
	var reference := _world(&"BBB")
	command.execute(state)
	_run_months(state, 24)
	_run_months(reference, 24)
	var currency := state.get_currency("bbc")
	assert_gt(_economy(state, "BBB").inflation, _economy(reference, "BBB").inflation, "inflation")
	assert_lt(_economy(state, "BBB").debt_ratio(currency), _economy(reference, "BBB").debt_ratio(
		reference.get_currency("bbc")), "moins d'emprunt")


func test_ai_tightens_when_debt_rises() -> void:
	var state := _world(&"")
	var economy := _economy(state, "AAA")
	var currency := state.get_currency("usd")
	BudgetSystem.update_budget(state.get_country("AAA"), state)
	var spending_before := economy.budget.total_spending()
	economy.local_debt *= 1.3
	BudgetSystem.adjust_ai_budget(state.get_country("AAA"), state)
	assert_lt(economy.budget.total_spending(), spending_before, "économies quand la dette monte")
	assert_almost_eq(spending_before - economy.budget.total_spending(),
		float((_definitions["settings"]["ai"] as Dictionary)["max_adjustment_per_year"]) / 12.0, 0.001, "par petits pas")
	assert_gt(economy.debt_ratio(currency), economy.start_debt_ratio)

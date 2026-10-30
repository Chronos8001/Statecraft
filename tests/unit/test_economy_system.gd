extends GutTest
## Mise en place et évolution mensuelle de l'économie sur un petit monde fictif, avec les vrais réglages.

const DEFINES_PATH := "res://data/defines.json"
const COUNTRIES := {
	"AAA": {"population": 100000000, "currency": "usd", "economy": {"gdp_billion_usd": 5000.0, "debt_to_gdp": 1.0,
		"growth": 2.0, "inflation": 2.0, "unemployment": 4.0, "budget_balance": -4.0, "rating": "AA",
		"foreign_debt_share": 0.0, "sectors": {"services": 0.7, "tech": 0.1, "industry": 0.2}}},
	"BBB": {"population": 50000000, "currency": "bbc", "economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.6,
		"growth": 4.0, "inflation": 12.0, "unemployment": 9.0, "budget_balance": -3.0,
		"foreign_debt_share": 0.5, "sectors": {"agriculture": 0.2, "industry": 0.3, "services": 0.5}}},
	"CCC": {"population": 2000000, "currency": "ccp", "economy": {"gdp_billion_usd": 40.0, "debt_to_gdp": 0.3,
		"growth": 3.0, "inflation": 2.5, "unemployment": 6.0, "budget_balance": 1.0, "rating": "A",
		"foreign_debt_share": 0.0, "sectors": {"energy": 0.5, "services": 0.5}}},
}
const CURRENCIES := {
	"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 4.0, "inflation_target": 2.0, "peg": "", "independent": true, "issuer": "AAA"},
	"bbc": {"code": "BBC", "usd_rate": 20.0, "policy_rate": 15.0, "inflation_target": 5.0, "peg": "", "independent": false},
	"ccp": {"code": "CCP", "usd_rate": 3.75, "policy_rate": 4.5, "inflation_target": 2.0, "peg": "usd", "independent": false},
}

var _settings: Dictionary


func before_all() -> void:
	_settings = (JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH)) as Dictionary)["economy"]


func _world(player: StringName = &"") -> SimState:
	var state := SimState.new()
	var date := GameDate.new()
	date.year = 2026
	date.month = 1
	date.day = 1
	state.setup(7, date, player)
	WorldSetup.populate(state, COUNTRIES, CURRENCIES, _settings)
	return state


func _run_months(state: SimState, months: int) -> void:
	var system := EconomySystem.new({"tech": {"trend": 3.0}, "agriculture": {"trend": -1.5}})
	for month: int in months:
		state.date.month = month % 12 + 1
		system.on_month(state)


func _economy(state: SimState, tag: String) -> EconomyState:
	return state.get_country(tag).economy


func test_setup_reproduces_starting_data() -> void:
	var state := _world()
	var economy := _economy(state, "AAA")
	var usd := state.get_currency("usd")
	assert_almost_eq(economy.gdp_usd(usd), 5000.0, 0.01)
	assert_almost_eq(economy.debt_ratio(usd), 1.0, 0.0001)
	assert_almost_eq(economy.budget_balance(usd), -4.0, 0.0001, "solde primaire calé sur le solde réel")
	assert_eq(CreditRating.new(_settings).id_of(economy.rating), "AA")
	assert_false(economy.rating_estimated)
	assert_eq(state.get_currency("bbc").issuer, "BBB")
	assert_eq(usd.members, ["AAA"] as Array[String])


func test_foreign_debt_share_and_estimated_rating() -> void:
	var state := _world()
	var economy := _economy(state, "BBB")
	var currency := state.get_currency("bbc")
	assert_almost_eq(economy.foreign_debt_share(currency), 0.5, 0.0001)
	assert_true(economy.rating_estimated)
	var ratings := CreditRating.new(_settings)
	assert_gte(economy.rating, ratings.index_of(str(_settings["min_estimated_rating"])))


func test_start_is_near_equilibrium() -> void:
	var state := _world()
	_run_months(state, 1)
	var economy := _economy(state, "AAA")
	assert_almost_eq(economy.growth, 2.0, 0.2)
	assert_almost_eq(state.get_currency("usd").policy_rate, 4.0, 0.3)


func test_peg_follows_anchor() -> void:
	var state := _world()
	_run_months(state, 24)
	var usd := state.get_currency("usd")
	var ccp := state.get_currency("ccp")
	assert_almost_eq(ccp.usd_rate, 3.75, 0.0001, "ancré au dollar")
	assert_almost_eq(ccp.policy_rate - usd.policy_rate, 0.5, 0.0001, "même écart de taux qu'au départ")


func test_high_inflation_comes_down() -> void:
	var state := _world()
	_run_months(state, 60)
	var economy := _economy(state, "BBB")
	assert_lt(economy.inflation, 12.0)
	assert_gt(state.get_currency("bbc").usd_rate, 20.0, "la monnaie perd de la valeur avec l'inflation")


func test_player_sets_rate_of_dependent_central_bank() -> void:
	var state := _world(&"BBB")
	var command := SetPolicyRateCommand.new(&"BBB", 2.0)
	assert_true(command.can_execute(state))
	command.execute(state)
	_run_months(state, 3)
	assert_eq(state.get_currency("bbc").policy_rate, 2.0, "le système ne touche plus au taux")
	assert_false(SetPolicyRateCommand.new(&"AAA", 1.0).can_execute(state), "banque centrale indépendante")
	assert_false(SetPolicyRateCommand.new(&"CCC", 1.0).can_execute(state), "monnaie ancrée")


func test_low_rates_overheat_the_economy() -> void:
	var calm := _world(&"BBB")
	var loose := _world(&"BBB")
	SetPolicyRateCommand.new(&"BBB", 15.0).execute(calm)
	SetPolicyRateCommand.new(&"BBB", 0.0).execute(loose)
	_run_months(calm, 24)
	_run_months(loose, 24)
	assert_gt(_economy(loose, "BBB").inflation, _economy(calm, "BBB").inflation)
	assert_lt(_economy(loose, "BBB").unemployment, _economy(calm, "BBB").unemployment)


func test_imf_program() -> void:
	var state := _world()
	var economy := _economy(state, "BBB")
	var ratings := CreditRating.new(_settings)
	economy.rating = ratings.index_of("B")
	var command := RequestImfCommand.new(&"BBB")
	assert_true(command.can_execute(state))
	assert_false(RequestImfCommand.new(&"AAA").can_execute(state), "pays bien noté")
	command.execute(state)
	assert_true(economy.in_imf_program())
	assert_false(command.can_execute(state), "déjà sous programme")
	var balance_before := economy.primary_balance
	_run_months(state, 12)
	assert_gt(economy.primary_balance, balance_before, "effort budgétaire")


func test_debt_crisis_and_recovery() -> void:
	var state := _world()
	var economy := _economy(state, "BBB")
	var currency := state.get_currency("bbc")
	var ratings := CreditRating.new(_settings)
	var debt_before := economy.total_debt(currency)
	var rate_before := currency.usd_rate
	EconomySystem.start_crisis(state.get_country("BBB"), currency, state, ratings)
	assert_true(economy.in_crisis())
	assert_true(ratings.is_default(economy.rating))
	assert_lt(economy.total_debt(currency), debt_before, "dette restructurée")
	assert_gt(currency.usd_rate, rate_before, "la monnaie décroche")
	assert_eq(state.events.back()["type"], EconomySystem.EVENT_DEBT_CRISIS)
	_run_months(state, int((_settings["crisis"] as Dictionary)["duration_months"]))
	assert_false(economy.in_crisis())
	assert_gt(economy.rating, 0, "sortie du défaut")


func test_simulation_is_deterministic() -> void:
	var first := _world()
	var second := _world()
	_run_months(first, 36)
	_run_months(second, 36)
	for tag: String in COUNTRIES.keys():
		assert_eq(_economy(first, tag).real_gdp, _economy(second, tag).real_gdp, tag)
		assert_eq(_economy(first, tag).rating, _economy(second, tag).rating, tag)


func test_sector_shares_stay_normalized() -> void:
	var state := _world()
	_run_months(state, 120)
	var total := 0.0
	for share: Variant in _economy(state, "AAA").sectors.values():
		total += float(share)
	assert_almost_eq(total, 1.0, 0.0001)
	assert_gt(float(_economy(state, "AAA").sectors["tech"]), 0.1)

extends GutTest
## Formules macroéconomiques.

const SETTINGS := {
	"rate_sensitivity": 0.5, "max_real_rate_gap": 10.0, "output_gap_decay": 0.1, "inflation_adjustment": 0.1,
	"phillips_slope": 0.5, "credibility_independent": 0.8, "credibility_dependent": 0.2,
	"depreciation_passthrough": 0.2, "okun_coefficient": 0.5, "unemployment_adjustment": 0.1,
	"taylor_inflation_weight": 0.5, "taylor_gap_weight": 0.5, "dependent_inflation_weight": 0.1,
	"rate_smoothing": 0.5, "max_rate_step": 1.0, "min_policy_rate": 0.0, "max_policy_rate": 50.0,
	"fx_rate_sensitivity": 0.5, "max_inflation_excess": 20.0,
	"long_run_growth": {"base": 6.0, "slope": 1.0, "min": 1.0, "max": 6.0},
	"rating_model": {"base": 5.0, "gdp_per_capita_log": 3.0, "debt": -2.0, "inflation_excess": -0.2, "growth": 0.1,
		"real_interest_burden": -0.5, "imf_bonus": 1.0},
}


func test_long_run_growth_is_higher_for_poor_countries() -> void:
	assert_almost_eq(EconomyModel.long_run_growth(1000.0, SETTINGS), 6.0, 0.001, "plafond")
	assert_almost_eq(EconomyModel.long_run_growth(20000.0, SETTINGS), 6.0 - log(20.0), 0.001)
	assert_almost_eq(EconomyModel.long_run_growth(1.0e6, SETTINGS), 1.0, 0.001, "plancher")


func test_demand_effect_follows_real_rate() -> void:
	assert_almost_eq(EconomyModel.demand_effect(5.0, 2.0, 1.0, SETTINGS), -1.0, 0.001, "taux réel 3 > neutre 1")
	assert_almost_eq(EconomyModel.demand_effect(0.0, 4.0, 1.0, SETTINGS), 2.5, 0.001, "taux réel -4")
	assert_almost_eq(EconomyModel.demand_effect(100.0, 0.0, 0.0, SETTINGS), -5.0, 0.001, "écart plafonné à 10")


func test_output_gap_accumulates_then_decays() -> void:
	assert_almost_eq(EconomyModel.next_output_gap(0.0, 3.0, 2.0, SETTINGS), 1.0 / 12.0, 0.0001)
	assert_almost_eq(EconomyModel.next_output_gap(2.0, 2.0, 2.0, SETTINGS), 1.8, 0.0001)


func test_expected_inflation_is_anchored_by_credibility() -> void:
	assert_almost_eq(EconomyModel.expected_inflation(10.0, 2.0, true, SETTINGS), 3.6, 0.0001)
	assert_almost_eq(EconomyModel.expected_inflation(10.0, 2.0, false, SETTINGS), 8.4, 0.0001)


func test_inflation_moves_toward_expectation() -> void:
	assert_almost_eq(EconomyModel.next_inflation(10.0, 2.0, 0.0, 0.0, SETTINGS), 9.2, 0.0001)
	assert_almost_eq(EconomyModel.next_inflation(2.0, 2.0, 2.0, 0.0, SETTINGS), 2.1, 0.0001, "économie en surchauffe")
	assert_almost_eq(EconomyModel.next_inflation(2.0, 2.0, 0.0, 5.0, SETTINGS), 3.0, 0.0001, "monnaie en baisse")


func test_unemployment_follows_okun() -> void:
	assert_almost_eq(EconomyModel.next_unemployment(5.0, 5.0, 2.0, SETTINGS), 4.9, 0.0001)
	assert_almost_eq(EconomyModel.next_unemployment(8.0, 5.0, 0.0, SETTINGS), 7.7, 0.0001)


func test_taylor_rule() -> void:
	assert_almost_eq(EconomyModel.taylor_rate(2.0, 0.0, 2.0, 1.0, true, SETTINGS), 3.0, 0.0001, "à la cible")
	assert_almost_eq(EconomyModel.taylor_rate(6.0, 2.0, 2.0, 1.0, true, SETTINGS), 10.0, 0.0001)
	assert_almost_eq(EconomyModel.taylor_rate(6.0, 0.0, 2.0, 1.0, false, SETTINGS), 7.4, 0.0001, "banque sous contrôle")


func test_policy_rate_moves_gradually() -> void:
	assert_almost_eq(EconomyModel.next_policy_rate(2.0, 3.0, SETTINGS), 2.5, 0.0001)
	assert_almost_eq(EconomyModel.next_policy_rate(2.0, 10.0, SETTINGS), 3.0, 0.0001, "pas maximal")
	assert_almost_eq(EconomyModel.next_policy_rate(0.5, -5.0, SETTINGS), 0.0, 0.0001, "taux plancher")


func test_depreciation_follows_inflation_gap() -> void:
	assert_almost_eq(EconomyModel.monthly_depreciation(14.0, 0.0, 2.0, SETTINGS), 1.0, 0.0001)
	assert_almost_eq(EconomyModel.monthly_depreciation(2.0, 2.4, 2.0, SETTINGS), -0.1, 0.0001, "taux attractifs")


func test_rating_score() -> void:
	var base := EconomyModel.rating_score(1000.0, 0.0, 2.0, 2.0, 0.0, 0.0, false, SETTINGS)
	assert_almost_eq(base, 5.0, 0.0001)
	assert_almost_eq(EconomyModel.rating_score(1000.0, 1.0, 2.0, 2.0, 0.0, 0.0, false, SETTINGS), 3.0, 0.0001)
	assert_almost_eq(EconomyModel.rating_score(1000.0, 0.0, 102.0, 2.0, 0.0, 0.0, false, SETTINGS), 1.0, 0.0001,
		"excès d'inflation plafonné")
	assert_gt(EconomyModel.rating_score(1000.0, 0.0, 2.0, 2.0, 0.0, 0.0, true, SETTINGS), base, "aide du FMI")


func test_rating_review_moves_one_notch() -> void:
	assert_eq(EconomyModel.reviewed_rating(10, 13.0, 21, 1.0), 11)
	assert_eq(EconomyModel.reviewed_rating(10, 10.8, 21, 1.0), 10, "écart trop faible")
	assert_eq(EconomyModel.reviewed_rating(10, 2.0, 21, 1.0), 9)
	assert_eq(EconomyModel.reviewed_rating(21, 30.0, 21, 1.0), 21)


func test_crisis_probability() -> void:
	assert_eq(EconomyModel.crisis_probability(8, 5, 0.01), 0.0)
	assert_almost_eq(EconomyModel.crisis_probability(5, 5, 0.01), 0.01, 0.0001)
	assert_almost_eq(EconomyModel.crisis_probability(0, 5, 0.01), 0.06, 0.0001)


func test_sector_shares_follow_trends() -> void:
	var shares := EconomyModel.next_sector_shares({"tech": 0.5, "agriculture": 0.5}, {"tech": 6.0, "agriculture": -6.0})
	assert_gt(float(shares["tech"]), 0.5)
	assert_almost_eq(float(shares["tech"]) + float(shares["agriculture"]), 1.0, 0.0001)

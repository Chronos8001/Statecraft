extends GutTest
## Difficulté et défis de départ des pays.

const SETTINGS := {
	"gdp_weight": 1.0, "military_weight": 0.5, "power_floor": 2.5,
	"difficulty_thresholds": [6.0, 5.0, 3.8, 2.5],
}
const CHALLENGES := {
	"high_debt": {"weight": 0.5, "rule": {"type": "debt_above", "threshold": 1.0}},
	"poverty": {"weight": 0.75, "rule": {"type": "gdp_per_capita_below", "threshold": 1500}},
	"occupied_territory": {"weight": 1.5, "rule": {"type": "occupied_provinces"}},
	"limited_recognition": {"weight": 1.0, "rule": {"type": "limited_recognition"}},
	"fragile_coalition": {"weight": 0.25, "rule": {"type": "coalition_partners_at_least", "threshold": 2}},
	"failed_state": {"weight": 1.5, "rule": {"type": "regime", "regimes": ["failed_state"]}},
	"landlocked": {"weight": 0.25, "rule": {"type": "landlocked"}},
	"no_army": {"weight": 0.25, "rule": {"type": "military_below", "threshold": 1}},
	"aaa_war": {"weight": 2.0},
}
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "coastal": true},
	"2": {"owner": "AAA", "controller": "BBB", "coastal": false},
	"3": {"owner": "BBB", "controller": "BBB", "coastal": false},
	"4": {"owner": "", "controller": ""},
}


## gdp en milliards de dollars ; 10 000 Md$ et 1 000 000 de militaires → score 4 + 3 = 7.
func _country(gdp: float, personnel: int, extra: Dictionary = {}) -> Dictionary:
	var country := {
		"population": 10000000, "regime": "parliamentary_republic",
		"economy": {"gdp_billion_usd": gdp, "debt_to_gdp": 0.5},
		"military": {"active_personnel": personnel, "reserve_personnel": 0},
	}
	country.merge(extra, true)
	return country


func test_province_stats() -> void:
	var stats := CountrySelection.province_stats(PROVINCES)
	assert_eq(stats["AAA"], {"occupied": 1, "coastal": true})
	assert_eq(stats["BBB"], {"occupied": 0, "coastal": false})
	assert_false(stats.has(""))


func test_rules() -> void:
	var poor := _country(10.0, 1000, {"economy": {"gdp_billion_usd": 10.0, "debt_to_gdp": 1.2}})
	var stats := {"occupied": 2, "coastal": false}
	var ids := CountrySelection.challenges_for(poor, stats, CHALLENGES)
	assert_eq(ids, ["high_debt", "landlocked", "occupied_territory", "poverty"] as Array[String])


func test_regime_coalition_recognition_and_army_rules() -> void:
	var country := _country(500.0, 0, {"regime": "failed_state", "limited_recognition": true,
		"coalition_partners": ["a", "b"]})
	var ids := CountrySelection.challenges_for(country, {"coastal": true}, CHALLENGES)
	assert_eq(ids, ["failed_state", "fragile_coalition", "limited_recognition", "no_army"] as Array[String])


func test_written_challenges_replace_generic_ones() -> void:
	var country := _country(10.0, 1000, {"challenges": ["aaa_war", "high_debt", "unknown"]})
	var ids := CountrySelection.challenges_for(country, {"occupied": 3}, CHALLENGES)
	assert_eq(ids, ["aaa_war", "high_debt"] as Array[String], "défis inconnus ignorés, pas de défi générique ajouté")


func test_power_score_has_a_floor() -> void:
	assert_almost_eq(CountrySelection.power_score(_country(9999.0, 999999), SETTINGS), 7.0, 0.001)
	assert_eq(CountrySelection.power_score(_country(0.5, 0), SETTINGS), 2.5)


func test_difficulty_levels() -> void:
	var none: Array[String] = []
	assert_eq(CountrySelection.difficulty_for(_country(9999.0, 999999), none, CHALLENGES, SETTINGS), 1)
	assert_eq(CountrySelection.difficulty_for(_country(999.0, 9999), none, CHALLENGES, SETTINGS), 2, "3 + 2 = 5")
	assert_eq(CountrySelection.difficulty_for(_country(999.0, 99), none, CHALLENGES, SETTINGS), 3, "3 + 1 = 4")
	assert_eq(CountrySelection.difficulty_for(_country(99.0, 999), none, CHALLENGES, SETTINGS), 4, "2 + 1,5 = 3,5")


func test_challenges_lower_the_score() -> void:
	var war: Array[String] = ["aaa_war"]
	assert_eq(CountrySelection.difficulty_for(_country(9999.0, 999999), war, CHALLENGES, SETTINGS), 2, "7 - 2 = 5")
	assert_eq(CountrySelection.difficulty_for(_country(0.5, 0), war, CHALLENGES, SETTINGS), 5, "plancher 2,5 - 2")


func test_written_difficulty_wins() -> void:
	var none: Array[String] = []
	assert_eq(CountrySelection.difficulty_for(_country(9999.0, 999999, {"difficulty": 4}), none, CHALLENGES, SETTINGS), 4)
	assert_eq(CountrySelection.difficulty_for(_country(1.0, 0, {"difficulty": 9}), none, CHALLENGES, SETTINGS), 5)


func test_playable_tags_filters() -> void:
	var countries := {
		"AAA": _country(9999.0, 999999),
		"BBB": _country(0.5, 0, {"limited_recognition": true}),
		"CCC": _country(0.5, 0),
	}
	var selection := CountrySelection.build(countries, PROVINCES, CHALLENGES, SETTINGS)
	assert_eq(selection.playable_tags(false), ["AAA", "CCC"] as Array[String])
	assert_eq(selection.playable_tags(true), ["AAA", "BBB", "CCC"] as Array[String])
	assert_eq(selection.playable_tags(true, 2), ["AAA"] as Array[String], "7 - 1,5 (province occupée) = 5,5")
	assert_eq(selection.challenges["AAA"], ["occupied_territory"] as Array[String])
	assert_false(selection.is_playable("BBB", false))
	assert_true(selection.is_playable("BBB", true))
	assert_false(selection.is_playable("ZZZ", true))

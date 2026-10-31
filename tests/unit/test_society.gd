extends GutTest
## Groupes sociaux, soutien populaire, stabilité et légitimité.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const GROUPS := {
	"workers": {"influence": 1.0, "affinity": {"left": 10, "liberal": -6},
		"reactions": {"unemployment": -4.0, "inflation": -2.0, "growth": 1.0, "blackout": -50.0, "public_ownership": 20.0}},
	"elites": {"influence": 4.0, "affinity": {"left": -20, "liberal": 10},
		"reactions": {"unemployment": 0.0, "inflation": -1.0, "growth": 3.0, "blackout": -40.0, "public_ownership": -60.0}},
	"military": {"influence": 2.0, "affinity": {},
		"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}},
}
const REGIMES := {
	"parliamentary_republic": {"democratic": true, "group_influence": {}},
	"military_junta": {"democratic": false, "group_influence": {"military": 5.0}, "legitimacy": 25.0},
}
const IDEOLOGIES := {"socialist": {"party_group": "left"}, "liberal": {"party_group": "liberal"}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(regime: String, ideology: String) -> Dictionary:
	return {"population": 10000000, "currency": "usd", "regime": regime, "ideology": ideology,
		"economy": {"gdp_billion_usd": 1000.0, "debt_to_gdp": 0.6, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0,
			"sectors": {"energy": 0.2, "industry": 0.3, "services": 0.5}},
		"investment": {"public_ownership": {"energy": 0.2}, "fdi_inflow": 2.0, "fdi_policy": "open"},
		"society": {"groups": {"workers": 0.6, "elites": 0.1, "military": 0.3}, "stability": 60.0, "corruption": 30.0,
			"democracy": 7.5, "approval": 40.0}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(5, GameDate.new(), &"AAA")
	WorldSetup.populate(state, {"AAA": _country("parliamentary_republic", "socialist"),
		"BBB": _country("military_junta", "liberal")}, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {},
		_defines["investment"], {"groups": GROUPS, "regimes": REGIMES, "ideologies": IDEOLOGIES,
		"settings": _defines["society"]})
	return state


func _months(state: SimState, count: int) -> void:
	for _month: int in count:
		SocietySystem.new().on_month(state)


func test_start_matches_approval() -> void:
	var society := _world().get_country("AAA").society
	assert_almost_eq(society.support, 40.0, 0.01, "soutien de départ = popularité")
	assert_gt(float(society.satisfaction["workers"]), float(society.satisfaction["elites"]),
		"les ouvriers soutiennent davantage un gouvernement socialiste")
	assert_almost_eq(society.stability, 60.0, 0.001)
	assert_almost_eq(society.legitimacy, 75.0, 0.001, "démocratie : indice × 10")
	assert_almost_eq(_world().get_country("BBB").society.legitimacy, 25.0, 0.001, "junte : valeur du régime")


func test_influence_follows_regime() -> void:
	var state := _world()
	var democracy := state.get_country("AAA").society.influence
	var junta := state.get_country("BBB").society.influence
	var total := 0.0
	for weight: Variant in democracy.values():
		total += float(weight)
	assert_almost_eq(total, 1.0, 0.0001)
	assert_gt(float(junta["military"]), float(democracy["military"]), "l'armée pèse plus dans une junte")
	assert_gt(float(democracy["elites"]), 0.1, "les élites pèsent plus que leur part de la population")


func test_start_is_neutral() -> void:
	var state := _world()
	_months(state, 24)
	var society := state.get_country("AAA").society
	assert_almost_eq(society.support, society.start_support, 0.001)
	assert_almost_eq(society.stability, 60.0, 0.001)
	assert_almost_eq(society.legitimacy, 75.0, 0.001)
	assert_eq(state.get_country("AAA").economy.society_growth, 0.0)


func test_unemployment_hurts_workers_and_stability() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	country.economy.unemployment += 5.0
	_months(state, 60)
	var society := country.society
	assert_lt(float(society.satisfaction["workers"]), float(society.start_satisfaction["workers"]) - 15.0)
	assert_almost_eq(float(society.satisfaction["military"]), float(society.start_satisfaction["military"]), 0.001,
		"l'armée ne réagit pas au chômage")
	assert_lt(society.support, society.start_support)
	assert_lt(society.stability, society.start_stability)
	assert_lt(society.legitimacy, society.start_legitimacy)
	assert_lt(country.economy.society_growth, 0.0, "l'instabilité freine la croissance")


func test_satisfaction_moves_gradually() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	country.economy.growth += 3.0
	var start := float(country.society.satisfaction["elites"])
	_months(state, 1)
	var after_one := float(country.society.satisfaction["elites"])
	_months(state, 59)
	var target := start + 9.0 * float(_defines["society"]["gain_factor"])
	assert_between(after_one, start + 0.1, target * 0.5 + start * 0.5, "un premier pas seulement")
	assert_almost_eq(float(country.society.satisfaction["elites"]), target, 0.1)


func test_budget_effects_reach_groups() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	country.economy.budget.effects = {"stability": 5.0, BudgetModel.GROUPS: {"workers": 10.0}}
	_months(state, 80)
	var society := country.society
	assert_almost_eq(float(society.satisfaction["workers"]), float(society.start_satisfaction["workers"]) + 10.0, 0.1)
	assert_gt(society.stability, 65.0, "dépenses sociales : plus de stabilité")
	assert_eq(country.economy.society_growth, 0.0, "pas de frein au-dessus du niveau de départ")


func test_nationalization_angers_elites() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	country.economy.investment.public_ownership["industry"] = 1.0
	_months(state, 60)
	var society := country.society
	assert_lt(float(society.satisfaction["elites"]), float(society.start_satisfaction["elites"]) - 10.0)
	assert_gt(float(society.satisfaction["workers"]), float(society.start_satisfaction["workers"]))


func test_reaction_is_capped() -> void:
	var reactions: Dictionary = GROUPS["workers"]["reactions"]
	assert_eq(SocietyModel.reaction(reactions, {"unemployment": 50.0}, 40.0, 15.0, 0.5), -40.0)
	assert_eq(SocietyModel.reaction(reactions, {"unemployment": -2.0}, 40.0, 15.0, 0.5), 4.0, "gain réduit de moitié")
	assert_eq(SocietyModel.reaction(reactions, {"unemployment": -20.0}, 40.0, 15.0, 0.5), 15.0, "gain plafonné")
	var bounds := [0.0, 100.0]
	assert_eq(SocietyModel.satisfaction_target(10.0, -5.0, -40.0, bounds), 0.0)

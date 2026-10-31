extends GutTest
## Forces armées agrégées : départ neutre, équipement entretenu par le budget, priorités, mobilisation,
## puissance militaire et modules remplaçables.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const GROUPS := ["youth", "workers", "middle_class", "military"]
const BUDGET := {"taxes": {}, "spending": {"defense": {"effects": {"military": 10.0}}},
	"settings": {"income_bracket_weights": []}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _forces(sea: bool) -> Dictionary:
	var branches := {"land": {"share": 0.7, "level": 3.0, "training": 54.0, "morale": 60.0},
		"air": {"share": 0.15, "level": 3.5, "training": 60.0, "morale": 60.0}}
	if sea:
		branches["sea"] = {"share": 0.15, "level": 3.0, "training": 54.0, "morale": 60.0}
	return {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": 30}, "nuclear_warheads": 0}


func _country(sea: bool) -> Dictionary:
	var groups: Dictionary = {}
	for group_id: String in GROUPS:
		groups[group_id] = 0.25
	return {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic",
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"budget": {"spending": {"defense": 2.0}},
		"society": {"groups": groups, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": 100000, "reserve_personnel": 200000}, "armed_forces": _forces(sea)}


func _settings() -> Dictionary:
	var settings: Dictionary = (_defines["military"] as Dictionary).duplicate(true)
	(settings["equipment"] as Dictionary)["cost_growth"] = 0.0
	(settings["mobilization"] as Dictionary)["start"] = {"BBB": 2}
	return settings


func _world() -> SimState:
	var state := SimState.new()
	state.setup(7, GameDate.new(), &"AAA")
	var reactions := {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}
	var group_definitions: Dictionary = {}
	for group_id: String in GROUPS:
		group_definitions[group_id] = {"influence": 1.0, "affinity": {}, "reactions": reactions}
	WorldSetup.populate(state, {"AAA": _country(true), "BBB": _country(false)}, CURRENCIES, _defines["economy"], BUDGET,
		{}, {}, {}, {}, {},
		{"groups": group_definitions, "regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}},
			"ideologies": {}, "settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {}, "organization_rules": {},
			"sanctions": {}, "aid": {}},
		{"settings": _settings()})
	return state


func _months(state: SimState, count: int) -> void:
	var system := MilitarySystem.new()
	for _index: int in count:
		BudgetSystem.update_budget(state.get_country("AAA"), state)
		BudgetSystem.update_budget(state.get_country("BBB"), state)
		system.on_month(state)


func _level(state: SimState, tag: String, branch: String) -> float:
	return float((state.get_country(tag).military.branches[branch] as Dictionary)["level"])


func test_start_forces() -> void:
	var state := _world()
	var military := state.get_country("AAA").military
	assert_eq(military.branches.size(), 3)
	assert_false(state.get_country("BBB").military.has_branch("sea"), "pas de marine sans littoral")
	assert_almost_eq(float(military.priorities["land"]) + float(military.priorities["air"])
		+ float(military.priorities["sea"]), 1.0, 0.0001)
	assert_eq(state.get_country("BBB").military.mobilization, 2, "mobilisation réelle de départ")
	assert_gt(military.power, 0.0)
	assert_gt(DiplomacyModel.power(state, "AAA"), TradeSystem.current_gdp(state, "AAA"), "l'armée compte dans la puissance")


func test_start_is_neutral() -> void:
	var state := _world()
	var start_power := state.get_country("AAA").military.power
	_months(state, 24)
	assert_almost_eq(_level(state, "AAA", "land"), 3.0, 0.001)
	assert_almost_eq(state.get_country("AAA").military.power, start_power, start_power * 0.001)
	var mobilized := state.get_country("BBB")
	assert_eq(float(mobilized.military.effects.get("growth", 0.0)), 0.0, "mobilisation de départ sans effet")
	assert_eq(mobilized.economy.military_growth, 0.0)


func test_spending_maintains_equipment() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	country.economy.budget.spending["defense"] = 4.0
	_months(state, 36)
	assert_gt(_level(state, "AAA", "land"), 3.3, "plus de budget : l'équipement monte")
	assert_gt(float(country.military.special["missiles"]), 40.0, "l'effort budgétaire renforce les capacités spéciales")
	country.economy.budget.spending["defense"] = 1.0
	_months(state, 120)
	assert_lt(_level(state, "AAA", "land"), 3.0, "moins de budget : l'équipement s'use")


func test_priorities_shift_equipment() -> void:
	var state := _world()
	var command := SetDefensePrioritiesCommand.new(&"AAA", {"land": 0.5, "air": 0.35, "sea": 0.15})
	assert_eq(command.refusal_reason(state), "")
	command.execute(state)
	_months(state, 36)
	assert_gt(_level(state, "AAA", "air"), 3.5)
	assert_lt(_level(state, "AAA", "land"), 3.0)
	assert_eq(SetDefensePrioritiesCommand.new(&"AAA", {"land": 0.98, "air": 0.01, "sea": 0.01}).refusal_reason(state),
		"MILITARY_PRIORITY_BOUNDS")
	assert_eq(SetDefensePrioritiesCommand.new(&"BBB", {"sea": 1.0}).refusal_reason(state), "MILITARY_INVALID")


func test_mobilization() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	var reserve_share: Array = (state.military_settings["mobilization"] as Dictionary)["reserve_share"]
	var debt := country.economy.local_debt
	var power := country.military.power
	MobilizeCommand.new(&"AAA", 2).execute(state)
	assert_eq(country.military.personnel(reserve_share), 260000.0, "80 % des réservistes rappelés")
	assert_lt(country.economy.military_growth, 0.0)
	var groups: Dictionary = country.military.effects["groups"]
	assert_lt(float(groups["youth"]), 0.0)
	assert_gt(float(groups["military"]), 0.0)
	assert_eq(MobilizeCommand.new(&"AAA", 0).refusal_reason(state), "MILITARY_COOLDOWN")
	assert_eq(MobilizeCommand.new(&"AAA", 2).refusal_reason(state), "MILITARY_ALREADY")
	_months(state, 1)
	assert_gt(country.economy.local_debt, debt, "la solde des réservistes coûte")
	assert_gt(country.military.power, power)
	_months(state, 3)
	MobilizeCommand.new(&"BBB", 0).execute(state)
	assert_gt(state.get_country("BBB").economy.military_growth, 0.0, "démobiliser relance l'économie")


func test_registry_modules_can_be_replaced() -> void:
	var state := _world()
	assert_true(state.military.model is MilitaryModel)
	assert_true(state.military.resolver is WarResolver)
	assert_true(state.military.ai is MilitaryAI)
	state.military.model = FrozenModel.new()
	_months(state, 1)
	assert_eq(state.get_country("AAA").military.power, 123.0, "le module de remplacement est utilisé")


class FrozenModel:
	extends MilitaryModel

	func update_country(country: CountryState, _state: SimState) -> void:
		country.military.power = 123.0


func test_conscription_law_changes_personnel() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	var reserve_share: Array = (state.military_settings["mobilization"] as Dictionary)["reserve_share"]
	country.laws["conscription"] = "selective"
	country.military.start_conscription = "selective"
	_months(state, 6)
	assert_eq(country.military.personnel(reserve_share), 100000.0, "loi de départ : effectifs inchangés")
	country.laws["conscription"] = "universal"
	_months(state, 120)
	assert_gt(country.military.personnel(reserve_share), 125000.0, "conscription : plus de soldats")
	assert_gt(country.military.reserves(), 380000.0, "et plus de réservistes")
	assert_lt(float((country.military.branches["land"] as Dictionary)["training"]), 54.0, "mais moins entraînés")

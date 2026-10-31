extends GutTest
## Électricité et bâtiments : répartition de la production, coupures, règle de l'IA, chantiers.

const DEFINES_PATH := "res://data/defines.json"
const SOURCES_PATH := "res://data/energy_sources/sources.json"
const BUILDINGS_PATH := "res://data/buildings/buildings.json"
const HOURS := 8760.0
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "terrain": "plains", "coastal": true, "population": 1000000,
		"resources": {"coal": 5}},
	"2": {"owner": "AAA", "controller": "AAA", "terrain": "mountains", "coastal": false, "population": 200000,
		"resources": {}},
	"3": {"owner": "BBB", "controller": "BBB", "terrain": "plains", "coastal": false, "population": 500000,
		"resources": {}},
}

var _defines: Dictionary
var _sources: Dictionary
var _buildings: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_sources = JSON.parse_string(FileAccess.get_file_as_string(SOURCES_PATH))
	_buildings = JSON.parse_string(FileAccess.get_file_as_string(BUILDINGS_PATH))


func _country(generation: Dictionary) -> Dictionary:
	return {"population": 10000000, "currency": "usd", "energy": {"generation": generation},
		"resources": {"coal": {"production": 10.0, "consumption": 100.0}},
		"economy": {"gdp_billion_usd": 1000.0, "debt_to_gdp": 0.5, "growth": 3.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": -2.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"industry": 0.5, "services": 0.5}}}


func _world(player: StringName = &"AAA") -> SimState:
	var state := SimState.new()
	state.setup(4, GameDate.new(), player)
	var countries := {"AAA": _country({"coal": 100.0, "solar": 20.0, "nuclear": 50.0}), "BBB": _country({"gas": 50.0})}
	var coal := {"market": {"base_price": 100.0, "unit_value": 0.1, "price_unit_key": "UNIT_PRICE_COAL",
		"quantity_unit_key": "UNIT_QUANTITY_COAL", "demand_elasticity": 0.2, "supply_elasticity": 0.2,
		"income_elasticity": 0.0, "demand_trend": 0.0, "supply_trend": 0.0}}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {"coal": coal},
		{"straits": {}, "sectors": {}, "settings": _defines["resources"]}, {},
		{"sources": _sources, "buildings": _buildings, "provinces": PROVINCES, "mine_outputs": {"coal": 10.0},
		"settings": _defines["energy"]})
	return state


func test_dispatch_reproduces_start_mix() -> void:
	var capacity := {"coal": EnergyModel.capacity_for(100.0, 0.55, HOURS), "solar": EnergyModel.capacity_for(20.0, 0.16, HOURS)}
	var result := EnergyModel.dispatch(capacity, 120.0, _sources, {}, HOURS)
	assert_almost_eq(float(result["output"]["coal"]), 100.0, 0.01)
	assert_almost_eq(float(result["output"]["solar"]), 20.0, 0.01)
	assert_eq(float(result["blackout"]), 0.0)
	assert_almost_eq(float(result["max_supply"]), 20.0 + 100.0 * 0.85 / 0.55, 0.01, "marge du charbon")


func test_fossil_plants_fill_the_gap_then_blackouts() -> void:
	var capacity := {"coal": EnergyModel.capacity_for(100.0, 0.55, HOURS), "solar": EnergyModel.capacity_for(20.0, 0.16, HOURS)}
	var more := EnergyModel.dispatch(capacity, 150.0, _sources, {}, HOURS)
	assert_almost_eq(float(more["output"]["coal"]), 130.0, 0.01)
	var too_much := EnergyModel.dispatch(capacity, 300.0, _sources, {}, HOURS)
	assert_almost_eq(float(too_much["blackout"]), (300.0 - float(too_much["max_supply"])) / 300.0, 0.0001)
	var no_fuel := EnergyModel.dispatch(capacity, 120.0, _sources, {"coal": 0.5}, HOURS)
	assert_gt(float(no_fuel["blackout"]), 0.0, "pénurie de charbon")


func test_expansion_restores_margin() -> void:
	var added := EnergyModel.expansion(100.0, 100.0, 1.2, {"solar": 1.0}, _sources, HOURS)
	assert_almost_eq(EnergyModel.twh(float(added["solar"]), 0.16, HOURS), 20.0, 0.01)
	assert_true(EnergyModel.expansion(130.0, 100.0, 1.2, {"solar": 1.0}, _sources, HOURS).is_empty())


func test_start_is_neutral() -> void:
	var state := _world()
	EnergySystem.update_energy(state.get_country("AAA"), state)
	var energy := state.get_country("AAA").energy
	assert_almost_eq(float(energy.output["coal"]), 100.0, 0.5, "un mois de croissance de la demande")
	assert_eq(energy.blackout, 0.0)
	assert_almost_eq(float(energy.fuel_factor["coal"]), 1.0, 0.01)
	assert_gt(float(state.get_country("AAA").resources.power_share["coal"]), 0.0, "charbon brûlé dans les centrales")
	assert_gt(EnergySystem.building_count(state, "1", "coal_plant"), 0, "parc de départ placé")
	assert_eq(EnergySystem.building_count(state, "1", "mine"), 1, "mine sur le charbon")
	assert_eq(EnergySystem.building_count(state, "1", "port"), 1, "port côtier")


func test_player_without_construction_gets_blackouts() -> void:
	var state := _world()
	var system := EnergySystem.new()
	state.get_country("AAA").economy.growth = 10.0
	for month: int in 240:
		system.on_month(state)
	assert_gt(state.get_country("AAA").energy.blackout, 0.0)
	assert_lt(state.get_country("AAA").economy.energy_growth, 0.0)
	assert_eq(state.get_country("BBB").energy.blackout, 0.0, "l'IA construit")


func test_build_requirements() -> void:
	var state := _world()
	assert_eq(BuildCommand.new(&"AAA", "port", "1").refusal_reason(state), "", "un port de départ, deux au maximum")
	BuildCommand.new(&"AAA", "port", "1").execute(state)
	assert_eq(BuildCommand.new(&"AAA", "port", "1").refusal_reason(state), "BUILD_REFUSED_FULL", "chantier compté")
	assert_eq(BuildCommand.new(&"AAA", "hydro_dam", "1").refusal_reason(state), "BUILD_REFUSED_TERRAIN")
	assert_eq(BuildCommand.new(&"AAA", "hydro_dam", "2").refusal_reason(state), "")
	assert_eq(BuildCommand.new(&"AAA", "refinery", "2").refusal_reason(state), "BUILD_REFUSED_COASTAL")
	assert_eq(BuildCommand.new(&"AAA", "mine", "2").refusal_reason(state), "BUILD_REFUSED_RESOURCE")
	assert_eq(BuildCommand.new(&"AAA", "factory", "3").refusal_reason(state), "BUILD_REFUSED_NOT_OURS")
	assert_eq(BuildCommand.new(&"AAA", "unknown", "1").refusal_reason(state), "BUILD_REFUSED_UNKNOWN")


func test_construction_is_paid_then_delivered() -> void:
	var state := _world()
	var command := BuildCommand.new(&"AAA", "wind_farm", "1")
	assert_true(command.can_execute(state))
	command.execute(state)
	var economy := state.get_country("AAA").economy
	var capacity_before := float(state.get_country("AAA").energy.capacity.get("wind", 0.0))
	EnergySystem.advance_projects(state)
	assert_gt(economy.project_spending, 0.0, "chantier payé par le budget")
	for month: int in int(_buildings["wind_farm"]["build_months"]):
		EnergySystem.advance_projects(state)
	assert_true(state.projects.is_empty())
	assert_almost_eq(float(state.get_country("AAA").energy.capacity["wind"]),
		capacity_before + float(_buildings["wind_farm"]["capacity_gw"]), 0.0001)
	assert_eq(economy.project_spending, 0.0, "plus de dépense")
	assert_eq(state.events.back()["type"], EnergySystem.EVENT_PROJECT_DONE)


func test_factory_and_mine_add_output() -> void:
	var state := _world()
	var country := state.get_country("AAA")
	var gdp := country.economy.real_gdp
	EnergySystem.complete_building(state, "AAA", "factory", "1")
	assert_almost_eq(country.economy.real_gdp, gdp + float(_buildings["factory"]["output_billion"]), 0.0001)
	var total := 0.0
	for share: Variant in country.economy.sectors.values():
		total += float(share)
	assert_almost_eq(total, 1.0, 0.0001)
	var coal := float(country.resources.production_base["coal"])
	EnergySystem.complete_building(state, "AAA", "mine", "1")
	assert_almost_eq(float(country.resources.production_base["coal"]), coal + 10.0, 0.0001)


func test_cancel_project() -> void:
	var state := _world()
	BuildCommand.new(&"AAA", "factory", "1").execute(state)
	var project_id := int(state.projects[0]["id"])
	assert_false(CancelProjectCommand.new(&"BBB", project_id).can_execute(state), "pas son chantier")
	var cancel := CancelProjectCommand.new(&"AAA", project_id)
	assert_true(cancel.can_execute(state))
	cancel.execute(state)
	assert_true(state.projects.is_empty())

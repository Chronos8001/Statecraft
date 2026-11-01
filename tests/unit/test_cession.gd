extends GutTest
## Cessions : transfert de la population, du PIB, de l'électricité (centrales), des ressources et de la
## circonscription ; frontières, revendications, carte et constructions suivent le nouveau propriétaire.

const DEFINES_PATH := "res://data/defines.json"
const WAR_GOALS_PATH := "res://data/war_goals/war_goals.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
## AAA 1-2-3 | BBB 4-5 (4 : 2 millions d'habitants et du pétrole), CCC 6 voisin de 5.
const PROVINCES := {
	"1": {"owner": "AAA", "controller": "AAA", "neighbors": [2], "center": [180.0, 90.0], "population": 4000000},
	"2": {"owner": "AAA", "controller": "AAA", "neighbors": [1, 3], "center": [181.0, 90.0], "population": 3000000},
	"3": {"owner": "AAA", "controller": "AAA", "neighbors": [2, 4], "center": [182.0, 90.0], "population": 3000000},
	"4": {"owner": "BBB", "controller": "BBB", "neighbors": [3, 5], "center": [183.0, 90.0], "population": 2000000,
		"resources": {"oil": 1}},
	"5": {"owner": "BBB", "controller": "BBB", "neighbors": [4, 6], "center": [184.0, 90.0], "population": 8000000,
		"resources": {"oil": 1}},
	"6": {"owner": "CCC", "controller": "CCC", "neighbors": [5], "center": [185.0, 90.0], "population": 600},
}
const BUILDINGS := {"gas_plant": {"source": "gas", "capacity_gw": 0.8}}

var _defines: Dictionary
var _goals: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))
	_goals = JSON.parse_string(FileAccess.get_file_as_string(WAR_GOALS_PATH))


func _country() -> Dictionary:
	var branches := {"land": {"share": 0.7, "level": 3.0, "training": 54.0, "morale": 60.0},
		"air": {"share": 0.3, "level": 3.0, "training": 54.0, "morale": 60.0}}
	return {"population": 10000000, "currency": "usd", "regime": "parliamentary_republic", "capital": 1,
		"economy": {"gdp_billion_usd": 500.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0},
		"military": {"active_personnel": 400000, "reserve_personnel": 100000},
		"armed_forces": {"branches": branches, "special": {"special_forces": 50, "missiles": 40, "cyber": 30},
			"nuclear_warheads": 0}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(9, GameDate.new(2026, 1, 1), &"AAA")
	var countries := {"AAA": _country(), "BBB": _country(), "CCC": _country()}
	WorldSetup.populate(state, countries, CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": {"military": {"influence": 1.0, "affinity": {}, "reactions": {"unemployment": 0.0, "inflation": 0.0,
			"growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}},
			"regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}}, "ideologies": {},
			"settings": _defines["society"]},
		{}, {"settings": _defines["diplomacy"], "treaties": {}, "start": {}, "organizations": {},
			"organization_rules": {}, "sanctions": {}, "aid": {}},
		{"settings": _defines["military"], "war_goals": _goals})
	state.energy_definitions["provinces"] = PROVINCES
	state.energy_definitions["buildings"] = BUILDINGS
	state.politics_definitions["provinces"] = {"AAA": [["1", 4000000, 1.0], ["2", 3000000, 1.0], ["3", 3000000, 1.0]],
		"BBB": [["4", 2000000, 1.0], ["5", 8000000, 1.0]]}
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	EnergySystem.add_building(state, "4", "gas_plant", 1)
	state.get_country("BBB").energy.capacity["gas"] = 0.8
	state.get_country("BBB").resources.production_base["oil"] = 10.0
	return state


func test_cession_transfers_people_and_economy() -> void:
	var state := _world()
	var giver := state.get_country("BBB")
	var taker := state.get_country("AAA")
	var gdp := giver.economy.real_gdp
	var taker_gdp := taker.economy.real_gdp
	WarEnd.cede(state, "4", "AAA")
	assert_eq(giver.economy.population, 8000000, "20 % de la population part")
	assert_eq(taker.economy.population, 12000000)
	assert_almost_eq(giver.economy.real_gdp, gdp * 0.8, 0.001, "avec sa part du PIB")
	assert_almost_eq(taker.economy.real_gdp, taker_gdp + gdp * 0.2, 0.001)
	assert_almost_eq(float(giver.energy.capacity["gas"]), 0.0, 0.0001, "la centrale change de réseau")
	assert_almost_eq(float(taker.energy.capacity.get("gas", 0.0)), 0.8, 0.0001)
	assert_almost_eq(float(giver.resources.production_base["oil"]), 5.0, 0.0001, "moitié du pétrole (2 provinces)")
	assert_almost_eq(float(taker.resources.production_base["oil"]), 5.0, 0.0001)


func test_cession_moves_districts_borders_and_claims() -> void:
	var state := _world()
	WarEnd.cede(state, "4", "AAA")
	var lists: Dictionary = state.politics_definitions["provinces"]
	assert_eq((lists["BBB"] as Array).size(), 1, "la circonscription quitte BBB")
	assert_true((lists["AAA"] as Array).any(func(entry: Array) -> bool: return str(entry[0]) == "4"))
	assert_true(state.border_provinces.has("4"), "4 est maintenant une province frontalière de AAA")
	assert_false(state.border_provinces.has("3"), "3 n'est plus à la frontière")
	assert_true((state.land_neighbors["AAA"] as Dictionary).has("BBB"))
	assert_eq(TensionSystem.adjacent_provinces(state, "BBB", "AAA", PROVINCES), ["4"], "BBB voit 4 comme province voisine de AAA")
	assert_true(TensionSystem.is_claimed_by(state, "BBB", "4"), "territoire perdu revendiqué")
	assert_eq(BuildCommand.new(&"AAA", "gas_plant", "4").refusal_reason(state) != "BUILD_REFUSED_NOT_OURS", true,
		"le nouveau propriétaire peut construire")


func test_map_context_follows_cessions() -> void:
	var state := _world()
	var context := MapModeContext.new()
	context.provinces = PROVINCES
	context.data_provinces = PROVINCES
	context.countries = {"AAA": {"color": "#FF0000"}, "BBB": {"color": "#0000FF"}}
	context.refresh_from_simulation(state)
	assert_eq(str((context.provinces["4"] as Dictionary)["owner"]), "BBB")
	WarEnd.cede(state, "4", "AAA")
	context.refresh_from_simulation(state)
	assert_eq(str((context.provinces["4"] as Dictionary)["owner"]), "AAA", "la carte suit la cession")
	assert_eq(str((PROVINCES["4"] as Dictionary)["owner"]), "BBB", "les données ne sont pas modifiées")

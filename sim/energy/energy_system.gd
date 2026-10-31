class_name EnergySystem
extends SimSystem
## Électricité et chantiers, une fois par mois, avant les ressources :
##   1. chantiers : coût du mois, bâtiments achevés (capacités, production, mines, demande) ;
##   2. pays de l'IA : nouvelles centrales pour garder une marge sur la demande prévue (règle provisoire) ;
##   3. demande, production par source, coupures, combustible consommé par les centrales.

const PRIORITY := -30
const EVENT_PROJECT_DONE := &"project_done"
const EVENT_BLACKOUT := &"blackout"
const BLACKOUT_ALERT := 0.01


func get_id() -> StringName:
	return &"energy"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.energy_definitions.is_empty():
		return
	advance_projects(state)
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		if tag != str(state.player_tag):
			expand_ai_capacity(country, state)
		update_energy(country, state)


## Paie les chantiers du mois et livre ceux qui sont terminés.
static func advance_projects(state: SimState) -> void:
	var spending: Dictionary = {}
	var finished: Array[Dictionary] = []
	for project: Dictionary in state.projects:
		var tag := str(project["tag"])
		spending[tag] = float(spending.get(tag, 0.0)) + float(project["monthly_cost"])
		project["months_left"] = int(project["months_left"]) - 1
		if int(project["months_left"]) <= 0:
			finished.append(project)
	for project: Dictionary in finished:
		state.projects.erase(project)
		complete_building(state, str(project["tag"]), str(project["building"]), str(project["province"]))
		state.add_event(EVENT_PROJECT_DONE, str(project["tag"]), {"building": project["building"],
			"province": project["province"]})
	for tag: String in state.countries.keys():
		var economy := (state.countries[tag] as CountryState).economy
		var gdp := TradeSystem.current_gdp(state, tag)
		var monthly := float(spending.get(tag, 0.0))
		economy.project_spending = monthly * EconomyModel.MONTHS_PER_YEAR / gdp * EconomyModel.PERCENT if gdp > 0.0 else 0.0


## Effets d'un bâtiment achevé : capacité électrique, production d'un secteur, extraction d'une mine,
## consommation d'électricité.
static func complete_building(state: SimState, tag: String, building_id: String, province_id: String) -> void:
	var country := state.get_country(tag)
	var definition: Dictionary = (state.energy_definitions.get("buildings", {}) as Dictionary).get(building_id, {})
	if country == null or definition.is_empty():
		return
	add_building(state, province_id, building_id, 1)
	var energy := country.energy
	if definition.has("source"):
		var source := str(definition["source"])
		energy.capacity[source] = float(energy.capacity.get(source, 0.0)) + float(definition.get("capacity_gw", 0.0))
	energy.demand += float(definition.get("electricity_twh", 0.0))
	var output := float(definition.get("output_billion", 0.0))
	var sector := str(definition.get("sector", ""))
	if bool(definition.get("requires_resource", false)):
		var resource_id := mine_resource(state, province_id)
		var market: MarketState = state.markets.get(resource_id)
		var amount := float((state.energy_definitions.get("mine_outputs", {}) as Dictionary).get(resource_id, 0.0))
		if market != null and amount > 0.0:
			country.resources.production_base[resource_id] = float(country.resources.production_base.get(resource_id, 0.0)) \
				+ amount
			output += amount * market.unit_value
			sector = "energy" if ["oil", "gas", "coal", "uranium"].has(resource_id) else "industry"
	if output > 0.0:
		add_output(country.economy, sector, output)


## Ajoute de la production (milliards de dollars de 2026 par an) à un secteur.
static func add_output(economy: EconomyState, sector: String, output: float) -> void:
	var total := economy.real_gdp
	var sectors := economy.sectors
	var new_total := total + output
	for sector_id: Variant in sectors.keys():
		sectors[sector_id] = float(sectors[sector_id]) * total / new_total
	sectors[sector] = float(sectors.get(sector, 0.0)) + output / new_total
	economy.real_gdp = new_total


## Ressource exploitable la plus riche d'une province ("" s'il n'y en a pas).
static func mine_resource(state: SimState, province_id: String) -> String:
	var province: Dictionary = (state.energy_definitions.get("provinces", {}) as Dictionary).get(province_id, {})
	var outputs: Dictionary = state.energy_definitions.get("mine_outputs", {})
	var best := ""
	var best_richness := 0
	var resources: Dictionary = province.get("resources", {})
	for resource_id: Variant in resources.keys():
		if outputs.has(resource_id) and int(resources[resource_id]) > best_richness:
			best = str(resource_id)
			best_richness = int(resources[resource_id])
	return best


static func add_building(state: SimState, province_id: String, building_id: String, count: int) -> void:
	var buildings: Dictionary = state.buildings.get(province_id, {})
	buildings[building_id] = int(buildings.get(building_id, 0)) + count
	state.buildings[province_id] = buildings


static func building_count(state: SimState, province_id: String, building_id: String) -> int:
	return int((state.buildings.get(province_id, {}) as Dictionary).get(building_id, 0))


## Règle de l'IA : si la production maximale ne couvre plus la demande prévue avec la marge visée,
## de nouvelles capacités s'ajoutent, selon le niveau de revenu (nucléaire et hydraulique seulement là
## où ils existent déjà). Ces constructions font partie des dépenses d'infrastructure du budget.
static func expand_ai_capacity(country: CountryState, state: SimState) -> void:
	var settings: Dictionary = state.energy_definitions.get("settings", {})
	var sources: Dictionary = state.energy_definitions.get("sources", {})
	var energy := country.energy
	var economy := country.economy
	var growth := float(settings.get("demand_income_elasticity", 0.0)) * economy.growth + float(settings.get("demand_trend", 0.0))
	var expected := energy.demand * pow(1.0 + growth / EconomyModel.PERCENT,
		float(settings.get("ai_horizon_months", 0)) / EconomyModel.MONTHS_PER_YEAR)
	var currency := state.get_currency(economy.currency)
	var rich := currency != null and economy.gdp_per_capita_usd(currency) >= float(settings.get("ai_rich_gdp_per_capita", 0.0))
	var weights: Dictionary = {}
	for source_id: String in sources.keys():
		var source: Dictionary = sources[source_id]
		if bool(source.get("requires_existing", false)) and float(energy.capacity.get(source_id, 0.0)) <= 0.0:
			continue
		weights[source_id] = float((source.get("ai_weights", {}) as Dictionary).get("rich" if rich else "other", 0.0))
	var added := EnergyModel.expansion(energy.max_supply, expected, float(settings.get("ai_target_margin", 1.0)), weights,
		sources, float(settings.get("hours_per_year", 0.0)))
	for source_id: Variant in added.keys():
		energy.capacity[source_id] = float(energy.capacity.get(source_id, 0.0)) + float(added[source_id])


static func update_energy(country: CountryState, state: SimState) -> void:
	var settings: Dictionary = state.energy_definitions.get("settings", {})
	var sources: Dictionary = state.energy_definitions.get("sources", {})
	var energy := country.energy
	var economy := country.economy
	energy.demand *= 1.0 + (float(settings.get("demand_income_elasticity", 0.0)) * economy.growth
		+ float(settings.get("demand_trend", 0.0))) / EconomyModel.PERCENT / EconomyModel.MONTHS_PER_YEAR
	var shortages: Dictionary = {}
	for source_id: Variant in energy.capacity.keys():
		var fuel: Dictionary = (sources.get(source_id, {}) as Dictionary).get("fuel", {})
		if not fuel.is_empty():
			shortages[source_id] = float(country.resources.shortage.get(str(fuel["resource"]), 0.0))
	var result := EnergyModel.dispatch(energy.capacity, energy.demand, sources, shortages,
		float(settings.get("hours_per_year", 0.0)))
	var was_dark := energy.blackout >= BLACKOUT_ALERT
	energy.output = result["output"]
	energy.max_supply = float(result["max_supply"])
	energy.blackout = float(result["blackout"])
	if energy.blackout >= BLACKOUT_ALERT and not was_dark:
		state.add_event(EVENT_BLACKOUT, country.tag, {"share": energy.blackout})
	energy.fuel_factor.clear()
	for source_id: Variant in energy.output.keys():
		var fuel: Dictionary = (sources.get(source_id, {}) as Dictionary).get("fuel", {})
		var start := float(energy.start_output.get(source_id, 0.0))
		if fuel.is_empty() or start <= 0.0:
			continue
		energy.fuel_factor[str(fuel["resource"])] = float(energy.output[source_id]) / start
	var limit := float(settings.get("max_economic_effect", INF))
	economy.energy_growth = clampf(-float(settings.get("blackout_growth_penalty", 0.0)) * energy.blackout, -limit, limit)

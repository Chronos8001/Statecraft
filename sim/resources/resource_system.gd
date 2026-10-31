class_name ResourceSystem
extends SimSystem
## Marché mondial des ressources, une fois par mois, avant le budget et l'économie :
##   1. exportations bloquées par les détroits fermés ;
##   2. capacités et besoins de chaque pays (tendances, croissance) ;
##   3. prix d'équilibre de chaque ressource (le prix du marché s'en rapproche peu à peu) ;
##   4. effets sur chaque pays : gains ou pertes des exportateurs, coût pour les consommateurs,
##      pénuries dans les chaînes d'approvisionnement, prix des ressources pour les taxes.

const PRIORITY := -20
const EVENT_STRAIT_CLOSED := &"strait_closed"
const EVENT_STRAIT_OPENED := &"strait_opened"


func get_id() -> StringName:
	return &"resources"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.markets.is_empty():
		return
	var settings: Dictionary = state.resource_definitions.get("settings", {})
	var tags: Array = state.countries.keys()
	tags.sort()
	update_blocked_shares(state, tags)
	for tag: String in tags:
		_grow_bases(state.countries[tag], state)
	var ids: Array = state.markets.keys()
	ids.sort()
	for resource_id: String in ids:
		clear_market(state.markets[resource_id], state, tags, settings)
	for tag: String in tags:
		apply_effects(state.countries[tag], state, settings)


## Part des exportations de chaque pays qui passe par un détroit fermé (cumulée, au plus 1).
static func update_blocked_shares(state: SimState, tags: Array) -> void:
	var trade: Dictionary = state.resource_definitions.get("straits", {})
	for tag: String in tags:
		(state.countries[tag] as CountryState).resources.blocked_share.clear()
	for strait_id: Variant in state.closed_straits.keys():
		var routes: Dictionary = (trade.get(strait_id, {}) as Dictionary).get("trade", {})
		for resource_id: Variant in routes.keys():
			var shares: Dictionary = routes[resource_id]
			for tag: Variant in shares.keys():
				var country := state.get_country(str(tag))
				if country == null:
					continue
				var blocked := country.resources.blocked_share
				blocked[resource_id] = minf(float(blocked.get(resource_id, 0.0)) + float(shares[tag]), 1.0)


static func _grow_bases(country: CountryState, state: SimState) -> void:
	var resources := country.resources
	var growth := country.economy.growth
	for resource_id: Variant in resources.production_base.keys():
		var market: MarketState = state.markets.get(resource_id)
		if market == null:
			continue
		resources.production_base[resource_id] = float(resources.production_base[resource_id]) \
			* (1.0 + market.supply_trend / EconomyModel.PERCENT / EconomyModel.MONTHS_PER_YEAR)
		resources.consumption_base[resource_id] = float(resources.consumption_base[resource_id]) \
			* (1.0 + (market.demand_trend + market.income_elasticity * growth) / EconomyModel.PERCENT \
			/ EconomyModel.MONTHS_PER_YEAR)


## Prix du mois et quantités de chaque pays à ce prix.
static func clear_market(market: MarketState, state: SimState, tags: Array, settings: Dictionary) -> void:
	var entries: Array = []
	var countries: Array[CountryResources] = []
	for tag: String in tags:
		var resources: CountryResources = (state.countries[tag] as CountryState).resources
		var capacity := float(resources.production_base.get(market.resource_id, 0.0))
		var needs := float(resources.consumption_base.get(market.resource_id, 0.0))
		if capacity <= 0.0 and needs <= 0.0:
			continue
		entries.append({"capacity": capacity, "needs": needs,
			"blocked": float(resources.blocked_share.get(market.resource_id, 0.0))})
		countries.append(resources)
	var bounds: Array = settings.get("price_bounds", [0.1, 10.0])
	var target := ResourceModel.equilibrium_ratio(entries, market, bounds, int(settings.get("solver_iterations", 30)))
	market.price += (target * market.base_price - market.price) * float(settings.get("price_adjustment", 1.0))
	var ratio := market.price_ratio()
	market.supply = 0.0
	market.demand = 0.0
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		var resources := countries[index]
		var produced := ResourceModel.available_supply(float(entry["capacity"]), float(entry["needs"]), ratio, market,
			float(entry["blocked"]))
		var used := ResourceModel.demand(float(entry["needs"]), ratio, market.demand_elasticity)
		resources.production[market.resource_id] = produced
		resources.consumption[market.resource_id] = used
		resources.shortage[market.resource_id] = ResourceModel.shortage(ratio, market.demand_elasticity)
		market.supply += produced
		market.demand += used


## Effets des prix sur l'économie du pays, mesurés par rapport à une situation normale
## (prix de départ, rien de bloqué) : neutres au départ.
static func apply_effects(country: CountryState, state: SimState, settings: Dictionary) -> void:
	var economy := country.economy
	var resources := country.resources
	var currency := state.get_currency(economy.currency)
	var gdp := economy.gdp_usd(currency) if currency != null else 0.0
	if gdp <= 0.0:
		return
	var windfall := 0.0
	var cost := 0.0
	var produced_value := 0.0
	var capacity_value := 0.0
	for resource_id: Variant in resources.production.keys():
		var market: MarketState = state.markets.get(resource_id)
		if market == null:
			continue
		var ratio := market.price_ratio()
		var produced := float(resources.production[resource_id])
		var used := float(resources.consumption.get(resource_id, 0.0))
		var capacity := float(resources.production_base.get(resource_id, 0.0))
		var needs := float(resources.consumption_base.get(resource_id, 0.0))
		windfall += ((produced - used) * ratio - (capacity - needs)) * market.unit_value
		cost += used * (ratio - 1.0) * market.unit_value
		produced_value += produced * ratio * market.unit_value
		capacity_value += capacity * market.unit_value
	var limit := float(settings.get("max_economic_effect", INF))
	var growth := float(settings.get("terms_of_trade_effect", 0.0)) * windfall / gdp * EconomyModel.PERCENT \
		- supply_chain_penalty(economy, resources, state, settings)
	economy.resource_growth = clampf(growth, -limit, limit)
	economy.resource_inflation = clampf(float(settings.get("cost_passthrough", 0.0)) * cost / gdp * EconomyModel.PERCENT,
		-limit, limit)
	economy.resource_price_index = produced_value / capacity_value if capacity_value > 0.0 else 1.0


## Frein à la croissance : chaque secteur souffre des pénuries des ressources dont il dépend.
static func supply_chain_penalty(economy: EconomyState, resources: CountryResources, state: SimState,
		settings: Dictionary) -> float:
	var sectors: Dictionary = state.resource_definitions.get("sectors", {})
	var penalty := 0.0
	for sector_id: Variant in economy.sectors.keys():
		var inputs: Dictionary = (sectors.get(sector_id, {}) as Dictionary).get("inputs", {})
		var exposure := 0.0
		for resource_id: Variant in inputs.keys():
			exposure += float(inputs[resource_id]) * float(resources.shortage.get(resource_id, 0.0))
		penalty += float(economy.sectors[sector_id]) * exposure
	return penalty * float(settings.get("supply_chain_penalty", 0.0))

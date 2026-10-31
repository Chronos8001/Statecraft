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
	add_embargo_blocks(state)
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


## Embargos : l'exportateur visé perd les achats du pays qui l'impose (part des importations nettes
## mondiales), sauf ce qui est revendu ailleurs ; le pays qui l'impose garde une prime et une pénurie
## pour la part de ses achats qui venait de ce fournisseur (embargo_premiums).
static func add_embargo_blocks(state: SimState) -> void:
	var trade := state.trade
	var settings := state.trade_settings
	var resale := float(settings.get("resale_share", 0.0))
	for tag: String in state.countries.keys():
		(state.countries[tag] as CountryState).resources.embargo_premium.clear()
	if trade.embargoes.is_empty():
		return
	var world_imports: Dictionary = {}
	for country: CountryState in state.countries.values():
		for resource_id: Variant in country.resources.consumption_base.keys():
			var net := float(country.resources.consumption_base[resource_id]) \
				- float(country.resources.production_base.get(resource_id, 0.0))
			if net > 0.0:
				world_imports[resource_id] = float(world_imports.get(resource_id, 0.0)) + net
	for source: String in trade.embargoes.keys():
		var importer := state.get_country(source)
		if importer == null:
			continue
		for target: String in (trade.embargoes[source] as Dictionary).keys():
			var exporter := state.get_country(target)
			if exporter == null:
				continue
			for resource_id: String in state.markets.keys():
				if not trade.is_embargoed(source, target, resource_id):
					continue
				var net_imports := float(importer.resources.consumption_base.get(resource_id, 0.0)) \
					- float(importer.resources.production_base.get(resource_id, 0.0))
				if net_imports <= 0.0 or float(world_imports.get(resource_id, 0.0)) <= 0.0:
					continue
				var lost := net_imports / float(world_imports[resource_id]) * (1.0 - resale)
				var blocked := exporter.resources.blocked_share
				blocked[resource_id] = minf(float(blocked.get(resource_id, 0.0)) + lost, 1.0)
				var share := float(TradeModel.supplier_shares(state, source, resource_id, false).get(target, 0.0))
				var premium := importer.resources.embargo_premium
				premium[resource_id] = minf(float(premium.get(resource_id, 0.0)) + share, 1.0)


static func _grow_bases(country: CountryState, state: SimState) -> void:
	var resources := country.resources
	var growth := country.economy.growth
	var response := float((state.resource_definitions.get("settings", {}) as Dictionary).get("long_run_supply_response", 0.0))
	for resource_id: Variant in resources.production_base.keys():
		var market: MarketState = state.markets.get(resource_id)
		if market == null:
			continue
		# À long terme, l'offre suit le prix : des prix durablement hauts attirent l'investissement, des prix
		# bas le découragent.
		var trend := market.supply_trend + response * log(maxf(market.price_ratio(), 0.01))
		resources.production_base[resource_id] = float(resources.production_base[resource_id]) \
			* (1.0 + trend / EconomyModel.PERCENT / EconomyModel.MONTHS_PER_YEAR)
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
		var needs := resources.needs(market.resource_id, (state.countries[tag] as CountryState).energy.fuel_factor)
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
		var embargo_share := float(resources.embargo_premium.get(market.resource_id, 0.0))
		resources.shortage[market.resource_id] = minf(ResourceModel.shortage(ratio, market.demand_elasticity)
			+ embargo_share * float(state.trade_settings.get("embargo_premium", 0.0)), 1.0)
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
		# Payer plus cher les fournisseurs restants quand on boycotte une partie des siens.
		var premium := float(resources.embargo_premium.get(resource_id, 0.0)) \
			* float(state.trade_settings.get("embargo_premium", 0.0))
		cost += used * ((ratio - 1.0) + ratio * premium) * market.unit_value
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

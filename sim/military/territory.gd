class_name Territory
extends RefCounted
## Transfert complet d'une province cédée : population, part du PIB (selon la population et le niveau de vie du
## cédant), demande d'électricité, centrales (capacité), mines et ressources de la province (part de la
## production nationale selon le poids de la province), circonscriptions électorales. La dette reste au cédant.
## Les frontières terrestres (voisins, provinces frontalières) sont recalculées.

## Part de la population qu'un pays peut perdre en une seule cession (garde-fou).
const MAX_SHARE := 0.9


static func transfer(state: SimState, province_id: String, from: String, to: String) -> void:
	var giver := state.get_country(from)
	var taker := state.get_country(to)
	if giver == null or taker == null:
		return
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var province: Dictionary = provinces.get(province_id, {})
	var population := float(province.get("population", 0))
	var share := minf(population / maxf(float(giver.economy.population), 1.0), MAX_SHARE)
	# Population et PIB.
	var moved_people := int(float(giver.economy.population) * share)
	giver.economy.population -= moved_people
	taker.economy.population += moved_people
	var gdp := giver.economy.real_gdp * share
	giver.economy.real_gdp -= gdp
	taker.economy.real_gdp += gdp
	var demand := giver.energy.demand * share
	giver.energy.demand -= demand
	taker.energy.demand += demand
	_move_resources(state, province_id, province, giver, taker)
	_move_buildings(state, province_id, giver, taker)
	_move_districts(state, province_id, from, to)


## Ressources de la province : part de la production du cédant selon le poids de la province parmi les siennes.
static func _move_resources(state: SimState, province_id: String, province: Dictionary, giver: CountryState,
		taker: CountryState) -> void:
	var weights: Dictionary = province.get("resources", {})
	if weights.is_empty():
		return
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	for resource_id: Variant in weights.keys():
		var total := 0.0
		for owned: Variant in state.provinces_by_owner.get(giver.tag, []):
			total += float(((provinces.get(str(owned), {}) as Dictionary).get("resources", {}) as Dictionary).get(resource_id, 0.0))
		total += float(weights[resource_id])
		var part := float(weights[resource_id]) / total if total > 0.0 else 0.0
		var amount := float(giver.resources.production_base.get(resource_id, 0.0)) * part
		if amount <= 0.0:
			continue
		giver.resources.production_base[resource_id] = float(giver.resources.production_base[resource_id]) - amount
		taker.resources.production_base[resource_id] = float(taker.resources.production_base.get(resource_id, 0.0)) + amount


## Centrales de la province : leur capacité change de réseau électrique.
static func _move_buildings(state: SimState, province_id: String, giver: CountryState, taker: CountryState) -> void:
	var definitions: Dictionary = state.energy_definitions.get("buildings", {})
	for building_id: Variant in (state.buildings.get(province_id, {}) as Dictionary).keys():
		var definition: Dictionary = definitions.get(building_id, {})
		if not definition.has("source"):
			continue
		var source := str(definition["source"])
		var capacity := float(definition.get("capacity_gw", 0.0)) * EnergySystem.building_count(state, province_id, str(building_id))
		giver.energy.capacity[source] = maxf(float(giver.energy.capacity.get(source, 0.0)) - capacity, 0.0)
		taker.energy.capacity[source] = float(taker.energy.capacity.get(source, 0.0)) + capacity


## Circonscription de la province : elle vote désormais chez le nouveau propriétaire.
static func _move_districts(state: SimState, province_id: String, from: String, to: String) -> void:
	var lists: Dictionary = state.politics_definitions.get("provinces", {})
	var source: Array = lists.get(from, [])
	for index: int in source.size():
		var entry: Array = source[index]
		if str(entry[0]) != province_id:
			continue
		source.remove_at(index)
		if not lists.has(to):
			lists[to] = []
		(lists[to] as Array).append(entry)
		return

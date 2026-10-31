class_name EnergyModel
extends RefCounted
## Formules de l'électricité, sans état.
##
## Les sources non pilotables (renouvelables, nucléaire) produisent à leur facteur de charge habituel ;
## les centrales pilotables (charbon, gaz, pétrole) couvrent le reste de la demande, au prorata de leur
## production habituelle, dans la limite de leur facteur de charge maximal (moins les pénuries de
## combustible). Ce qui manque est coupé.

const GW_TWH := 1000.0
## Part de la demande en dessous de laquelle on ne parle pas de coupure (arrondis).
const BLACKOUT_EPSILON := 0.0001


## Production annuelle (TWh) d'une capacité (GW) à un facteur de charge.
static func twh(capacity_gw: float, capacity_factor: float, hours: float) -> float:
	return capacity_gw * capacity_factor * hours / GW_TWH


## Capacité (GW) nécessaire pour produire une quantité (TWh) à un facteur de charge.
static func capacity_for(output_twh: float, capacity_factor: float, hours: float) -> float:
	return output_twh * GW_TWH / (capacity_factor * hours) if capacity_factor > 0.0 else 0.0


## Production de chaque source pour une demande. fuel_shortage : source → part du combustible manquante.
## Renvoie {output: {source: TWh}, max_supply, blackout}.
static func dispatch(capacity: Dictionary, demand: float, sources: Dictionary, fuel_shortage: Dictionary,
		hours: float) -> Dictionary:
	var output: Dictionary = {}
	var base := 0.0
	var weights: Dictionary = {}
	var limits: Dictionary = {}
	for source_id: Variant in capacity.keys():
		var source: Dictionary = sources.get(source_id, {})
		var gw := float(capacity[source_id])
		var usual := twh(gw, float(source.get("capacity_factor", 0.0)), hours)
		if bool(source.get("dispatchable", false)):
			weights[source_id] = usual
			limits[source_id] = twh(gw, float(source.get("max_capacity_factor", 0.0)), hours) \
				* (1.0 - clampf(float(fuel_shortage.get(source_id, 0.0)), 0.0, 1.0))
			output[source_id] = 0.0
		else:
			output[source_id] = usual
			base += usual
	var remaining := maxf(demand - base, 0.0)
	# Une passe par source au plus : chaque passe remplit au moins une centrale ou épuise le reste.
	for step: int in weights.size() + 1:
		var open_weight := 0.0
		for source_id: Variant in weights.keys():
			if float(output[source_id]) < float(limits[source_id]):
				open_weight += float(weights[source_id])
		if remaining <= 0.0 or open_weight <= 0.0:
			break
		var allocated := 0.0
		for source_id: Variant in weights.keys():
			var room := float(limits[source_id]) - float(output[source_id])
			if room <= 0.0:
				continue
			var share := minf(remaining * float(weights[source_id]) / open_weight, room)
			output[source_id] = float(output[source_id]) + share
			allocated += share
		remaining -= allocated
	var max_supply := base
	for source_id: Variant in limits.keys():
		max_supply += float(limits[source_id])
	var supplied := 0.0
	for value: Variant in output.values():
		supplied += float(value)
	var blackout := clampf((demand - supplied) / demand, 0.0, 1.0) if demand > 0.0 else 0.0
	if blackout < BLACKOUT_EPSILON:
		blackout = 0.0
	return {"output": output, "max_supply": max_supply, "blackout": blackout}


## Capacités à ajouter (GW par source) pour retrouver la marge visée sur la demande prévue.
## weights : source → poids de la source dans les nouvelles constructions.
static func expansion(max_supply: float, expected_demand: float, target_margin: float, weights: Dictionary,
		sources: Dictionary, hours: float) -> Dictionary:
	var missing := expected_demand * target_margin - max_supply
	var total := 0.0
	for value: Variant in weights.values():
		total += float(value)
	var result: Dictionary = {}
	if missing <= 0.0 or total <= 0.0:
		return result
	for source_id: Variant in weights.keys():
		var source: Dictionary = sources.get(source_id, {})
		var factor := float(source.get("max_capacity_factor", 0.0))
		if float(weights[source_id]) > 0.0 and factor > 0.0:
			result[source_id] = capacity_for(missing * float(weights[source_id]) / total, factor, hours)
	return result

class_name ResourceModel
extends RefCounted
## Formules du marché mondial des ressources, sans état.
##
## Offre d'un pays = capacité × (prix relatif)^élasticité de l'offre, moins ses exportations bloquées ;
## demande = besoins × (prix relatif)^-élasticité de la demande. Le prix d'équilibre égalise l'offre et
## la demande mondiales (recherche par dichotomie sur le logarithme du prix).


static func supply(capacity: float, ratio: float, elasticity: float) -> float:
	return capacity * pow(ratio, elasticity)


static func demand(needs: float, ratio: float, elasticity: float) -> float:
	return needs * pow(ratio, -elasticity)


## Production vendable d'un pays : ses exportations passant par un détroit fermé ne trouvent pas preneur.
static func available_supply(capacity: float, needs: float, ratio: float, market: MarketState,
		blocked_share: float) -> float:
	var produced := supply(capacity, ratio, market.supply_elasticity)
	var exports := maxf(produced - demand(needs, ratio, market.demand_elasticity), 0.0)
	return produced - exports * clampf(blocked_share, 0.0, 1.0)


## Excès d'offre mondiale à un prix relatif donné. entries : [{capacity, needs, blocked}].
static func excess_supply(entries: Array, ratio: float, market: MarketState) -> float:
	var total := 0.0
	for entry: Dictionary in entries:
		total += available_supply(float(entry["capacity"]), float(entry["needs"]), ratio, market,
			float(entry["blocked"])) - demand(float(entry["needs"]), ratio, market.demand_elasticity)
	return total


## Prix relatif d'équilibre (prix / prix de départ), borné.
static func equilibrium_ratio(entries: Array, market: MarketState, bounds: Array, iterations: int) -> float:
	var low := log(float(bounds[0]))
	var high := log(float(bounds[1]))
	for step: int in iterations:
		var middle := (low + high) * 0.5
		if excess_supply(entries, exp(middle), market) > 0.0:
			high = middle
		else:
			low = middle
	return exp((low + high) * 0.5)


## Part des besoins abandonnée à cause du prix (0 si le prix n'est pas plus élevé qu'au départ).
static func shortage(ratio: float, elasticity: float) -> float:
	return clampf(1.0 - pow(maxf(ratio, 1.0), -elasticity), 0.0, 1.0)

class_name EnergyState
extends RefCounted
## Électricité d'un pays : capacités installées par source (GW), production et demande annuelles (TWh).

var capacity: Dictionary = {}
## Production de départ par source (TWh) : référence de la consommation de combustibles.
var start_output: Dictionary = {}
var output: Dictionary = {}
var demand: float = 0.0
## Production maximale possible avec le parc actuel (TWh).
var max_supply: float = 0.0
## Part de la demande non servie (coupures), de 0 à 1.
var blackout: float = 0.0
## Combustible des centrales par rapport au départ (ressource → facteur) : lu par le marché des ressources.
var fuel_factor: Dictionary = {}


func total_output() -> float:
	var total := 0.0
	for value: Variant in output.values():
		total += float(value)
	return total


## Marge de production : production maximale / demande.
func margin() -> float:
	return max_supply / demand if demand > 0.0 else 1.0

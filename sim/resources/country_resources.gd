class_name CountryResources
extends RefCounted
## Ressources d'un pays : capacités de production et besoins (qui suivent les tendances et la croissance),
## quantités du mois au prix du marché, exportations bloquées et pénuries.

## Production et consommation « normales » (au prix de départ), par ressource.
var production_base: Dictionary = {}
var consumption_base: Dictionary = {}
## Quantités du dernier mois au prix du marché.
var production: Dictionary = {}
var consumption: Dictionary = {}
## Part des exportations bloquée par des détroits fermés (0 à 1).
var blocked_share: Dictionary = {}
## Part des besoins non couverte à cause du prix (0 à 1) : lue par les chaînes d'approvisionnement.
var shortage: Dictionary = {}
## Part des achats qui venait de fournisseurs sous embargo (0 à 1), par ressource.
var embargo_premium: Dictionary = {}
var water_renewable: float = 0.0
var water_withdrawal_ratio: float = 0.0


func net_exports(resource_id: String) -> float:
	return float(production.get(resource_id, 0.0)) - float(consumption.get(resource_id, 0.0))


## Production / consommation (1 = autosuffisant) ; -1 si le pays n'en consomme pas.
func self_sufficiency(resource_id: String) -> float:
	var used := float(consumption.get(resource_id, 0.0))
	return float(production.get(resource_id, 0.0)) / used if used > 0.0 else -1.0

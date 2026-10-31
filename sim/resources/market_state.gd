class_name MarketState
extends RefCounted
## Marché mondial d'une ressource : prix, offre et demande mondiales du mois.

var resource_id: String = ""
var base_price: float = 1.0
var price: float = 1.0
## Valeur d'une unité de quantité par an au prix de départ (milliards de dollars).
var unit_value: float = 0.0
var demand_elasticity: float = 0.0
var supply_elasticity: float = 0.0
var income_elasticity: float = 0.0
## Tendances autonomes (% par an), hors effet de la croissance.
var demand_trend: float = 0.0
var supply_trend: float = 0.0
## Offre et demande mondiales du dernier mois (unités de la ressource).
var supply: float = 0.0
var demand: float = 0.0


func price_ratio() -> float:
	return price / base_price if base_price > 0.0 else 1.0

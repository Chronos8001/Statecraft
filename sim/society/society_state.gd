class_name SocietyState
extends RefCounted
## Société d'un pays : poids et satisfaction des groupes sociaux, indicateurs nationaux (0 à 100).
## Les valeurs « start_* » servent de référence : les effets se mesurent par rapport au départ.

## Part de la population de chaque groupe (0 à 1, somme 1).
var group_shares: Dictionary = {}
## Poids politique de chaque groupe (0 à 1, somme 1) : population × influence × régime.
var influence: Dictionary = {}
## Satisfaction de chaque groupe (0 à 100).
var satisfaction: Dictionary = {}
var start_satisfaction: Dictionary = {}
## Bonus temporaires de satisfaction par groupe (promesses de campagne, concessions…), en points.
var bonuses: Dictionary = {}
## Soutien populaire : satisfaction moyenne pondérée par la population.
var support: float = 0.0
var start_support: float = 0.0
var stability: float = 0.0
var start_stability: float = 0.0
var legitimacy: float = 0.0
var start_legitimacy: float = 0.0
var corruption: float = 0.0
var start_corruption: float = 0.0
## Indice de démocratie (0 à 10) au départ.
var democracy_index: float = 0.0
## Situation économique de départ, à laquelle les groupes comparent la situation du moment.
var start_unemployment: float = 0.0
var start_inflation: float = 0.0
var start_growth: float = 0.0


## Satisfaction moyenne pondérée par l'influence des groupes.
func influential_satisfaction() -> float:
	return SocietyModel.weighted(satisfaction, influence)

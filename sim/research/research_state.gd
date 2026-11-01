class_name ResearchState
extends RefCounted
## Recherche d'un pays : technologies connues (au départ et acquises), emplacements de recherche, avancement,
## points du mois et effets cumulés des technologies acquises pendant la partie.

## Technologies connues (id → true) et celles connues dès le départ (leurs effets sont déjà dans les données).
var known: Dictionary = {}
var start_known: Dictionary = {}
## Emplacements : technologie en cours dans chacun ("" : libre).
var slots: Array[String] = []
## Points déjà investis par technologie (gardés si on la retire d'un emplacement).
var progress: Dictionary = {}
## Points de recherche du mois et dépense de R&D de départ (% du PIB), universités classées.
var points: float = 0.0
var rd_share: float = 0.0
var universities: int = 0
## Effets cumulés des technologies acquises : clé d'effet → valeur (growth, research, military:land…).
var effects: Dictionary = {}


func is_known(tech_id: String) -> bool:
	return known.has(tech_id)


func is_researching(tech_id: String) -> bool:
	return slots.has(tech_id)


func effect(key: String) -> float:
	return float(effects.get(key, 0.0))

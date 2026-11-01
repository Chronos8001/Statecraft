class_name MilitaryState
extends RefCounted
## Forces armées agrégées d'un pays : effectifs, branches (terre, air, mer), capacités spéciales, arsenal
## nucléaire et mobilisation. Les valeurs de départ sont gardées : les effets se calculent par rapport à elles.

## Effectifs d'active et de réserve au départ.
var active_personnel: float = 0.0
var reserve_personnel: float = 0.0
## Branche → {share, level, training, morale} (niveau d'équipement 1 à 5, entraînement et moral sur 100).
var branches: Dictionary = {}
var start_branches: Dictionary = {}
## Part du budget d'équipement donnée à chaque branche (somme 1) et part de départ.
var priorities: Dictionary = {}
var start_priorities: Dictionary = {}
## Forces spéciales, missiles et cyber (0 à 100).
var special: Dictionary = {}
var start_special: Dictionary = {}
var nuclear_warheads: int = 0
## Niveau d'alerte nucléaire (0 : normal … 3 : maximal, seul niveau qui permet une frappe) et mois avant de
## pouvoir le changer.
var nuclear_alert: int = 0
var alert_cooldown: int = 0
## Service militaire (loi « conscription ») : option de départ, et facteurs du moment appliqués aux effectifs
## d'active et de réserve de départ (ils rejoignent peu à peu ceux de l'option en vigueur).
var start_conscription: String = ""
var active_factor: float = 1.0
var reserve_factor: float = 1.0
## Mobilisation : 0 (aucune), 1 (partielle), 2 (générale) ; niveau de départ et mois avant de pouvoir changer.
var mobilization: int = 0
var start_mobilization: int = 0
var mobilization_cooldown: int = 0
## Budget d'équipement de départ (milliards de dollars par mois, armes reçues comprises), dépense par
## soldat de départ et stabilité de départ (référence du moral).
var start_equipment: float = 0.0
var start_spend_per_soldier: float = 0.0
var start_stability: float = 0.0
## Coût de l'équipement par rapport au départ (monte chaque année avec les prix et la technologie).
var cost_index: float = 1.0
## Armes reçues déjà comptées (cumul) et flux du mois.
var arms_counted: float = 0.0
var arms_flow: float = 0.0
## Stock de missiles (salves disponibles) et délais des actions ponctuelles (action → mois restants).
var missile_stock: float = 0.0
var action_cooldowns: Dictionary = {}
## Bonus des technologies acquises : niveau d'équipement visé par branche, jauges des capacités spéciales.
var tech_levels: Dictionary = {}
var tech_special: Dictionary = {}
## Pertes au combat pas encore remplacées (soldats), retirées des effectifs d'active.
var losses: float = 0.0
## Calculés chaque mois : puissance militaire et effets de la mobilisation ({growth, stability, groups}).
var power: float = 0.0
var effects: Dictionary = {}


## Effectifs d'active du moment : active (selon le service militaire) + réservistes rappelés au-delà du départ.
func personnel(reserve_share: Array) -> float:
	return maxf(active_personnel * active_factor + reserves() * level_value(reserve_share, mobilization)
		- reserve_personnel * level_value(reserve_share, start_mobilization) - losses, 0.0)


## Réservistes disponibles (selon le service militaire).
func reserves() -> float:
	return reserve_personnel * reserve_factor


func has_branch(branch: String) -> bool:
	return branches.has(branch)


static func level_value(values: Array, level: int) -> float:
	return float(values[clampi(level, 0, values.size() - 1)]) if not values.is_empty() else 0.0

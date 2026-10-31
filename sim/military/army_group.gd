class_name ArmyGroup
extends RefCounted
## Pion « groupe d'armées » : une part des forces terrestres d'un pays, posée sur une province. Il peut se
## déplacer par voie de terre vers une province que son pays contrôle (étapes successives, quelques jours).

var id: int = 0
var owner: String = ""
## Numéro d'ordre dans le pays (1er, 2e groupe d'armées…).
var number: int = 1
var province: String = ""
## Part des forces terrestres du pays (la somme des groupes d'un pays vaut 1).
var share: float = 0.0
## Déplacement : provinces restant à traverser, jours avant la prochaine, destination finale.
var path: Array[String] = []
var days_left: int = 0
var destination: String = ""


func is_moving() -> bool:
	return not path.is_empty()


## Effectifs du groupe : part des forces terrestres actuelles du pays.
func personnel(military: MilitaryState, reserve_share: Array) -> float:
	var land: Dictionary = military.branches.get("land", {})
	return military.personnel(reserve_share) * float(land.get("share", 0.0)) * share

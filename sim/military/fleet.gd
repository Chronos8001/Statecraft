class_name Fleet
extends RefCounted
## Pion « flotte » : une part de la marine d'un pays, dans une zone maritime. Elle se déplace de zone en zone
## (détroits et canaux ouverts compris) et s'abîme au combat (état de 0 à 1), réparée près de ses côtes.

var id: int = 0
var owner: String = ""
## Numéro d'ordre dans le pays (1re, 2e flotte…).
var number: int = 1
var zone: String = ""
## Part de la marine du pays (la somme des flottes d'un pays vaut 1) et état (1 : intacte).
var share: float = 0.0
var condition: float = 1.0
## Déplacement : zones restant à traverser, jours avant la prochaine, destination finale.
var path: Array[String] = []
var days_left: int = 0
var destination: String = ""
## Vrai une fois l'avarie grave signalée (remis à faux après réparation).
var damage_reported: bool = false


func is_moving() -> bool:
	return not path.is_empty()

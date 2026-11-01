class_name War
extends RefCounted
## Une guerre : deux camps (attaquants, défenseurs) menés chacun par un pays, un but de guerre de l'attaquant
## et les provinces qu'il vise. Une guerre civile oppose un pays à sa faction rebelle.

const ATTACKERS := "attackers"
const DEFENDERS := "defenders"

var id: int = 0
## Guerre civile : le défenseur est le pays, l'attaquant sa faction rebelle.
var civil: bool = false
var attackers: Array[String] = []
var defenders: Array[String] = []
var goal: String = ""
var goal_provinces: Array[String] = []
## Date de début (AAAA-MM-JJ) et nombre de jours écoulés depuis.
var start_date: String = ""
var days: int = 0
## Provinces déjà tenues par un camp adverse avant la guerre : id → contrôleur (rendu tel quel à la paix).
var prewar: Dictionary = {}
## Embargos posés par la déclaration (["A>B", …]), levés à la paix.
var embargoes: Array[String] = []


func attacker_leader() -> String:
	return attackers[0] if not attackers.is_empty() else ""


func defender_leader() -> String:
	return defenders[0] if not defenders.is_empty() else ""


func involves(tag: String) -> bool:
	return attackers.has(tag) or defenders.has(tag)


## Camp d'un participant (ATTACKERS, DEFENDERS ou "" s'il n'est pas en guerre).
func side_of(tag: String) -> String:
	if attackers.has(tag):
		return ATTACKERS
	return DEFENDERS if defenders.has(tag) else ""


func members(side: String) -> Array[String]:
	return attackers if side == ATTACKERS else defenders


func enemies_of(tag: String) -> Array[String]:
	var side := side_of(tag)
	if side.is_empty():
		return []
	return defenders if side == ATTACKERS else attackers


static func other_side(side: String) -> String:
	return DEFENDERS if side == ATTACKERS else ATTACKERS


func months() -> float:
	return days / 30.0

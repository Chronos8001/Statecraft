class_name SimSystem
extends RefCounted
## Système de simulation appelé par l'ordonnanceur. Un système déclare les périodes qui
## l'intéressent (get_periods) et implémente les méthodes correspondantes.

const HOURLY := &"hourly"
const DAILY := &"daily"
const WEEKLY := &"weekly"
const MONTHLY := &"monthly"
const YEARLY := &"yearly"


func get_id() -> StringName:
	return &"system"


## Périodes auxquelles le système s'abonne (sous-ensemble de HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY).
func get_periods() -> Array[StringName]:
	return []


## Ordre d'appel au sein d'une même période : les plus petites valeurs passent en premier.
func get_priority() -> int:
	return 0


func on_hour(_state: SimState) -> void:
	pass


func on_day(_state: SimState) -> void:
	pass


func on_week(_state: SimState) -> void:
	pass


func on_month(_state: SimState) -> void:
	pass


func on_year(_state: SimState) -> void:
	pass

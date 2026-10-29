class_name SimScheduler
extends RefCounted
## Ordonnanceur de la simulation. Un tick = une heure de jeu :
##   1. avance la date ;
##   2. appelle les systèmes horaires, puis, si une période se termine, les systèmes
##      quotidiens, hebdomadaires, mensuels et annuels (dans cet ordre) ;
## L'ordre des systèmes est fixe (priorité, puis ordre d'ajout) : la simulation reste déterministe.

var _systems: Dictionary = {
	SimSystem.HOURLY: [],
	SimSystem.DAILY: [],
	SimSystem.WEEKLY: [],
	SimSystem.MONTHLY: [],
	SimSystem.YEARLY: [],
}
var _order: int = 0


func add_system(system: SimSystem) -> void:
	_order += 1
	for period: StringName in system.get_periods():
		if not _systems.has(period):
			GameLog.warn("SimScheduler", "Période inconnue « %s » pour %s." % [period, system.get_id()])
			continue
		var entries: Array = _systems[period]
		entries.append({"system": system, "priority": system.get_priority(), "order": _order})
		entries.sort_custom(_is_before)


func remove_system(system: SimSystem) -> void:
	for period: StringName in _systems.keys():
		_systems[period] = (_systems[period] as Array).filter(
			func(entry: Dictionary) -> bool: return entry["system"] != system)


func get_systems(period: StringName) -> Array[SimSystem]:
	var result: Array[SimSystem] = []
	for entry: Dictionary in _systems.get(period, []):
		result.append(entry["system"])
	return result


## Avance d'une heure. Renvoie les drapeaux GameDate.CHANGED_* des périodes terminées.
func tick(state: SimState) -> int:
	var flags := state.date.advance_hour()
	for system: SimSystem in get_systems(SimSystem.HOURLY):
		system.on_hour(state)
	if flags & GameDate.CHANGED_DAY:
		for system: SimSystem in get_systems(SimSystem.DAILY):
			system.on_day(state)
	if flags & GameDate.CHANGED_WEEK:
		for system: SimSystem in get_systems(SimSystem.WEEKLY):
			system.on_week(state)
	if flags & GameDate.CHANGED_MONTH:
		for system: SimSystem in get_systems(SimSystem.MONTHLY):
			system.on_month(state)
	if flags & GameDate.CHANGED_YEAR:
		for system: SimSystem in get_systems(SimSystem.YEARLY):
			system.on_year(state)
	return flags


static func _is_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["priority"]) != int(b["priority"]):
		return int(a["priority"]) < int(b["priority"])
	return int(a["order"]) < int(b["order"])

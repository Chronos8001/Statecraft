class_name MilitarySystem
extends SimSystem
## Forces armées. Chaque jour : déplacements des groupes d'armées et combats (modules remplaçables). Chaque
## mois, après le budget et avant l'économie : le modèle met à jour chaque armée, puis l'IA militaire décide
## pour les pays qu'elle dirige.

const PRIORITY := -8


func get_id() -> StringName:
	return &"military"


func get_periods() -> Array[StringName]:
	return [DAILY, MONTHLY]


func on_day(state: SimState) -> void:
	if state.military_settings.is_empty():
		return
	state.military.model.update_day(state)
	state.military.resolver.resolve_day(state)


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.military_settings.is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		state.military.model.update_country(country, state)
		if StringName(tag) != state.player_tag:
			state.military.ai.decide_month(country, state)


## Puissance militaire d'un pays (0 sans armée).
static func power(state: SimState, tag: String) -> float:
	var country := state.get_country(tag)
	return country.military.power if country != null and country.military != null else 0.0


## Effets de la mobilisation d'un pays : {growth, stability, groups}.
static func effects(country: CountryState) -> Dictionary:
	return country.military.effects if country.military != null else {}

class_name MilitarySystem
extends SimSystem
## Forces armées. Chaque jour : déplacements des groupes d'armées, durée des guerres et appels aux armes,
## combats sur les fronts et issue des guerres civiles (modules remplaçables). Chaque semaine : l'IA militaire
## répartit ses groupes et choisit ses postures. Chaque mois, après le budget et avant l'économie : le modèle
## met à jour chaque armée (pertes remplacées), puis l'IA militaire décide pour les pays qu'elle dirige.

const PRIORITY := -8


func get_id() -> StringName:
	return &"military"


func get_periods() -> Array[StringName]:
	return [DAILY, WEEKLY, MONTHLY]


func on_day(state: SimState) -> void:
	if state.military_settings.is_empty():
		return
	state.military.model.update_day(state)
	NavalModel.update_day(state)
	WarSystem.update_day(state)
	state.military.resolver.resolve_day(state)
	state.military.naval.resolve_day(state)
	NavalModel.update_blockades(state)
	NavalModel.update_straits(state)
	LandingSystem.update_day(state)
	MilitaryActions.update_day(state)
	WarSystem.check_civil_wars(state)


## Décisions de guerre de l'IA pour les pays en guerre (sauf le joueur) et les factions rebelles.
func on_week(state: SimState) -> void:
	if state.military_settings.is_empty() or state.wars.is_empty():
		return
	FrontSystem.refresh(state)
	var tags: Array = []
	for war: War in state.wars.values():
		for tag: String in war.attackers + war.defenders:
			if not tags.has(tag) and StringName(tag) != state.player_tag:
				tags.append(tag)
	tags.sort()
	for tag: String in tags:
		state.military.ai.decide_week(tag, state)


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.military_settings.is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	state.military.ai.begin_month(state)
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		state.military.model.update_country(country, state)
		if StringName(tag) != state.player_tag:
			state.military.ai.decide_month(country, state)
	WarSystem.update_month(state)
	NavalModel.repair_month(state)
	MilitaryActions.update_month(state)
	NuclearSystem.update_month(state)


## Puissance militaire d'un pays (0 sans armée).
static func power(state: SimState, tag: String) -> float:
	var country := state.get_country(tag)
	return country.military.power if country != null and country.military != null else 0.0


## Effets de la mobilisation d'un pays : {growth, stability, groups}.
static func effects(country: CountryState) -> Dictionary:
	return country.military.effects if country.military != null else {}

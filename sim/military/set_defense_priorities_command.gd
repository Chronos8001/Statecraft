class_name SetDefensePrioritiesCommand
extends Command
## Répartition du budget d'équipement entre les branches (terre, air, mer). Les parts sont ramenées à une
## somme de 1 et chacune reste entre les bornes des données.

var priorities: Dictionary = {}


func _init(p_issuer: StringName = &"", p_priorities: Dictionary = {}) -> void:
	issuer = p_issuer
	priorities = p_priorities


func get_type() -> StringName:
	return &"set_defense_priorities"


func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	if country == null or country.military == null or priorities.is_empty():
		return "MILITARY_INVALID"
	var bounds: Dictionary = state.military_settings.get("priorities", {})
	var total := 0.0
	for branch: Variant in priorities.keys():
		if not country.military.has_branch(str(branch)):
			return "MILITARY_INVALID"
		total += float(priorities[branch])
	if total <= 0.0:
		return "MILITARY_INVALID"
	for branch: Variant in priorities.keys():
		var share := float(priorities[branch]) / total
		if share < float(bounds.get("min", 0.0)) - 0.0001 or share > float(bounds.get("max", 1.0)) + 0.0001:
			return "MILITARY_PRIORITY_BOUNDS"
	return ""


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	var military := state.get_country(str(issuer)).military
	for branch: Variant in priorities.keys():
		military.priorities[str(branch)] = float(priorities[branch])
	MilitaryModel.normalize(military.priorities)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["priorities"] = priorities
	return data

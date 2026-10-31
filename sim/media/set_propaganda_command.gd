class_name SetPropagandaCommand
extends Command
## Niveau de propagande d'État (0 à 3), payé chaque mois.

const MAX_LEVEL := 3

var level: int = 0


func _init(p_issuer: StringName = &"", p_level: int = 0) -> void:
	issuer = p_issuer
	level = p_level


func get_type() -> StringName:
	return &"set_propaganda"


func can_execute(state: SimState) -> bool:
	var country := state.get_country(str(issuer))
	return country != null and level >= 0 and level <= MAX_LEVEL and country.propaganda_level != level


func execute(state: SimState) -> void:
	state.get_country(str(issuer)).propaganda_level = level


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["level"] = level
	return data

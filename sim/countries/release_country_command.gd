class_name ReleaseCountryCommand
extends Command
## Fait naître un pays de data/releasables. Pour l'instant réservée aux tests et au mode développement ; les
## arbres de décisions et les événements passent par l'effet « release_country ».

var definition_id: String = ""


func _init(p_issuer: StringName = &"", p_definition_id: String = "") -> void:
	issuer = p_issuer
	definition_id = p_definition_id


func get_type() -> StringName:
	return &"release_country"


func refusal_reason(state: SimState) -> String:
	return CountryFactory.release_refusal(state, definition_id)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	CountryFactory.release(state, definition_id)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["definition"] = definition_id
	return data

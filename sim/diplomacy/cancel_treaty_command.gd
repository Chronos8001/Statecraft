class_name CancelTreatyCommand
extends Command
## Rompre un traité : la confiance et les relations en pâtissent.

var treaty_id: int = 0


func _init(p_issuer: StringName = &"", p_treaty_id: int = 0) -> void:
	issuer = p_issuer
	treaty_id = p_treaty_id


func get_type() -> StringName:
	return &"cancel_treaty"


func can_execute(state: SimState) -> bool:
	var treaty: Dictionary = state.diplomacy.treaties.get(treaty_id, {})
	return not treaty.is_empty() and (treaty["a"] == str(issuer) or treaty["b"] == str(issuer))


func execute(state: SimState) -> void:
	DiplomacySystem.cancel_treaty(state, str(issuer), treaty_id)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["treaty"] = treaty_id
	return data

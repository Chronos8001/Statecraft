class_name SetStraitClosedCommand
extends Command
## Ferme ou rouvre un détroit au commerce des ressources (tests et mode développement ; les événements passent
## par ResourceSystem.set_strait_closed).

var strait_id: String = ""
var closed: bool = true


func _init(p_strait_id: String = "", p_closed: bool = true) -> void:
	strait_id = p_strait_id
	closed = p_closed


func get_type() -> StringName:
	return &"set_strait_closed"


func can_execute(state: SimState) -> bool:
	return (state.resource_definitions.get("straits", {}) as Dictionary).has(strait_id) \
		and state.closed_straits.has(strait_id) != closed


func execute(state: SimState) -> void:
	ResourceSystem.set_strait_closed(state, strait_id, closed)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["strait"] = strait_id
	data["closed"] = closed
	return data

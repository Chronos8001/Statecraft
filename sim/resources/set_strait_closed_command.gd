class_name SetStraitClosedCommand
extends Command
## Ferme ou rouvre un détroit au commerce des ressources. Pour l'instant réservée aux tests et au mode
## développement ; les blocus militaires (étape 7) et les événements (étape 9) l'utiliseront.

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
	if closed:
		state.closed_straits[strait_id] = true
		state.add_event(ResourceSystem.EVENT_STRAIT_CLOSED, "", {"strait": strait_id})
	else:
		state.closed_straits.erase(strait_id)
		state.add_event(ResourceSystem.EVENT_STRAIT_OPENED, "", {"strait": strait_id})


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["strait"] = strait_id
	data["closed"] = closed
	return data

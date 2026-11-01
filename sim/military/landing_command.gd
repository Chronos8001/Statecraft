class_name LandingCommand
extends Command
## Débarquement d'un groupe d'armées sur une province ennemie côtière, appuyé par une flotte de notre camp.

var group_id: int = 0
var target: String = ""


func _init(p_issuer: StringName = &"", p_group_id: int = 0, p_target: String = "") -> void:
	issuer = p_issuer
	group_id = p_group_id
	target = p_target


func get_type() -> StringName:
	return &"landing"


func refusal_reason(state: SimState) -> String:
	return LandingSystem.refusal(state, str(issuer), group_id, target)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	LandingSystem.launch(state, state.army_groups[group_id], target)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["group"] = group_id
	data["target"] = target
	return data

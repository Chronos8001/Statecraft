class_name DeclareWarCommand
extends Command
## Déclaration de guerre à un pays avec un but de guerre justifié.

var target: String = ""
var goal: String = ""


func _init(p_issuer: StringName = &"", p_target: String = "", p_goal: String = "") -> void:
	issuer = p_issuer
	target = p_target
	goal = p_goal


func get_type() -> StringName:
	return &"declare_war"


func refusal_reason(state: SimState) -> String:
	return WarSystem.declare_refusal(state, str(issuer), target, goal)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	WarSystem.declare(state, str(issuer), target, goal)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["goal"] = goal
	return data

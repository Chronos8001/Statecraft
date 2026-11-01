class_name DeclareIndependenceCommand
extends Command
## Un gouvernement fantoche proclame son indépendance (crise avec son suzerain).


func _init(p_issuer: StringName = &"") -> void:
	issuer = p_issuer


func get_type() -> StringName:
	return &"declare_independence"


func refusal_reason(state: SimState) -> String:
	return OccupationSystem.independence_refusal(state, str(issuer))


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	OccupationSystem.declare_independence(state, str(issuer))

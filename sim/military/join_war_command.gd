class_name JoinWarCommand
extends Command
## Entrée en guerre volontaire aux côtés d'un camp (attaquants ou défenseurs).

var war_id: int = -1
var side: String = ""


func _init(p_issuer: StringName = &"", p_war_id: int = -1, p_side: String = "") -> void:
	issuer = p_issuer
	war_id = p_war_id
	side = p_side


func get_type() -> StringName:
	return &"join_war"


func refusal_reason(state: SimState) -> String:
	return WarSystem.join_refusal(state, str(issuer), war_id, side)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	var war: War = state.wars[war_id]
	var called := not WarSystem.pending_call(state, war_id, str(issuer)).is_empty()
	WarSystem.join(state, war, str(issuer), side, called)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["war"] = war_id
	data["side"] = side
	return data

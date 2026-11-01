class_name AnswerCallToArmsCommand
extends Command
## Réponse du joueur à un appel aux armes : entrer en guerre aux côtés de l'allié ou refuser.

var war_id: int = -1
var accept: bool = false


func _init(p_issuer: StringName = &"", p_war_id: int = -1, p_accept: bool = false) -> void:
	issuer = p_issuer
	war_id = p_war_id
	accept = p_accept


func get_type() -> StringName:
	return &"answer_call_to_arms"


func refusal_reason(state: SimState) -> String:
	if WarSystem.pending_call(state, war_id, str(issuer)).is_empty():
		return "WAR_INVALID"
	return ""


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	WarSystem.answer_call(state, war_id, str(issuer), accept)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["war"] = war_id
	data["accept"] = accept
	return data

class_name AnswerPeaceCommand
extends Command
## Réponse du joueur à une paix blanche proposée par un pays de l'IA : accepter (fin de la guerre) ou refuser.

var war_id: int = -1
var accept: bool = false


func _init(p_issuer: StringName = &"", p_war_id: int = -1, p_accept: bool = false) -> void:
	issuer = p_issuer
	war_id = p_war_id
	accept = p_accept


func get_type() -> StringName:
	return &"answer_peace"


func refusal_reason(state: SimState) -> String:
	var war: War = state.wars.get(war_id)
	if war == null or WarSystem.peace_offer(state, war_id).is_empty() or StringName(str(issuer)) != state.player_tag \
			or not war.involves(str(issuer)):
		return "WAR_INVALID"
	return ""


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	WarSystem.answer_peace(state, war_id, accept)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["war"] = war_id
	data["accept"] = accept
	return data

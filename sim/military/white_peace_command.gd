class_name WhitePeaceCommand
extends Command
## Proposition de paix blanche par le meneur d'un camp : retour au contrôle d'avant-guerre si l'autre camp
## accepte.

var war_id: int = -1


func _init(p_issuer: StringName = &"", p_war_id: int = -1) -> void:
	issuer = p_issuer
	war_id = p_war_id


func get_type() -> StringName:
	return &"white_peace"


func refusal_reason(state: SimState) -> String:
	return WarSystem.white_peace_refusal(state, str(issuer), war_id)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	WarSystem.propose_white_peace(state, state.wars[war_id], str(issuer))


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["war"] = war_id
	return data

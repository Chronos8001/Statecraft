class_name CeasefireCommand
extends Command
## Proposition de cessez-le-feu par le meneur d'un camp : les fronts se figent le temps de négocier.

var war_id: int = -1


func _init(p_issuer: StringName = &"", p_war_id: int = -1) -> void:
	issuer = p_issuer
	war_id = p_war_id


func get_type() -> StringName:
	return &"ceasefire"


func refusal_reason(state: SimState) -> String:
	return WarEnd.ceasefire_refusal(state, str(issuer), war_id)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	WarEnd.propose_ceasefire(state, state.wars[war_id], str(issuer))


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["war"] = war_id
	return data

class_name NegotiatePeaceCommand
extends Command
## Proposition de paix avec exigences (provinces visées et tenues, réparations), au prix du score de guerre.

var war_id: int = -1
var demands: Array = []


func _init(p_issuer: StringName = &"", p_war_id: int = -1, p_demands: Array = []) -> void:
	issuer = p_issuer
	war_id = p_war_id
	demands = p_demands


func get_type() -> StringName:
	return &"negotiate_peace"


func refusal_reason(state: SimState) -> String:
	return WarEnd.peace_refusal(state, str(issuer), war_id, demands)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	WarEnd.propose_peace(state, state.wars[war_id], str(issuer), demands)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["war"] = war_id
	data["demands"] = demands
	return data

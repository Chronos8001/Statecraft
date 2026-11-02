class_name FocusCommand
extends Command
## Commence un nœud de l'arbre de décisions, ou abandonne le nœud en cours (node_id vide ; avancement perdu).

var node_id: String = ""


func _init(p_issuer: StringName = &"", p_node_id: String = "") -> void:
	issuer = p_issuer
	node_id = p_node_id


func get_type() -> StringName:
	return &"focus"


func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	if country == null:
		return "FOCUS_UNKNOWN"
	if node_id.is_empty():
		return "" if not country.focus_current.is_empty() else "FOCUS_NONE"
	return DecisionSystem.focus_refusal(state, country, node_id)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	if node_id.is_empty():
		DecisionSystem.cancel_focus(country)
	else:
		DecisionSystem.start_focus(state, country, node_id)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["node"] = node_id
	return data

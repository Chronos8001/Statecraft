class_name DecisionCommand
extends Command
## Prend une décision ponctuelle, ou annule celle en cours (cancel = true ; le coût n'est pas rendu).

var decision_id: String = ""
var cancel: bool = false


func _init(p_issuer: StringName = &"", p_decision_id: String = "", p_cancel: bool = false) -> void:
	issuer = p_issuer
	decision_id = p_decision_id
	cancel = p_cancel


func get_type() -> StringName:
	return &"decision"


func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	if country == null:
		return "DECISION_UNKNOWN"
	if cancel:
		return "" if country.decisions_active.has(decision_id) else "DECISION_NOT_ACTIVE"
	return DecisionSystem.decision_refusal(state, country, decision_id)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	if cancel:
		DecisionSystem.cancel_decision(state, country, decision_id)
	else:
		DecisionSystem.start_decision(state, country, decision_id)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["decision"] = decision_id
	data["cancel"] = cancel
	return data

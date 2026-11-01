class_name MilitaryActionCommand
extends Command
## Action ponctuelle : frappe de missiles, opération spéciale ou cyberattaque (voir MilitaryActions).

var action: String = ""
var kind: String = ""
## Province (bâtiment, infrastructures), clé d'un front, ou pays visé (cyberattaque).
var target: String = ""
var building: String = ""


func _init(p_issuer: StringName = &"", p_action: String = "", p_kind: String = "", p_target: String = "",
		p_building: String = "") -> void:
	issuer = p_issuer
	action = p_action
	kind = p_kind
	target = p_target
	building = p_building


func get_type() -> StringName:
	return &"military_action"


func refusal_reason(state: SimState) -> String:
	return MilitaryActions.refusal(state, str(issuer), action, kind, target, building)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	MilitaryActions.execute(state, str(issuer), action, kind, target, building)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["action"] = action
	data["kind"] = kind
	data["target"] = target
	data["building"] = building
	return data

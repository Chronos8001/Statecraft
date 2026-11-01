class_name StealTechnologyCommand
extends Command
## Espionnage industriel : voler une technologie connue d'un autre pays.

var target: String = ""
var technology: String = ""


func _init(p_issuer: StringName = &"", p_target: String = "", p_technology: String = "") -> void:
	issuer = p_issuer
	target = p_target
	technology = p_technology


func get_type() -> StringName:
	return &"steal_technology"


func refusal_reason(state: SimState) -> String:
	return ResearchCooperation.espionage_refusal(state, str(issuer), target, technology)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	ResearchCooperation.steal(state, str(issuer), target, technology)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["technology"] = technology
	return data

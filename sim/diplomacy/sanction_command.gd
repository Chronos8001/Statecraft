class_name SanctionCommand
extends Command
## Imposer ou lever une mesure de sanction contre un pays.

var target: String = ""
var measure: String = ""
var active: bool = true


func _init(p_issuer: StringName = &"", p_target: String = "", p_measure: String = "", p_active: bool = true) -> void:
	issuer = p_issuer
	target = p_target
	measure = p_measure
	active = p_active


func get_type() -> StringName:
	return &"sanction"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func refusal_reason(state: SimState) -> String:
	var tag := str(issuer)
	if state.get_country(tag) == null or state.get_country(target) == null or tag == target \
			or not state.sanction_definitions.has(measure):
		return "DIPLOMACY_INVALID"
	if SanctionSystem.has_measure(state, tag, target, measure) == active:
		return "DIPLOMACY_ALREADY"
	if active and not TensionSystem.unlocked(state, measure):
		return "TENSION_TOO_LOW"
	return ""


func execute(state: SimState) -> void:
	SanctionSystem.set_measure(state, str(issuer), target, measure, active)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["measure"] = measure
	data["active"] = active
	return data

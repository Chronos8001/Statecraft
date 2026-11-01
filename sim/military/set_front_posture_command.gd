class_name SetFrontPostureCommand
extends Command
## Posture du pays sur un front : offensive, défensive, tenir ou retraite.

var front_key: String = ""
var posture: String = ""


func _init(p_issuer: StringName = &"", p_front_key: String = "", p_posture: String = "") -> void:
	issuer = p_issuer
	front_key = p_front_key
	posture = p_posture


func get_type() -> StringName:
	return &"set_front_posture"


func refusal_reason(state: SimState) -> String:
	var front: Front = state.fronts.get(front_key)
	if front == null or (front.a != str(issuer) and front.b != str(issuer)) or not FrontSystem.POSTURES.has(posture):
		return "WAR_INVALID"
	if front.posture_of(str(issuer)) == posture:
		return "MILITARY_ALREADY"
	return ""


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	(state.fronts[front_key] as Front).postures[str(issuer)] = posture


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["front"] = front_key
	data["posture"] = posture
	return data

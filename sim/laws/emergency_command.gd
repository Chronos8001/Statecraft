class_name EmergencyCommand
extends Command
## Déclarer ou lever l'état d'urgence. En démocratie, la déclaration demande une majorité gouvernementale.

var active: bool = true


func _init(p_issuer: StringName = &"", p_active: bool = true) -> void:
	issuer = p_issuer
	active = p_active


func get_type() -> StringName:
	return &"emergency"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	if country == null:
		return "LAWS_INVALID"
	var politics := country.politics
	if active == (politics.emergency_months > 0):
		return "LAWS_ALREADY"
	if active and politics.democratic and politics.seats > 0 and not politics.has_majority():
		return "CONSTITUTION_NO_MAJORITY"
	return ""


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	country.politics.emergency_months = int(ConstitutionSystem.settings_of(state).get("emergency_months", 0)) \
		if active else 0
	state.add_event(ConstitutionSystem.EVENT_EMERGENCY, country.tag, {"active": active})


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["active"] = active
	return data

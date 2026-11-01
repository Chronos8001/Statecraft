class_name NuclearAlertCommand
extends Command
## Niveau d'alerte nucléaire du pays (0 : normal … 3 : maximal).

var level: int = 0


func _init(p_issuer: StringName = &"", p_level: int = 0) -> void:
	issuer = p_issuer
	level = p_level


func get_type() -> StringName:
	return &"nuclear_alert"


func refusal_reason(state: SimState) -> String:
	return NuclearSystem.alert_refusal(state, str(issuer), level)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	NuclearSystem.set_alert(state, str(issuer), level)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["level"] = level
	return data

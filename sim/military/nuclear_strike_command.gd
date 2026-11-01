class_name NuclearStrikeCommand
extends Command
## Frappe nucléaire sur une province ennemie (alerte maximale exigée).

var province: String = ""


func _init(p_issuer: StringName = &"", p_province: String = "") -> void:
	issuer = p_issuer
	province = p_province


func get_type() -> StringName:
	return &"nuclear_strike"


func refusal_reason(state: SimState) -> String:
	return NuclearSystem.strike_refusal(state, str(issuer), province)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	NuclearSystem.strike(state, str(issuer), province)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["province"] = province
	return data

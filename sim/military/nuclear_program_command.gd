class_name NuclearProgramCommand
extends Command
## Lance ou abandonne un programme nucléaire militaire.

var start: bool = true


func _init(p_issuer: StringName = &"", p_start: bool = true) -> void:
	issuer = p_issuer
	start = p_start


func get_type() -> StringName:
	return &"nuclear_program"


func refusal_reason(state: SimState) -> String:
	return NuclearSystem.program_refusal(state, str(issuer), start)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	if start:
		NuclearSystem.start_program(state, str(issuer))
	else:
		NuclearSystem.abandon_program(state, str(issuer))


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["start"] = start
	return data

class_name ProposeTreatyCommand
extends Command
## Proposer un traité à un pays ; un pays de l'IA accepte si son intérêt (DiplomacyModel) est positif.

var target: String = ""
var treaty_type: String = ""


func _init(p_issuer: StringName = &"", p_target: String = "", p_treaty_type: String = "") -> void:
	issuer = p_issuer
	target = p_target
	treaty_type = p_treaty_type


func get_type() -> StringName:
	return &"propose_treaty"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func refusal_reason(state: SimState) -> String:
	var tag := str(issuer)
	if state.get_country(tag) == null or state.get_country(target) == null or tag == target \
			or not state.treaty_definitions.has(treaty_type):
		return "DIPLOMACY_INVALID"
	if not state.diplomacy.has_embassy(tag, target):
		return "DIPLOMACY_NO_EMBASSY"
	if state.diplomacy.has_treaty(tag, target, treaty_type):
		return "DIPLOMACY_ALREADY"
	if state.diplomacy.cooldown("treaty_" + treaty_type, tag, target) > 0:
		return "DIPLOMACY_COOLDOWN"
	return ""


func execute(state: SimState) -> void:
	DiplomacySystem.propose_treaty(state, str(issuer), target, treaty_type)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["treaty"] = treaty_type
	return data

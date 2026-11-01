class_name JointProjectCommand
extends Command
## Propose un projet de recherche conjoint à un pays (même technologie, avancement commun).

var partner: String = ""
var technology: String = ""


func _init(p_issuer: StringName = &"", p_partner: String = "", p_technology: String = "") -> void:
	issuer = p_issuer
	partner = p_partner
	technology = p_technology


func get_type() -> StringName:
	return &"joint_project"


func refusal_reason(state: SimState) -> String:
	return ResearchCooperation.joint_refusal(state, str(issuer), partner, technology)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	ResearchCooperation.propose_joint(state, str(issuer), partner, technology)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["partner"] = partner
	data["technology"] = technology
	return data

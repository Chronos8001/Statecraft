class_name AutoDeployCommand
extends Command
## Répartit automatiquement les groupes d'armées du pays sur ses fronts, selon les forces ennemies en face.


func _init(p_issuer: StringName = &"") -> void:
	issuer = p_issuer


func get_type() -> StringName:
	return &"auto_deploy"


func refusal_reason(state: SimState) -> String:
	if state.get_country(str(issuer)) == null:
		return "WAR_INVALID"
	FrontSystem.refresh(state)
	if FrontSystem.fronts_of(state, str(issuer)).is_empty():
		return "MILITARY_NO_FRONT"
	if ArmyGroupModel.groups_of(state, str(issuer)).is_empty():
		return "MILITARY_NO_GROUP"
	return ""


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	FrontSystem.auto_deploy(state, str(issuer))

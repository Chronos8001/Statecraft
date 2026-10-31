class_name CancelProjectCommand
extends Command
## Abandonne un chantier du pays : les dépenses s'arrêtent, ce qui a été payé est perdu.

var project_id: int = 0


func _init(p_issuer: StringName = &"", p_project_id: int = 0) -> void:
	issuer = p_issuer
	project_id = p_project_id


func get_type() -> StringName:
	return &"cancel_project"


func can_execute(state: SimState) -> bool:
	return find(state) != null


func execute(state: SimState) -> void:
	state.projects.erase(find(state))


func find(state: SimState) -> Variant:
	for project: Dictionary in state.projects:
		if int(project["id"]) == project_id and str(project["tag"]) == str(issuer):
			return project
	return null


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["project"] = project_id
	return data

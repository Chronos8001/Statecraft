class_name MoveArmyGroupCommand
extends Command
## Envoie un groupe d'armées vers une province que son pays contrôle, par voie de terre.

var group_id: int = 0
var destination: String = ""


func _init(p_issuer: StringName = &"", p_group_id: int = 0, p_destination: String = "") -> void:
	issuer = p_issuer
	group_id = p_group_id
	destination = p_destination


func get_type() -> StringName:
	return &"move_army_group"


func refusal_reason(state: SimState) -> String:
	var group: ArmyGroup = state.army_groups.get(group_id)
	if group == null or group.owner != str(issuer):
		return "ARMY_INVALID"
	if group.province == destination and not group.is_moving():
		return "ARMY_ALREADY_THERE"
	if ControlSystem.controller(state, destination) != str(issuer):
		return "ARMY_NOT_CONTROLLED"
	if destination != group.province and ArmyGroupModel.find_path(state, group.owner, group.province, destination).is_empty():
		return "ARMY_UNREACHABLE"
	return ""


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	var group: ArmyGroup = state.army_groups[group_id]
	if destination == group.province:
		group.path.clear()
		group.days_left = 0
		return
	ArmyGroupModel.order_move(state, group, destination)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["group"] = group_id
	data["destination"] = destination
	return data

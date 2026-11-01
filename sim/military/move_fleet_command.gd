class_name MoveFleetCommand
extends Command
## Envoie une flotte vers une zone maritime, par la mer (détroits et canaux ouverts).

var fleet_id: int = 0
var destination: String = ""


func _init(p_issuer: StringName = &"", p_fleet_id: int = 0, p_destination: String = "") -> void:
	issuer = p_issuer
	fleet_id = p_fleet_id
	destination = p_destination


func get_type() -> StringName:
	return &"move_fleet"


func refusal_reason(state: SimState) -> String:
	var fleet: Fleet = state.fleets.get(fleet_id)
	if fleet == null or fleet.owner != str(issuer):
		return "FLEET_INVALID"
	if not NavalModel.is_sea(state, destination):
		return "FLEET_NOT_SEA"
	if fleet.zone == destination and not fleet.is_moving():
		return "FLEET_ALREADY_THERE"
	if destination != fleet.zone and NavalModel.find_path(state, fleet.zone, destination).is_empty():
		return "FLEET_UNREACHABLE"
	return ""


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	var fleet: Fleet = state.fleets[fleet_id]
	if destination == fleet.zone:
		fleet.path.clear()
		fleet.days_left = 0
		return
	NavalModel.order_move(state, fleet, destination)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["fleet"] = fleet_id
	data["destination"] = destination
	return data

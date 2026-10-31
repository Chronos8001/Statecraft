class_name BuildCommand
extends Command
## Lance un chantier dans une province du pays : le coût est payé chaque mois par le budget jusqu'à
## l'achèvement. Conditions : province possédée, côte (port, raffinerie), relief (barrage, géothermie,
## solaire), ressource exploitable (mine), nombre maximal par province (chantiers en cours compris).

var building: String = ""
var province: String = ""


func _init(p_issuer: StringName = &"", p_building: String = "", p_province: String = "") -> void:
	issuer = p_issuer
	building = p_building
	province = p_province


func get_type() -> StringName:
	return &"build"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


## Raison du refus (clé de traduction), vide si la construction est possible.
func refusal_reason(state: SimState) -> String:
	var definitions := state.energy_definitions
	var definition: Dictionary = (definitions.get("buildings", {}) as Dictionary).get(building, {})
	var data: Dictionary = (definitions.get("provinces", {}) as Dictionary).get(province, {})
	if definition.is_empty() or data.is_empty() or state.get_country(str(issuer)) == null:
		return "BUILD_REFUSED_UNKNOWN"
	if str(data.get("owner", "")) != str(issuer) or str(data.get("controller", "")) != str(issuer):
		return "BUILD_REFUSED_NOT_OURS"
	if bool(definition.get("coastal", false)) and not bool(data.get("coastal", false)):
		return "BUILD_REFUSED_COASTAL"
	var terrains: Array = definition.get("terrains", [])
	if not terrains.is_empty() and not terrains.has(str(data.get("terrain", ""))):
		return "BUILD_REFUSED_TERRAIN"
	if bool(definition.get("requires_resource", false)) and EnergySystem.mine_resource(state, province).is_empty():
		return "BUILD_REFUSED_RESOURCE"
	var count := EnergySystem.building_count(state, province, building)
	for project: Dictionary in state.projects:
		if str(project["province"]) == province and str(project["building"]) == building:
			count += 1
	if count >= int(definition.get("max_per_province", 1)):
		return "BUILD_REFUSED_FULL"
	return ""


func execute(state: SimState) -> void:
	var definition: Dictionary = state.energy_definitions["buildings"][building]
	var months := int(definition.get("build_months", 1))
	state.next_project_id += 1
	state.projects.append({"id": state.next_project_id, "tag": str(issuer), "building": building, "province": province,
		"months_left": months, "total_months": months,
		"monthly_cost": float(definition.get("cost_billion", 0.0)) / months})


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["building"] = building
	data["province"] = province
	return data

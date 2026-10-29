class_name ResourceMapMode
extends MapMode
## Couleur de la ressource la plus abondante de chaque province.


static func dominant_resource(province: Dictionary) -> String:
	var best := ""
	var best_amount := 0.0
	var amounts: Dictionary = province.get("resources", {})
	for resource: String in amounts.keys():
		if float(amounts[resource]) > best_amount:
			best = resource
			best_amount = float(amounts[resource])
	return best


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var none_color := Color.html(str(definition.get("none_color", "#000000")))
	return _color_provinces(context, func(province: Dictionary) -> Color:
		var resource: Dictionary = context.resources.get(dominant_resource(province), {})
		return Color.html(str(resource["color"])) if resource.has("color") else none_color)


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	var legend: Array[Dictionary] = []
	for resource_id: String in context.resources.keys():
		var resource: Dictionary = context.resources[resource_id]
		legend.append(_entry(Color.html(str(resource["color"])), str(resource["name_key"])))
	legend.append(_entry(Color.html(str(definition.get("none_color", "#000000"))), "LEGEND_NONE"))
	return legend

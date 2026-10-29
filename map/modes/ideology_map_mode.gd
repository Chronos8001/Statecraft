class_name IdeologyMapMode
extends MapMode
## Couleur de l'idéologie dominante du pays propriétaire.


func compute_colors(context: MapModeContext) -> PackedColorArray:
	return _color_provinces(context, func(province: Dictionary) -> Color:
		var owner := context.owner_of(province)
		if owner.is_empty():
			return context.unowned_color
		var ideology: Dictionary = context.ideologies.get(str(owner.get("ideology", "")), {})
		return Color.html(str(ideology["color"])) if ideology.has("color") else context.no_data_color)


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	var used: Dictionary = {}
	for tag: String in context.countries.keys():
		var ideology := str((context.countries[tag] as Dictionary).get("ideology", ""))
		if context.ideologies.has(ideology):
			used[ideology] = true
	var legend: Array[Dictionary] = []
	for ideology_id: String in context.ideologies.keys():
		if used.has(ideology_id):
			var ideology: Dictionary = context.ideologies[ideology_id]
			legend.append(_entry(Color.html(str(ideology["color"])), str(ideology["name_key"])))
	legend.append(_entry(context.no_data_color, "LEGEND_NO_DATA"))
	return legend

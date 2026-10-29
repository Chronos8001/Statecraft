class_name TerrainMapMode
extends MapMode
## Couleur du terrain de chaque province.


func compute_colors(context: MapModeContext) -> PackedColorArray:
	return _color_provinces(context, func(province: Dictionary) -> Color:
		var terrain: Dictionary = context.terrains.get(str(province.get("terrain", "")), {})
		return Color.html(str(terrain["color"])) if terrain.has("color") else context.no_data_color)


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	var legend: Array[Dictionary] = []
	for terrain_id: String in context.terrains.keys():
		var terrain: Dictionary = context.terrains[terrain_id]
		legend.append(_entry(Color.html(str(terrain["color"])), str(terrain["name_key"])))
	return legend

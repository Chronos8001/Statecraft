class_name PoliticalMapMode
extends MapMode
## Couleur du pays propriétaire.


func compute_colors(context: MapModeContext) -> PackedColorArray:
	return _color_provinces(context, func(province: Dictionary) -> Color:
		var owner := context.owner_of(province)
		return Color.html(str(owner["color"])) if owner.has("color") else context.unowned_color)


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	return [_entry(context.unowned_color, "LEGEND_UNOWNED")]

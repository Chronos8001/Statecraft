class_name ControlMapMode
extends MapMode
## Couleur du pays qui contrôle la province ; les territoires occupés sont teintés.


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var occupied_color := Color.html(str(definition.get("occupied_color", "#FF0000")))
	var strength := float(definition.get("occupied_strength", 0.5))
	return _color_provinces(context, func(province: Dictionary) -> Color:
		var controller: Dictionary = context.countries.get(str(province.get("controller", "")), {})
		if controller.is_empty():
			return context.unowned_color
		var color := Color.html(str(controller.get("color", "#000000")))
		if province.get("controller", "") != province.get("owner", ""):
			color = color.lerp(occupied_color, strength)
		return color)


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	return [
		_entry(Color.html(str(definition.get("occupied_color", "#FF0000"))), "LEGEND_OCCUPIED"),
		_entry(context.unowned_color, "LEGEND_UNOWNED"),
	]

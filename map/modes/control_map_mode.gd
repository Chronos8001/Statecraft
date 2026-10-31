class_name ControlMapMode
extends MapMode
## Couleur du pays qui contrôle la province ; les territoires occupés sont teintés. Pendant une partie, le
## contrôle vient de la simulation et une province disputée se colore en partie vers celui qui en tient une part.


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var occupied_color := Color.html(str(definition.get("occupied_color", "#FF0000")))
	var strength := float(definition.get("occupied_strength", 0.5))
	var state := context.simulation
	var live := state != null and not state.province_control.is_empty()
	var colors := context.new_colors()
	for key: String in context.provinces.keys():
		var province_id := int(key)
		if province_id <= 0 or province_id > context.max_id:
			continue
		var province: Dictionary = context.provinces[key]
		var controller_tag := ControlSystem.controller(state, key) if live else str(province.get("controller", ""))
		var controller: Dictionary = context.countries.get(controller_tag, {})
		if controller.is_empty():
			colors[province_id] = context.unowned_color
			continue
		var color := _tinted(controller_tag, controller, str(province.get("owner", "")), occupied_color, strength)
		if live and state.contested.has(key):
			var contest: Dictionary = state.contested[key]
			var holder := str(contest["by"])
			var holder_color := _tinted(holder, context.countries.get(holder, {}), str(province.get("owner", "")),
				occupied_color, strength)
			color = color.lerp(holder_color, float(contest["share"]))
		colors[province_id] = color
	return colors


static func _tinted(tag: String, country: Dictionary, owner: String, occupied_color: Color, strength: float) -> Color:
	var color := Color.html(str(country.get("color", "#000000")))
	return color.lerp(occupied_color, strength) if tag != owner else color


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	return [
		_entry(Color.html(str(definition.get("occupied_color", "#FF0000"))), "LEGEND_OCCUPIED"),
		_entry(context.unowned_color, "LEGEND_UNOWNED"),
	]

class_name SeaControlMapMode
extends MapMode
## Contrôle des mers dans les guerres en cours : mers dominées par notre camp, par l'ennemi, disputées, et mers
## d'autres guerres. Les terres restent neutres (notre pays mis en évidence).


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var ours := Color.html(str(definition.get("ally_color", "#0000FF")))
	var theirs := Color.html(str(definition.get("enemy_color", "#FF0000")))
	var contested := Color.html(str(definition.get("contested_color", "#FF8000")))
	var other := Color.html(str(definition.get("war_color", "#808080")))
	var player_color := Color.html(str(definition.get("player_color", "#FFFFFF")))
	var colors := context.new_colors()
	for key: String in context.provinces.keys():
		var province_id := int(key)
		if province_id <= 0 or province_id > context.max_id:
			continue
		var owner := str((context.provinces[key] as Dictionary).get("owner", ""))
		colors[province_id] = context.unowned_color if owner.is_empty() \
			else player_color if owner == context.player_tag else context.no_data_color
	var state := context.simulation
	if state == null:
		return colors
	for zone_key: Variant in state.sea_control.keys():
		var zone_id := int(zone_key)
		if zone_id <= 0 or zone_id > context.max_id:
			continue
		var control: Dictionary = state.sea_control[zone_key]
		var war: War = state.wars.get(int(control.get("war", -1)))
		if war == null:
			continue
		var player_side := war.side_of(context.player_tag)
		if player_side.is_empty():
			colors[zone_id] = other
		elif bool(control.get("contested", false)):
			colors[zone_id] = contested
		else:
			colors[zone_id] = ours if str(control.get("side", "")) == player_side else theirs
	return colors


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	return [_entry(Color.html(str(definition.get("ally_color", "#0000FF"))), "LEGEND_SEA_OURS"),
		_entry(Color.html(str(definition.get("enemy_color", "#FF0000"))), "LEGEND_SEA_ENEMY"),
		_entry(Color.html(str(definition.get("contested_color", "#FF8000"))), "LEGEND_SEA_CONTESTED"),
		_entry(Color.html(str(definition.get("war_color", "#808080"))), "LEGEND_SEA_OTHER_WAR"),
		_entry(context.sea_color, "LEGEND_SEA_PEACE")]

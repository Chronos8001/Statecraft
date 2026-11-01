class_name WarsMapMode
extends MapMode
## Guerres en cours vues du joueur : nos ennemis, nos alliés dans nos guerres, les autres pays en guerre et
## les provinces tenues par des rebelles (en partie si elles sont disputées) ; les provinces de nos fronts sont
## éclaircies. Les pays en paix restent sur la couleur « pas de données ».


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var player_color := Color.html(str(definition.get("player_color", "#FFFFFF")))
	var enemy_color := Color.html(str(definition.get("enemy_color", "#FF0000")))
	var ally_color := Color.html(str(definition.get("ally_color", "#0000FF")))
	var war_color := Color.html(str(definition.get("war_color", "#FF8000")))
	var rebel_color := Color.html(str(definition.get("rebel_color", "#000000")))
	var state := context.simulation
	var status: Dictionary = {}
	if state != null:
		for war: War in state.wars.values():
			var player_side := war.side_of(context.player_tag)
			for tag: String in war.attackers + war.defenders:
				var side := war.side_of(tag)
				var color := war_color
				if not player_side.is_empty():
					color = ally_color if side == player_side else enemy_color
				# Nos ennemis et nos alliés passent devant les autres guerres.
				if not status.has(tag) or color != war_color:
					status[tag] = color
	status[context.player_tag] = player_color
	var front_color := Color.html(str(definition.get("front_color", "#FFFFFF")))
	var on_front: Dictionary = {}
	if state != null:
		for front: Front in state.fronts.values():
			if front.a == context.player_tag or front.b == context.player_tag:
				for tag: Variant in front.provinces.keys():
					for province_id: Variant in front.provinces[tag]:
						on_front[str(province_id)] = true
	var live := state != null and not state.province_control.is_empty()
	var colors := context.new_colors()
	for key: String in context.provinces.keys():
		var province_id := int(key)
		if province_id <= 0 or province_id > context.max_id:
			continue
		var owner := str((context.provinces[key] as Dictionary).get("owner", ""))
		if owner.is_empty():
			colors[province_id] = context.unowned_color
			continue
		var color: Color = status.get(owner, context.no_data_color)
		if live:
			if WarSystem.is_rebel(state, ControlSystem.controller(state, key)):
				color = rebel_color
			var contest: Dictionary = state.contested.get(key, {})
			if not contest.is_empty() and WarSystem.is_rebel(state, str(contest["by"])):
				color = color.lerp(rebel_color, float(contest["share"]))
		if on_front.has(key):
			color = color.lerp(front_color, float(definition.get("front_strength", 0.0)))
		colors[province_id] = color
	return colors


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	return [_entry(Color.html(str(definition.get("player_color", "#FFFFFF"))), "LEGEND_PLAYER"),
		_entry(Color.html(str(definition.get("enemy_color", "#FF0000"))), "LEGEND_WAR_ENEMY"),
		_entry(Color.html(str(definition.get("ally_color", "#0000FF"))), "LEGEND_WAR_ALLY"),
		_entry(Color.html(str(definition.get("war_color", "#FF8000"))), "LEGEND_WAR_OTHER"),
		_entry(Color.html(str(definition.get("rebel_color", "#000000"))), "LEGEND_REBELS"),
		_entry(Color.html(str(definition.get("enemy_color", "#FF0000"))).lerp(Color.html(str(definition.get("front_color",
			"#FFFFFF"))), float(definition.get("front_strength", 0.0))), "LEGEND_OUR_FRONTS"),
		_entry(context.no_data_color, "LEGEND_AT_PEACE")]

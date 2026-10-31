class_name ClaimsMapMode
extends MapMode
## Revendications territoriales : provinces que nous revendiquons, provinces de notre pays revendiquées par
## d'autres, autres provinces disputées dans le monde. Le reste reste sur la couleur « pas de données ».


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var own := Color.html(str(definition.get("own_color", "#FFFFFF")))
	var against := Color.html(str(definition.get("against_color", "#FF0000")))
	var other := Color.html(str(definition.get("other_color", "#808080")))
	var marks: Dictionary = {}
	var state := context.simulation
	if state != null:
		for claim: Dictionary in state.diplomacy.claims.values():
			var color := own if claim["claimant"] == context.player_tag \
				else against if claim["target"] == context.player_tag else other
			for province_id: Variant in TensionSystem.claimed_provinces(state, claim):
				# Nos revendications et celles qui nous visent passent devant les autres.
				if not marks.has(str(province_id)) or color != other:
					marks[str(province_id)] = color
	var colors := context.new_colors()
	for key: String in context.provinces.keys():
		var province_id := int(key)
		if province_id <= 0 or province_id > context.max_id:
			continue
		var owner := str((context.provinces[key] as Dictionary).get("owner", ""))
		colors[province_id] = context.unowned_color if owner.is_empty() else marks.get(key, context.no_data_color)
	return colors


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	return [_entry(Color.html(str(definition.get("own_color", "#FFFFFF"))), "LEGEND_CLAIM_OWN"),
		_entry(Color.html(str(definition.get("against_color", "#FF0000"))), "LEGEND_CLAIM_AGAINST"),
		_entry(Color.html(str(definition.get("other_color", "#808080"))), "LEGEND_CLAIM_OTHER"),
		_entry(context.no_data_color, "LEGEND_NONE")]

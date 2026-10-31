class_name TradeMapMode
extends MapMode
## Poids de chaque pays dans les échanges du pays joué (part de son commerce total) ; pays sous embargo
## (dans un sens ou dans l'autre) en couleur d'alerte.

var _gradient: ColorGradient


func _init(p_id: String, p_definition: Dictionary) -> void:
	super(p_id, p_definition)
	_gradient = ColorGradient.from_stops(definition.get("stops", []), false)


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var player_color := Color.html(str(definition.get("player_color", "#FFFFFF")))
	var embargo_color := Color.html(str(definition.get("embargo_color", "#FF0000")))
	return _color_provinces(context, func(province: Dictionary) -> Color:
		var owner := str(province.get("owner", ""))
		if owner.is_empty():
			return context.unowned_color
		if owner == context.player_tag:
			return player_color
		if context.embargoed.has(owner):
			return embargo_color
		return _gradient.sample(float(context.trade_shares.get(owner, 0.0))))


func get_legend(_context: MapModeContext) -> Array[Dictionary]:
	var legend: Array[Dictionary] = [
		_entry(Color.html(str(definition.get("player_color", "#FFFFFF"))), "LEGEND_PLAYER"),
		_entry(Color.html(str(definition.get("embargo_color", "#FF0000"))), "LEGEND_EMBARGO"),
	]
	var stops: Array = definition.get("stops", [])
	var keys: Array = definition.get("legend_keys", [])
	for i: int in mini(stops.size(), keys.size()):
		legend.append(_entry(Color.html(str(stops[i][1])), str(keys[i])))
	return legend

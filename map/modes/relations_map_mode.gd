class_name RelationsMapMode
extends MapMode
## Relations du joueur avec chaque pays (-100 hostile … +100 amical). Neutre si aucune relation connue.

const LEGEND_KEYS := ["LEGEND_HOSTILE", "LEGEND_NEUTRAL", "LEGEND_FRIENDLY"]

var _gradient: ColorGradient


func _init(p_id: String, p_definition: Dictionary) -> void:
	super(p_id, p_definition)
	_gradient = ColorGradient.from_stops(definition.get("stops", []), false)


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var player_color := Color.html(str(definition.get("player_color", "#FFFFFF")))
	return _color_provinces(context, func(province: Dictionary) -> Color:
		var owner := str(province.get("owner", ""))
		if owner.is_empty():
			return context.unowned_color
		if owner == context.player_tag:
			return player_color
		return _gradient.sample(float(context.relations.get(owner, 0.0))))


func get_legend(_context: MapModeContext) -> Array[Dictionary]:
	var stops: Array = definition.get("stops", [])
	var legend: Array[Dictionary] = [
		_entry(Color.html(str(definition.get("player_color", "#FFFFFF"))), "LEGEND_PLAYER")]
	for i: int in mini(stops.size(), LEGEND_KEYS.size()):
		legend.append(_entry(Color.html(str(stops[i][1])), LEGEND_KEYS[i]))
	return legend

class_name MapMode
extends RefCounted
## Mode de carte : calcule une couleur par province et une légende.
## Une entrée de légende est {"color": Color, "label_key": String}
## ou {"color": Color, "value": float, "unit_key": String} (nombre à mettre en forme).

var id: String = ""
var name_key: String = ""
var definition: Dictionary = {}


func _init(p_id: String, p_definition: Dictionary) -> void:
	id = p_id
	definition = p_definition
	name_key = str(p_definition.get("name_key", p_id))


func compute_colors(context: MapModeContext) -> PackedColorArray:
	return context.new_colors()


func get_legend(_context: MapModeContext) -> Array[Dictionary]:
	return []


## Applique une fonction province → couleur à toutes les provinces connues.
func _color_provinces(context: MapModeContext, color_of: Callable) -> PackedColorArray:
	var colors := context.new_colors()
	for key: String in context.provinces.keys():
		var province_id := int(key)
		if province_id > 0 and province_id <= context.max_id:
			colors[province_id] = color_of.call(context.provinces[key])
	return colors


static func _entry(color: Color, label_key: String) -> Dictionary:
	return {"color": color, "label_key": label_key}


static func _gradient_legend(stops: Array, unit_key: String) -> Array[Dictionary]:
	var legend: Array[Dictionary] = []
	for stop: Array in stops:
		legend.append({"color": Color.html(str(stop[1])), "value": float(stop[0]), "unit_key": unit_key})
	return legend

class_name ProvinceGradientMapMode
extends MapMode
## Dégradé selon une valeur de la province : « population_density » ou un champ numérique.

const POPULATION_DENSITY := "population_density"

var _gradient: ColorGradient


func _init(p_id: String, p_definition: Dictionary) -> void:
	super(p_id, p_definition)
	_gradient = ColorGradient.from_stops(definition.get("stops", []), bool(definition.get("logarithmic", false)))


static func province_value(province: Dictionary, value_name: String) -> float:
	if value_name == POPULATION_DENSITY:
		var area := float(province.get("area_km2", 0.0))
		return float(province.get("population", 0)) / area if area > 0.0 else 0.0
	return float(province.get(value_name, 0.0))


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var value_name := str(definition.get("value", ""))
	return _color_provinces(context, func(province: Dictionary) -> Color:
		return _gradient.sample(province_value(province, value_name)))


func get_legend(_context: MapModeContext) -> Array[Dictionary]:
	return _gradient_legend(definition.get("stops", []), str(definition.get("unit_key", "")))

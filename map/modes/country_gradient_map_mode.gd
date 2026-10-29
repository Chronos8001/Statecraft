class_name CountryGradientMapMode
extends MapMode
## Dégradé selon une valeur du pays propriétaire : « gdp_per_capita » ou un champ numérique du pays.
## Pays sans cette donnée : couleur « pas de données ».

const GDP_PER_CAPITA := "gdp_per_capita"
const USD_PER_BILLION := 1.0e9

var _gradient: ColorGradient


func _init(p_id: String, p_definition: Dictionary) -> void:
	super(p_id, p_definition)
	_gradient = ColorGradient.from_stops(definition.get("stops", []), bool(definition.get("logarithmic", false)))


## Valeur du pays, ou null si la donnée manque.
static func country_value(country: Dictionary, value_name: String) -> Variant:
	if value_name == GDP_PER_CAPITA:
		var economy: Dictionary = country.get("economy", {})
		var population := float(country.get("population", 0))
		if not economy.has("gdp_billion_usd") or population <= 0.0:
			return null
		return float(economy["gdp_billion_usd"]) * USD_PER_BILLION / population
	return float(country[value_name]) if country.has(value_name) else null


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var value_name := str(definition.get("value", ""))
	var by_country: Dictionary = {}
	for tag: String in context.countries.keys():
		var value: Variant = country_value(context.countries[tag], value_name)
		by_country[tag] = context.no_data_color if value == null else _gradient.sample(float(value))
	return _color_provinces(context, func(province: Dictionary) -> Color:
		return by_country.get(str(province.get("owner", "")), context.unowned_color))


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	var legend := _gradient_legend(definition.get("stops", []), str(definition.get("unit_key", "")))
	legend.append(_entry(context.no_data_color, "LEGEND_NO_DATA"))
	return legend

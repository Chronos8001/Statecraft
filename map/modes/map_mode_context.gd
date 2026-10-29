class_name MapModeContext
extends RefCounted
## Données dont les modes de carte ont besoin pour calculer leurs couleurs.

var provinces: Dictionary = {}
var countries: Dictionary = {}
var terrains: Dictionary = {}
var ideologies: Dictionary = {}
var organizations: Dictionary = {}
var resources: Dictionary = {}
## Relations du joueur avec chaque pays (tag → -100..100). Vide tant que la diplomatie n'existe pas.
var relations: Dictionary = {}
var player_tag: String = ""
var max_id: int = 0
var sea_color: Color = Color.BLACK
var unowned_color: Color = Color.GRAY
var no_data_color: Color = Color.DIM_GRAY


static func from_game_data() -> MapModeContext:
	var context := MapModeContext.new()
	context.provinces = DataLoader.get_category("provinces")
	context.countries = DataLoader.get_category("countries")
	context.terrains = DataLoader.get_category("terrains")
	context.ideologies = DataLoader.get_category("ideologies")
	context.organizations = DataLoader.repository.resolve_ref("names#organizations")
	context.resources = DataLoader.get_category("resources")
	context.player_tag = str(GameState.sim.player_tag)
	context.max_id = int(DataLoader.get_category("map")["map"]["province_count"])
	context.sea_color = Color.html(str(DataLoader.get_define("map_colors.sea")))
	context.unowned_color = Color.html(str(DataLoader.get_define("map_colors.unowned")))
	context.no_data_color = Color.html(str(DataLoader.get_define("map_colors.no_data")))
	return context


## Tableau de couleurs prêt à remplir : mer pour l'id 0, « sans propriétaire » ailleurs.
func new_colors() -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(max_id + 1)
	colors.fill(unowned_color)
	colors[0] = sea_color
	return colors


func owner_of(province: Dictionary) -> Dictionary:
	return countries.get(str(province.get("owner", "")), {})

class_name MapModeContext
extends RefCounted
## Données dont les modes de carte ont besoin pour calculer leurs couleurs.

var provinces: Dictionary = {}
var sea_zones: Dictionary = {}
var countries: Dictionary = {}
var terrains: Dictionary = {}
var ideologies: Dictionary = {}
var organizations: Dictionary = {}
var resources: Dictionary = {}
## Relations du joueur avec chaque pays (tag → -100..100). Vide tant que la diplomatie n'existe pas.
var relations: Dictionary = {}
## Part de chaque pays dans les échanges du joueur (tag → 0..1) et pays sous embargo avec lui (tag → true).
var trade_shares: Dictionary = {}
var embargoed: Dictionary = {}
var player_tag: String = ""
var max_id: int = 0
var sea_color: Color = Color.BLACK
var unowned_color: Color = Color.GRAY
var no_data_color: Color = Color.DIM_GRAY


static func from_game_data() -> MapModeContext:
	var context := MapModeContext.new()
	context.provinces = DataLoader.get_category("provinces")
	context.sea_zones = DataLoader.get_category("sea_zones")
	context.countries = DataLoader.get_category("countries")
	context.terrains = DataLoader.get_category("terrains")
	context.ideologies = DataLoader.get_category("ideologies")
	context.organizations = DataLoader.repository.resolve_ref("names#organizations")
	context.resources = DataLoader.get_category("resources")
	context.player_tag = str(GameState.sim.player_tag)
	context.max_id = int(DataLoader.get_category("map")["map"]["max_id"])
	context.sea_color = Color.html(str(DataLoader.get_define("map_colors.sea")))
	context.unowned_color = Color.html(str(DataLoader.get_define("map_colors.unowned")))
	context.no_data_color = Color.html(str(DataLoader.get_define("map_colors.no_data")))
	return context


## Met à jour ce qui dépend de la partie en cours (pays joué, commerce).
func refresh_from_simulation(state: SimState) -> void:
	player_tag = str(state.player_tag)
	trade_shares.clear()
	embargoed.clear()
	if player_tag.is_empty() or state.trade.start_flows.is_empty():
		return
	var totals := TradeSystem.partner_totals(state, player_tag)
	var total := 0.0
	for amount: Variant in totals.values():
		total += float(amount)
	for partner: Variant in totals.keys():
		trade_shares[partner] = float(totals[partner]) / total if total > 0.0 else 0.0
	for tag: String in state.countries.keys():
		if state.trade.trade_blocked(player_tag, tag) or not state.trade.embargo_goods(player_tag, tag).is_empty() \
				or not state.trade.embargo_goods(tag, player_tag).is_empty():
			embargoed[tag] = true


## Tableau de couleurs prêt à remplir : mer pour l'id 0 et les zones maritimes, « sans propriétaire » ailleurs.
func new_colors() -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(max_id + 1)
	colors.fill(unowned_color)
	colors[0] = sea_color
	for key: String in sea_zones.keys():
		var zone_id := int(key)
		if zone_id > 0 and zone_id <= max_id:
			colors[zone_id] = sea_color
	return colors


func owner_of(province: Dictionary) -> Dictionary:
	return countries.get(str(province.get("owner", "")), {})

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
## Valeurs de la partie en cours par pays, lues par les dégradés : nom → {tag: valeur} (stabilité, soutien…).
var country_values: Dictionary = {}
## Idéologie au pouvoir dans la partie en cours (tag → idéologie), après d'éventuelles alternances.
var country_ideologies: Dictionary = {}
## Organisations de la partie en cours (créées en jeu comprises) et appartenances : tag → [identifiants].
var country_organizations: Dictionary = {}
## Partie en cours, pour les modes qui recalculent à la demande (votes par province).
var simulation: SimState = null
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
	relations.clear()
	if not player_tag.is_empty() and not state.diplomacy_settings.is_empty():
		for tag: String in state.countries.keys():
			if tag != player_tag:
				relations[tag] = state.diplomacy.relation(player_tag, tag)
	trade_shares.clear()
	embargoed.clear()
	_refresh_society(state)
	simulation = state
	if not state.diplomacy.organizations.is_empty():
		organizations = state.diplomacy.organizations
		country_organizations.clear()
		for org_id: String in organizations.keys():
			for member: Variant in (organizations[org_id] as Dictionary).get("members", []):
				if not country_organizations.has(member):
					country_organizations[member] = []
				(country_organizations[member] as Array).append(org_id)
	country_ideologies.clear()
	for tag: String in state.countries.keys():
		var ideology := (state.countries[tag] as CountryState).politics.ideology
		if not ideology.is_empty():
			country_ideologies[tag] = ideology
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


func _refresh_society(state: SimState) -> void:
	country_values.clear()
	var stability: Dictionary = {}
	var support: Dictionary = {}
	var unrest: Dictionary = {}
	for tag: String in state.countries.keys():
		var society: SocietyState = (state.countries[tag] as CountryState).society
		if not society.group_shares.is_empty():
			stability[tag] = society.stability
			support[tag] = society.support
			unrest[tag] = float((state.countries[tag] as CountryState).crisis_effects.get("severity", 0))
	if not stability.is_empty():
		country_values["stability"] = stability
		country_values["support"] = support
		country_values["unrest"] = unrest


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


## Idéologie au pouvoir : celle de la partie en cours, sinon celle des données.
func ideology_of(tag: String) -> String:
	return str(country_ideologies.get(tag, (countries.get(tag, {}) as Dictionary).get("ideology", "")))


## Organisations d'un pays : celles de la partie en cours, sinon celles des données.
func organizations_of(tag: String) -> Array:
	if not country_organizations.is_empty():
		return country_organizations.get(tag, [])
	return (countries.get(tag, {}) as Dictionary).get("organizations", [])


func owner_of(province: Dictionary) -> Dictionary:
	return countries.get(str(province.get("owner", "")), {})

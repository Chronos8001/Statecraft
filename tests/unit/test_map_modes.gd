extends GutTest

const SEA := Color(0, 0, 0.5)
const UNOWNED := Color(0.5, 0.5, 0.5)
const NO_DATA := Color(0.3, 0.3, 0.3)


func _context() -> MapModeContext:
	var context := MapModeContext.new()
	context.max_id = 4
	context.sea_color = SEA
	context.unowned_color = UNOWNED
	context.no_data_color = NO_DATA
	context.provinces = {
		"1": {"owner": "AAA", "controller": "AAA", "terrain": "plains", "population": 1000, "area_km2": 10.0,
			"infrastructure": 10, "resources": {"oil": 2, "coal": 5}},
		"2": {"owner": "AAA", "controller": "BBB", "terrain": "desert", "population": 10, "area_km2": 10.0,
			"infrastructure": 0, "resources": {}},
		"3": {"owner": "BBB", "controller": "BBB", "terrain": "unknown", "population": 0, "area_km2": 0.0,
			"infrastructure": 5, "resources": {}},
		"4": {"terrain": "tundra", "population": 0, "area_km2": 5.0, "infrastructure": 0, "resources": {}},
	}
	context.countries = {
		"AAA": {"color": "#FF0000", "ideology": "liberal", "population": 1000000,
			"economy": {"gdp_billion_usd": 50.0}, "organizations": ["pact", "forum"]},
		"BBB": {"color": "#0000FF"},
	}
	context.terrains = {"plains": {"name_key": "TERRAIN_PLAINS", "color": "#00FF00"},
		"desert": {"name_key": "TERRAIN_DESERT", "color": "#FFFF00"}}
	context.ideologies = {"liberal": {"name_key": "IDEOLOGY_LIBERAL", "color": "#FFAA00"}}
	context.organizations = {"pact": {"kind": "military_alliance", "color": "#123456", "name": "Pact"},
		"forum": {"kind": "economic_forum", "color": "#654321", "name": "Forum"}}
	context.resources = {"oil": {"name_key": "RESOURCE_OIL", "color": "#111111"},
		"coal": {"name_key": "RESOURCE_COAL", "color": "#222222"}}
	return context


func test_gradient_linear_and_log() -> void:
	var linear := ColorGradient.from_stops([[0, "#000000"], [10, "#FFFFFF"]], false)
	assert_eq(linear.sample(-5.0), Color.BLACK)
	assert_eq(linear.sample(20.0), Color.WHITE)
	assert_almost_eq(linear.sample(5.0).r, 0.5, 0.01)
	var logarithmic := ColorGradient.from_stops([[1, "#000000"], [100, "#FFFFFF"]], true)
	assert_almost_eq(logarithmic.sample(10.0).r, 0.5, 0.01)


func test_political_mode() -> void:
	var colors := PoliticalMapMode.new("political", {}).compute_colors(_context())
	assert_eq(colors.size(), 5)
	assert_eq(colors[0], SEA)
	assert_eq(colors[1], Color.RED)
	assert_eq(colors[3], Color.BLUE)
	assert_eq(colors[4], UNOWNED)


func test_terrain_mode() -> void:
	var colors := TerrainMapMode.new("terrain", {}).compute_colors(_context())
	assert_eq(colors[1], Color.GREEN)
	assert_eq(colors[2], Color.YELLOW)
	assert_eq(colors[3], NO_DATA, "terrain inconnu")


func test_population_density_gradient() -> void:
	var definition := {"value": "population_density", "logarithmic": false,
		"stops": [[0, "#000000"], [100, "#FFFFFF"]]}
	var colors := ProvinceGradientMapMode.new("population", definition).compute_colors(_context())
	assert_eq(colors[1], Color.WHITE, "100 hab./km²")
	assert_almost_eq(colors[2].r, 0.01, 0.005, "1 hab./km²")
	assert_eq(colors[3], Color.BLACK, "surface nulle")


func test_country_gradient_without_data() -> void:
	var definition := {"value": "gdp_per_capita", "logarithmic": false,
		"stops": [[0, "#000000"], [50000, "#FFFFFF"]]}
	var mode := CountryGradientMapMode.new("gdp", definition)
	assert_almost_eq(float(CountryGradientMapMode.country_value(_context().countries["AAA"], "gdp_per_capita")), 50000.0, 0.1)
	var colors := mode.compute_colors(_context())
	assert_eq(colors[1], Color.WHITE)
	assert_eq(colors[3], NO_DATA, "pays sans PIB")
	assert_eq(colors[4], UNOWNED)
	assert_eq(mode.get_legend(_context()).back()["label_key"], "LEGEND_NO_DATA")


func test_ideology_and_alliance_modes() -> void:
	var ideology := IdeologyMapMode.new("ideology", {}).compute_colors(_context())
	assert_eq(ideology[1], Color.html("#FFAA00"))
	assert_eq(ideology[3], NO_DATA)
	var definition := {"organization_kinds": ["military_alliance"], "none_color": "#FFFFFF"}
	var alliance := AllianceMapMode.new("alliances", definition).compute_colors(_context())
	assert_eq(alliance[1], Color.html("#123456"))
	assert_eq(alliance[3], NO_DATA, "membres inconnus")


func test_relations_mode_marks_player() -> void:
	var context := _context()
	context.player_tag = "AAA"
	context.relations = {"BBB": -100.0}
	var definition := {"player_color": "#FFFF00", "stops": [[-100, "#FF0000"], [0, "#808080"], [100, "#00FF00"]]}
	var colors := RelationsMapMode.new("relations", definition).compute_colors(context)
	assert_eq(colors[1], Color.YELLOW)
	assert_eq(colors[3], Color.RED)


func test_resource_mode_uses_dominant_resource() -> void:
	assert_eq(ResourceMapMode.dominant_resource(_context().provinces["1"]), "coal")
	var colors := ResourceMapMode.new("resources", {"none_color": "#FFFFFF"}).compute_colors(_context())
	assert_eq(colors[1], Color.html("#222222"))
	assert_eq(colors[2], Color.WHITE)


func test_control_mode_tints_occupied() -> void:
	var definition := {"occupied_color": "#FFFFFF", "occupied_strength": 0.5}
	var colors := ControlMapMode.new("control", definition).compute_colors(_context())
	assert_eq(colors[1], Color.RED)
	assert_eq(colors[2], Color.BLUE.lerp(Color.WHITE, 0.5), "occupée par BBB")


func test_trade_mode_shows_partners_and_embargoes() -> void:
	var definition := {"player_color": "#FFFFFF", "embargo_color": "#FF0000",
		"stops": [[0.0, "#000000"], [1.0, "#00FF00"]]}
	var context := _context()
	context.player_tag = "BBB"
	context.trade_shares = {"AAA": 1.0}
	var colors := TradeMapMode.new("trade", definition).compute_colors(context)
	assert_eq(colors[1], Color.GREEN, "premier partenaire")
	context.embargoed = {"AAA": true}
	colors = TradeMapMode.new("trade", definition).compute_colors(context)
	assert_eq(colors[1], Color.RED, "embargo")


func test_registry_builds_all_game_modes_in_order() -> void:
	var registry := MapModeRegistry.from_definitions(DataLoader.get_category("map_modes"))
	assert_eq(registry.modes.size(), 12)
	assert_eq(registry.modes[0].id, "political")
	assert_eq(registry.index_of("stability"), 10)
	assert_eq(registry.index_of("trade"), 11)
	var context := MapModeContext.from_game_data()
	for mode: MapMode in registry.modes:
		assert_eq(mode.compute_colors(context).size(), context.max_id + 1, mode.id)

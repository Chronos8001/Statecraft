extends GutTest
## Arbres nationaux : données valides, nœuds qui ne se chevauchent pas, bon arbre pour chaque pays, et les
## uchronies jouées dans le vrai monde (fédération européenne, Groenland, Taïwan, Texas).

const LOT_1 := ["USA", "CHN", "RUS", "IND", "FRA", "DEU"]
const MIN_GAP := 2.0


func _trees() -> Dictionary:
	return DecisionSystem.resolve_trees(DataLoader.get_category("focus_trees"))


func test_trees_are_valid_and_readable() -> void:
	var trees := _trees()
	var errors := DecisionSystem.validate_definitions(DataLoader.get_category("decisions"), trees,
		DataLoader.get_category("events").keys())
	assert_eq(errors.size(), 0, "\n".join(errors))
	for tag: String in LOT_1:
		var tree: Dictionary = trees[tag.to_lower()]
		assert_eq(tree["countries"], [tag])
		var nodes: Dictionary = tree["nodes"]
		assert_gt(nodes.size(), 45, "%s : nœuds nationaux et génériques" % tag)
		var rows: Dictionary = {}
		for node: Dictionary in nodes.values():
			var y := float(node["y"])
			if not rows.has(y):
				rows[y] = []
			(rows[y] as Array).append(float(node["x"]))
		for y: Variant in rows.keys():
			var xs: Array = rows[y]
			xs.sort()
			for index: int in range(1, xs.size()):
				assert_gte(float(xs[index]) - float(xs[index - 1]), MIN_GAP, "%s : nœuds trop proches (ligne %s)" % [tag, y])


func test_countries_get_their_tree() -> void:
	GameState.new_game(31, &"BRA")
	for tag: String in LOT_1:
		assert_eq(GameState.sim.get_country(tag).focus_tree, tag.to_lower())
	assert_eq(GameState.sim.get_country("BRA").focus_tree, "generic")


func test_european_federation() -> void:
	GameState.new_game(32, &"BRA")
	var state := GameState.sim
	state.diplomacy.change_relation("FRA", "DEU", 100.0)
	EventSystem.fire(state, "european_federation_proposal", {"country": "DEU", "from": "FRA"})
	if state.get_country("DEU") != null:
		EventSystem.choose(state, "european_federation_proposal", {"country": "DEU", "from": "FRA"}, 0)
	assert_null(state.get_country("DEU"), "l'Allemagne rejoint la Fédération")
	assert_eq(str(state.country_overrides["FRA"]["name_key"]), "COUNTRY_EUF")
	assert_gt(state.scheduled_events.filter(func(entry: Dictionary) -> bool:
		return str(entry["id"]) == "european_federation_invitation" and str(entry["from"]) == "FRA").size(), 10,
		"invitations aux autres membres de l'UE")
	for _hour: int in 70 * GameDate.HOURS_PER_DAY:
		GameState.advance_hour()
	assert_eq(state.scheduled_events.filter(func(entry: Dictionary) -> bool:
		return str(entry["id"]) == "european_federation_invitation").size(), 0, "toutes les invitations ont eu lieu")


func test_greenland_purchase() -> void:
	GameState.new_game(33, &"BRA")
	var state := GameState.sim
	EventSystem.choose(state, "greenland_purchase_offer", {"country": "DNK", "from": "USA"}, 0)
	assert_eq(ControlSystem.owner(state, "1513"), "USA")
	assert_eq(ControlSystem.owner(state, "850"), "DNK", "le Danemark garde son territoire européen")


func test_taiwan_by_force_and_texas() -> void:
	GameState.new_game(34, &"BRA")
	var state := GameState.sim
	state.diplomacy.world_tension = 70.0
	var china := state.get_country("CHN")
	for node_id: String in ["chn_15th_plan", "chn_tech_self_reliance", "chn_chip_independence", "chn_taiwan_pressure"]:
		china.focus_done[node_id] = true
	ScriptEffects.apply(state, {"country": "CHN", "from": ""},
		(_trees()["chn"]["nodes"]["chn_taiwan_pressure"] as Dictionary)["effects"])
	assert_eq(DecisionSystem.focus_refusal(state, china, "chn_reunification_by_force"), "")
	assert_true(DecisionSystem.start_focus(state, china, "chn_reunification_by_force"))
	DecisionSystem.complete_focus(state, china)
	assert_true(WarSystem.at_war(state, "CHN", "TWN"), "guerre déclarée")
	EventSystem.choose(state, "texas_independence_crisis", {"country": "USA", "from": ""}, 0)
	assert_not_null(state.get_country("TEX"))
	assert_eq(ControlSystem.owner(state, "4350"), "TEX")

extends GutTest
## Arbres nationaux : données valides, nœuds qui ne se chevauchent pas, bon arbre pour chaque pays, et les
## uchronies jouées dans le vrai monde (fédération européenne, Groenland, Taïwan, Texas).

const NATIONAL := ["USA", "CHN", "RUS", "IND", "FRA", "DEU", "GBR", "JPN", "KOR", "PRK", "TWN", "UKR", "BRA", "MEX", "ARG",
	"CAN", "AUS", "IDN"]
const MIN_GAP := 2.0


func _trees() -> Dictionary:
	return DecisionSystem.resolve_trees(DataLoader.get_category("focus_trees"))


func test_trees_are_valid_and_readable() -> void:
	var trees := _trees()
	var errors := DecisionSystem.validate_definitions(DataLoader.get_category("decisions"), trees,
		DataLoader.get_category("events").keys())
	assert_eq(errors.size(), 0, "\n".join(errors))
	for tag: String in NATIONAL:
		var tree: Dictionary = trees[tag.to_lower()]
		assert_eq(tree["countries"], [tag])
		var nodes: Dictionary = tree["nodes"]
		assert_gte(nodes.size(), 44, "%s : nœuds nationaux et génériques" % tag)
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
	for tag: String in NATIONAL:
		assert_eq(GameState.sim.get_country(tag).focus_tree, tag.to_lower())
	assert_eq(GameState.sim.get_country("CHL").focus_tree, "generic")


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


func test_korean_reunification() -> void:
	GameState.new_game(35, &"BRA")
	var state := GameState.sim
	EventSystem.choose(state, "korean_reunification_proposal", {"country": "PRK", "from": "KOR"}, 0)
	assert_null(state.get_country("PRK"))
	assert_eq(ControlSystem.owner(state, "3239"), "KOR", "Pyongyang")
	assert_eq(str(state.country_overrides["KOR"]["name_key"]), "COUNTRY_COR")


func test_scotland_ireland_and_ukraine() -> void:
	GameState.new_game(36, &"BRA")
	var state := GameState.sim
	EventSystem.choose(state, "scotland_votes_yes", {"country": "GBR", "from": ""}, 0)
	assert_not_null(state.get_country("SCO"))
	var trees := _trees()
	ScriptEffects.apply(state, {"country": "GBR", "from": ""},
		(trees["gbr"]["nodes"]["gbr_irish_unity"] as Dictionary)["effects"])
	assert_eq(ControlSystem.owner(state, "1267"), "IRL", "Belfast")
	ScriptEffects.apply(state, {"country": "UKR", "from": ""},
		(trees["ukr"]["nodes"]["ukr_eu_accession"] as Dictionary)["effects"])
	ScriptEffects.apply(state, {"country": "UKR", "from": ""},
		(trees["ukr"]["nodes"]["ukr_nato_membership"] as Dictionary)["effects"])
	assert_true(OrganizationSystem.is_member(state, "eu", "UKR"))
	assert_true(OrganizationSystem.is_member(state, "nato", "UKR"))
	for _hour: int in 31 * GameDate.HOURS_PER_DAY:
		GameState.advance_hour()


func test_lot_3_scenarios() -> void:
	GameState.new_game(37, &"FRA")
	var state := GameState.sim
	var trees := _trees()
	EventSystem.choose(state, "quebec_votes_yes", {"country": "CAN", "from": ""}, 0)
	assert_not_null(state.get_country("QUE"))
	EventSystem.choose(state, "alberta_independence_crisis", {"country": "CAN", "from": ""}, 0)
	assert_eq(ControlSystem.owner(state, "565"), "ABT")
	ScriptEffects.apply(state, {"country": "IDN", "from": ""},
		(trees["idn"]["nodes"]["idn_papua_self_determination"] as Dictionary)["effects"])
	assert_not_null(state.get_country("PAP"))
	ScriptEffects.apply(state, {"country": "ARG", "from": ""},
		(trees["arg"]["nodes"]["arg_malvinas_claim"] as Dictionary)["effects"])
	ScriptEffects.apply(state, {"country": "ARG", "from": ""},
		(trees["arg"]["nodes"]["arg_malvinas_war"] as Dictionary)["effects"])
	assert_true(WarSystem.at_war(state, "ARG", "GBR"), "guerre des Malouines")
	state.rng.seed = 1
	for _attempt: int in 10:
		ScriptEffects.apply(state, {"country": "AUS", "from": ""},
			(trees["aus"]["nodes"]["aus_republic_referendum"] as Dictionary)["effects"])
	assert_eq(state.get_country("AUS").politics.regime, "parliamentary_republic", "la république finit par passer")
	for _hour: int in 31 * GameDate.HOURS_PER_DAY:
		GameState.advance_hour()

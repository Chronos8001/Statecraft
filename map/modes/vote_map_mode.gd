class_name VoteMapMode
extends MapMode
## Parti en tête dans chaque province d'après les sondages du moment (couleur du parti) ; pays sans partis
## ou sans parlement en couleur « pas de données ».


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var leaders: Dictionary = {}
	var state := context.simulation
	if state != null and not state.politics_definitions.is_empty():
		var parties: Dictionary = state.politics_definitions.get("parties", {})
		var provinces: Dictionary = state.politics_definitions.get("provinces", {})
		var settings := ElectionSystem.settings_of(state)
		for tag: String in state.countries.keys():
			var politics: PoliticsState = (state.countries[tag] as CountryState).politics
			if politics.parties.is_empty():
				continue
			var national: Dictionary = {}
			var groups_of: Dictionary = {}
			for party: PartyState in politics.parties.values():
				national[party.id] = party.poll
				groups_of[party.id] = party.party_group
			var regional := ElectionModel.regional_votes(national, groups_of, provinces.get(tag, []), politics.other_poll,
				settings)
			var winners := ElectionModel.regional_winners(regional)
			for province_id: Variant in winners.keys():
				leaders[province_id] = Color.html(str((parties.get(winners[province_id], {}) as Dictionary).get(
					"color", "#808080")))
	var colors := context.new_colors()
	for key: String in context.provinces.keys():
		var province_id := int(key)
		if province_id <= 0 or province_id > context.max_id:
			continue
		var owner := str((context.provinces[key] as Dictionary).get("owner", ""))
		colors[province_id] = context.unowned_color if owner.is_empty() else leaders.get(key, context.no_data_color)
	return colors


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	return [_entry(Color.html(str(definition.get("hint_color", "#FFFFFF"))), "LEGEND_VOTE_HINT"),
		_entry(context.no_data_color, "LEGEND_NO_PARTIES")]

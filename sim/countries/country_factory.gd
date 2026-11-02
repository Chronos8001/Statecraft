class_name CountryFactory
extends RefCounted
## Naissance d'un pays (sécession, indépendance) à partir d'une définition de data/releasables : provinces, nom,
## couleur, régime. Le nouveau pays reprend la part du pays d'origine qui correspond à la population de ses
## provinces (économie, dette, armée, énergie, consommation de ressources, commerce) et ses taux (croissance,
## budget, société, lois) ; ses partis, dirigeants et ministres sont générés ; ses relations sont celles du pays
## d'origine, sauf avec lui.

const EVENT_RELEASED := &"country_released"
const PERCENT := 100.0
const MILLION := 1.0e6


## Pays qui donnerait naissance à ce pays (propriétaire de la capitale prévue), "" si impossible.
static func parent_of(state: SimState, definition_id: String) -> String:
	var definition: Dictionary = state.releasable_definitions.get(definition_id, {})
	if definition.is_empty() or state.get_country(str(definition.get("tag", ""))) != null:
		return ""
	var parent := ControlSystem.owner(state, str(int(definition.get("capital", -1))))
	if parent.is_empty() or state.get_country(parent) == null or WarSystem.is_rebel(state, parent):
		return ""
	var owned := _released_provinces(state, definition, parent)
	if owned.is_empty() or owned.size() >= (state.provinces_by_owner.get(parent, []) as Array).size():
		return ""
	return parent


static func release_refusal(state: SimState, definition_id: String) -> String:
	return "" if not parent_of(state, definition_id).is_empty() else "RELEASE_INVALID"


static func _released_provinces(state: SimState, definition: Dictionary, parent: String) -> Array[String]:
	var result: Array[String] = []
	for province_id: Variant in definition.get("provinces", []):
		var id := str(int(province_id)) if province_id is float or province_id is int else str(province_id)
		if ControlSystem.owner(state, id) == parent:
			result.append(id)
	return result


## Crée le pays ; renvoie son tag, ou "" si c'est impossible.
static func release(state: SimState, definition_id: String) -> String:
	var parent_tag := parent_of(state, definition_id)
	if parent_tag.is_empty():
		return ""
	var definition: Dictionary = state.releasable_definitions[definition_id]
	var tag := str(definition["tag"])
	var parent := state.get_country(parent_tag)
	var provinces := _released_provinces(state, definition, parent_tag)
	var share := _population_share(state, parent_tag, provinces)
	var gdp_before := TradeSystem.current_gdp(state, parent_tag)
	var parties := _create_parties(state, parent, tag, definition)
	var data := _build_data(state, parent, tag, definition, share, parties)
	if not state.country_data.has(tag):
		state.country_data = state.country_data.duplicate()
	state.country_data[tag] = data
	var country := WorldSetup.create_country(state, tag, data)
	_install_leaders(state, country, parties)
	country.laws = parent.laws.duplicate()
	LawSystem.apply_effects(country, state)
	if country.research != null and parent.research != null:
		country.research.known = parent.research.known.duplicate()
		country.research.start_known = country.research.known.duplicate()
	_split_parent(state, parent, country)
	for province_id: String in provinces:
		WarEnd.cede(state, province_id, tag, true, false)
	CountryLifecycle.recompute_land_neighbors(state)
	_split_trade(state, parent_tag, tag, gdp_before)
	_setup_relations(state, parent_tag, tag, definition)
	_place_armies(state, tag, provinces, str(int(definition.get("capital", -1))))
	state.country_overrides[tag] = {"name_key": str(definition.get("name_key", "")),
		"color": str(definition.get("color", "#808080")), "flag": str(definition.get("flag", "")),
		"capital": int(definition.get("capital", -1)), "regime": str(data.get("regime", ""))}
	state.created_countries[tag] = definition_id
	state.dissolved.erase(tag)
	DecisionSystem.assign_trees(state)
	state.gdp_ranks.clear()
	state.add_event(EVENT_RELEASED, tag, {"target": parent_tag})
	return tag


static func _population_share(state: SimState, parent: String, provinces: Array[String]) -> float:
	var definitions: Dictionary = state.energy_definitions.get("provinces", {})
	var released := 0.0
	var total := 0.0
	for province_id: Variant in state.provinces_by_owner.get(parent, []):
		var population := float((definitions.get(str(province_id), {}) as Dictionary).get("population", 0.0))
		total += population
		if provinces.has(str(province_id)):
			released += population
	return clampf(released / total, 0.0, 1.0) if total > 0.0 else 0.0


## Données du nouveau pays : celles du pays d'origine, quantités réduites à sa part, valeurs du moment.
static func _build_data(state: SimState, parent: CountryState, tag: String, definition: Dictionary, share: float,
		parties: Dictionary) -> Dictionary:
	var data: Dictionary = (state.country_data.get(parent.tag, {}) as Dictionary).duplicate(true)
	var currency := state.get_currency(parent.economy.currency)
	data["name_key"] = str(definition.get("name_key", ""))
	data["color"] = str(definition.get("color", "#808080"))
	data["capital"] = int(definition.get("capital", -1))
	var regime := str(definition.get("regime", parent.politics.regime))
	if not definition.has("regime") and regime.contains("monarchy"):
		regime = "parliamentary_republic"
	data["regime"] = regime
	data["culture"] = str(definition.get("culture", parent.politics.culture))
	data["ideology"] = str(definition.get("ideology", parent.politics.ideology))
	data["population"] = int(float(parent.economy.population) * share)
	data["organizations"] = []
	data["relations"] = {}
	data["currency"] = parent.economy.currency
	var economy: Dictionary = data.get("economy", {})
	economy["gdp_billion_usd"] = TradeSystem.current_gdp(state, parent.tag) * share
	economy["debt_to_gdp"] = parent.economy.debt_ratio(currency) if currency != null else 0.0
	economy["growth"] = parent.economy.growth
	economy["inflation"] = parent.economy.inflation
	economy["unemployment"] = parent.economy.unemployment
	data["economy"] = economy
	if parent.military != null:
		data["military"] = {"active_personnel": parent.military.active_personnel * share,
			"reserve_personnel": parent.military.reserve_personnel * share}
	var forces: Dictionary = data.get("armed_forces", {})
	forces["nuclear_warheads"] = 0
	data["armed_forces"] = forces
	var generation: Dictionary = (data.get("energy", {}) as Dictionary).get("generation", {})
	for source: Variant in generation.keys():
		generation[source] = float(generation[source]) * share
	var resources: Dictionary = data.get("resources", {})
	for resource_id: Variant in resources.keys():
		var entry: Dictionary = resources[resource_id]
		entry["production"] = 0.0
		entry["consumption"] = float(entry.get("consumption", 0.0)) * share
	var water: Dictionary = data.get("water", {})
	water["renewable"] = float(water.get("renewable", 0.0)) * share
	var research: Dictionary = data.get("research", {})
	research["universities"] = roundi(float(research.get("universities", 0)) * share)
	data["parliament"] = _build_parliament(parent, parties, share)
	return data


## Partis du nouveau pays : un par parti du pays d'origine (même idéologie, nouveau nom, nouveau chef).
static func _create_parties(state: SimState, parent: CountryState, tag: String, definition: Dictionary) -> Dictionary:
	var mapping: Dictionary = {}
	var definitions: Dictionary = (state.politics_definitions.get("parties", {}) as Dictionary).duplicate()
	var culture := str(definition.get("culture", parent.politics.culture))
	var names := GovernmentModel.generator(state, "%s|parties|%d" % [tag, state.date.to_day_number()])
	var taken: Array = []
	var ids: Array = parent.politics.parties.keys()
	ids.sort()
	for index: int in ids.size():
		var party: PartyState = parent.politics.parties[ids[index]]
		var party_id := "pty_%s_%d" % [tag.to_lower(), index + 1]
		var entry := {"country": tag, "ideology": party.ideology, "name": party_id, "abbreviation": "", "color": "#808080"}
		if names != null:
			var named := names.generate_party_name(culture, party.ideology, taken)
			if not named.is_empty():
				entry["name"] = named["name"]
				entry["abbreviation"] = named["abbreviation"]
				taken.append(named["name"])
			entry["color"] = names.party_color(party.ideology)
		definitions[party_id] = entry
		mapping[str(ids[index])] = party_id
	state.politics_definitions["parties"] = definitions
	return mapping


static func _build_parliament(parent: CountryState, parties: Dictionary, share: float) -> Dictionary:
	var politics := parent.politics
	var seats := clampi(roundi(float(politics.seats) * sqrt(share)), mini(40, politics.seats), maxi(politics.seats, 1))
	var party_seats: Dictionary = {}
	for party_id: Variant in politics.parties.keys():
		var party: PartyState = politics.parties[party_id]
		party_seats[parties[party_id]] = {"seats": roundi(float(party.seats) / maxf(float(politics.seats), 1.0) * seats),
			"vote": party.vote, "poll": party.poll}
	var government: Array = []
	for party_id: String in politics.government:
		if parties.has(party_id):
			government.append(parties[party_id])
	var result := {"seats": seats, "parties": party_seats, "government": government, "other_seats": 0,
		"other_vote": politics.other_vote, "other_poll": politics.other_poll,
		"election": {"year": politics.election_year, "month": politics.election_month}, "term_years": politics.term_years,
		"next_election": {"year": politics.next_election_year, "month": politics.next_election_month},
		"system": {"type": politics.system_type, "threshold": politics.threshold, "list_share": politics.list_share}}
	if politics.has_presidency:
		result["presidency"] = {"election": {"year": politics.presidential_year, "month": politics.presidential_month},
			"term_years": politics.presidential_term, "two_rounds": politics.two_rounds,
			"next_election": {"year": politics.next_presidential_year, "month": politics.next_presidential_month}}
	return result


## Chefs de parti et dirigeants : le chef du premier parti au pouvoir dirige le pays.
static func _install_leaders(state: SimState, country: CountryState, parties: Dictionary) -> void:
	var definitions: Dictionary = state.politics_definitions.get("parties", {})
	for party_id: Variant in parties.values():
		var leader := GovernmentModel.make_character(state, country, str(party_id), "%s|leader|%s" % [country.tag, party_id])
		if leader.is_empty():
			continue
		var character_id := "%s%d" % [GovernmentSystem.CHARACTER_PREFIX, state.next_character_id]
		state.next_character_id += 1
		state.characters[character_id] = leader
		(definitions[party_id] as Dictionary)["leader"] = character_id
	var ruling := country.politics.ruling_party()
	var head := LeaderSystem.party_leader(state, ruling) if not ruling.is_empty() else ""
	if head.is_empty():
		var general := GovernmentModel.make_character(state, country, "", "%s|head" % country.tag)
		if general.is_empty():
			return
		head = "%s%d" % [GovernmentSystem.CHARACTER_PREFIX, state.next_character_id]
		state.next_character_id += 1
		state.characters[head] = general
	country.politics.head_of_state = head
	country.politics.head_of_government = head


## Le pays d'origine perd ce que le nouveau pays reprend : population, PIB, électricité, dette, soldats,
## consommation de ressources.
static func _split_parent(state: SimState, parent: CountryState, country: CountryState) -> void:
	parent.economy.population = maxi(parent.economy.population - country.economy.population, 1)
	parent.economy.real_gdp = maxf(parent.economy.real_gdp - country.economy.real_gdp, 0.0)
	parent.energy.demand = maxf(parent.energy.demand - country.energy.demand, 0.0)
	var currency := state.get_currency(country.economy.currency)
	if currency != null:
		InvestmentSystem.add_debt_usd(parent, state, -country.economy.total_debt(currency) / currency.fx_factor())
	if parent.military != null and country.military != null:
		parent.military.active_personnel = maxf(parent.military.active_personnel - country.military.active_personnel, 0.0)
		parent.military.reserve_personnel = maxf(parent.military.reserve_personnel - country.military.reserve_personnel,
			0.0)
	for resource_id: Variant in country.resources.consumption_base.keys():
		parent.resources.consumption_base[resource_id] = maxf(float(parent.resources.consumption_base.get(resource_id,
			0.0)) - float(country.resources.consumption_base[resource_id]), 0.0)


## Commerce : le nouveau pays reprend sa part des échanges du pays d'origine ; leurs échanges mutuels
## deviennent internationaux ; les PIB de départ sont partagés pour garder les mêmes proportions.
static func _split_trade(state: SimState, parent: String, tag: String, gdp_before: float) -> void:
	var trade := state.trade
	if trade.start_flows.is_empty():
		return
	var gdp_after := TradeSystem.current_gdp(state, parent)
	var kept := clampf(gdp_after / gdp_before, 0.0, 1.0) if gdp_before > 0.0 else 1.0
	var taken := 1.0 - kept
	var own: Dictionary = {}
	var parent_row: Dictionary = trade.start_flows.get(parent, {})
	for importer: Variant in parent_row.keys():
		own[importer] = float(parent_row[importer]) * taken
		parent_row[importer] = float(parent_row[importer]) * kept
	for exporter: Variant in trade.start_flows.keys():
		var row: Dictionary = trade.start_flows[exporter]
		if row.has(parent) and str(exporter) != parent:
			row[tag] = float(row[parent]) * taken
			row[parent] = float(row[parent]) * kept
	var mutual := float(state.trade_settings.get("secession_mutual_trade", 0.0)) * float(trade.start_gdp.get(parent, 0.0)) \
		* taken * kept
	own[parent] = mutual
	parent_row[tag] = mutual
	trade.start_flows[tag] = own
	var parent_tariffs: Dictionary = trade.start_tariffs.get(parent, {})
	trade.start_tariffs[tag] = parent_tariffs.duplicate()
	(trade.start_tariffs[tag] as Dictionary)[parent] = 0.0
	parent_tariffs[tag] = 0.0
	for exporter: Variant in trade.start_tariffs.keys():
		var tariffs: Dictionary = trade.start_tariffs[exporter]
		if tariffs.has(parent) and not tariffs.has(tag):
			tariffs[tag] = tariffs[parent]
	var start_gdp := float(trade.start_gdp.get(parent, 0.0))
	trade.start_gdp[tag] = maxf(start_gdp * taken, 0.001)
	trade.start_gdp[parent] = maxf(start_gdp * kept, 0.001)
	trade.surcharges[tag] = {}
	trade.dirty = true
	TradeSystem.refresh_tariff_changes(state)


## Relations : celles du pays d'origine avec le reste du monde, une valeur propre avec le pays d'origine ;
## membre de l'ONU.
static func _setup_relations(state: SimState, parent: String, tag: String, definition: Dictionary) -> void:
	var diplomacy := state.diplomacy
	for other: String in state.countries.keys():
		if other == tag or other == parent:
			continue
		diplomacy.start_relations[DiplomacyState.pair_key(tag, other)] = diplomacy.relation(parent, other)
	diplomacy.start_relations[DiplomacyState.pair_key(tag, parent)] = float(definition.get("relation_with_parent",
		(state.diplomacy_settings.get("secession", {}) as Dictionary).get("relation_with_parent", 0.0)))
	diplomacy.influence_points[tag] = 0.0
	for org_id: Variant in definition.get("organizations", ["un"]):
		if diplomacy.organizations.has(org_id):
			OrganizationSystem.add_member(state, str(org_id), tag)


static func _place_armies(state: SimState, tag: String, provinces: Array[String], capital: String) -> void:
	var country := state.get_country(tag)
	var settings := ArmyGroupModel.settings_of(state)
	if settings.is_empty() or country.military == null or not country.military.has_branch("land"):
		return
	var land := country.military.personnel(ArmyGroupModel.reserve_share(state)) \
		* float((country.military.branches["land"] as Dictionary)["share"])
	var count := clampi(ceili(land / float(settings.get("personnel_per_group", 1.0))), 1, int(settings.get("max_groups", 1)))
	ArmyGroupModel._place(state, tag, provinces, capital, count, settings, {})

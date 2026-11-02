class_name WorldSetup
extends RefCounted
## Crée l'état des pays et des monnaies au début de la partie, à partir des données chargées.
## Le modèle est calé pour que chaque économie parte à l'équilibre : taux neutres et écart de note
## propres à chaque pays reprennent la situation réelle du 1er janvier 2026.

const BILLION := 1.0e9
const PRESIDENTIAL_REGIME := "presidential_republic"


## budget_definitions : {taxes, spending, settings} (catégories budget_taxes, budget_spending, defines.budget).
## resources : catégorie « resources » ; resource_definitions : {straits, sectors, settings}.
static func populate(state: SimState, countries: Dictionary, currencies: Dictionary, settings: Dictionary,
		budget_definitions: Dictionary = {}, resources: Dictionary = {}, resource_definitions: Dictionary = {},
		trade_definitions: Dictionary = {}, energy_definitions: Dictionary = {},
		investment_settings: Dictionary = {}, society_definitions: Dictionary = {},
		politics_definitions: Dictionary = {}, diplomacy_definitions: Dictionary = {},
		military_definitions: Dictionary = {}, research_definitions: Dictionary = {}) -> void:
	state.economy_settings = settings
	state.investment_settings = investment_settings
	state.budget_definitions = budget_definitions
	state.resource_definitions = resource_definitions
	state.markets.clear()
	state.closed_straits.clear()
	for resource_id: String in resources.keys():
		var market_data: Dictionary = (resources[resource_id] as Dictionary).get("market", {})
		if not market_data.is_empty():
			state.markets[resource_id] = _create_market(resource_id, market_data)
	state.countries.clear()
	state.currencies.clear()
	state.country_data = countries
	var ratings := CreditRating.new(settings)
	var tags: Array = countries.keys()
	tags.sort()

	for currency_id: String in currencies.keys():
		state.currencies[currency_id] = _create_currency(currency_id, currencies[currency_id])
	for tag: String in tags:
		var currency_id := str((countries[tag] as Dictionary).get("currency", ""))
		var currency: CurrencyState = state.currencies.get(currency_id)
		if currency != null:
			currency.members.append(tag)
	for currency_id: String in currencies.keys():
		var currency: CurrencyState = state.currencies[currency_id]
		# Pays émetteur indiqué dans les données ; à défaut, l'unique pays qui l'utilise.
		currency.issuer = str((currencies[currency_id] as Dictionary).get("issuer",
			currency.members[0] if currency.members.size() == 1 else ""))

	for tag: String in tags:
		var country := CountryState.new()
		country.tag = tag
		_setup_economy(country, countries[tag], state, ratings, settings)
		_setup_budget(country, countries[tag], state)
		_setup_resources(country, countries[tag], state)
		_setup_investment(country, countries[tag])
		state.countries[tag] = country
	_calibrate_currencies(state, settings)
	if not trade_definitions.is_empty():
		_setup_trade(state, countries, trade_definitions)
	state.energy_definitions = energy_definitions
	state.buildings.clear()
	state.projects.clear()
	state.next_project_id = 0
	if not energy_definitions.is_empty():
		for tag: String in tags:
			_setup_energy(state.countries[tag], countries[tag], state)
		_place_start_buildings(state)
	state.society_definitions = society_definitions
	if not society_definitions.is_empty():
		for tag: String in tags:
			_setup_society(state.countries[tag], countries[tag], state)
	_setup_diplomacy(state, countries, diplomacy_definitions)
	state.politics_definitions = politics_definitions
	if not politics_definitions.is_empty():
		for tag: String in tags:
			_setup_politics(state.countries[tag], countries[tag], state)
			_setup_laws(state.countries[tag], countries[tag], state)
			_setup_constitution(state.countries[tag], countries[tag])
			MediaSystem.refresh_media(state.countries[tag], (politics_definitions.get("settings", {}) as Dictionary).get(
				"media", {}))
			if not (politics_definitions.get("portfolios", {}) as Dictionary).is_empty():
				GovernmentSystem.form_cabinet(state.countries[tag], state)
				GovernmentSystem.set_start(state.countries[tag], state)
		var crisis_settings: Dictionary = (politics_definitions.get("settings", {}) as Dictionary).get("crises", {})
		var civil_war: Dictionary = (politics_definitions.get("crises", {}) as Dictionary).get(CrisisSystem.CIVIL_WAR, {})
		for tag: Variant in crisis_settings.get("start_civil_wars", []):
			if state.countries.has(tag) and not civil_war.is_empty():
				CrisisSystem.start_civil_war(state.countries[tag], state, civil_war, true)
				CrisisSystem.refresh_effects(state.countries[tag], state)
	state.military_settings = military_definitions.get("settings", {})
	state.map_size = military_definitions.get("map_size", state.map_size)
	state.war_goal_definitions = military_definitions.get("war_goals", {})
	state.terrain_definitions = military_definitions.get("terrains", {})
	NavalModel.setup_seas(state, military_definitions.get("sea_zones", {}), military_definitions.get("straits", {}))
	ControlSystem.setup_start(state)
	WarSystem.setup_start(state)
	if not state.military_settings.is_empty():
		for tag: String in tags:
			state.military.model.setup_country(state.countries[tag], countries[tag], state)
		WarSystem.setup_forces(state)
		MilitaryActions.setup_start(state)
		NuclearSystem.setup_start(state)
		state.military.model.setup_world(state, countries)
	state.technology_definitions = research_definitions.get("technologies", {})
	state.research_settings = research_definitions.get("settings", {})
	if not state.technology_definitions.is_empty():
		for tag: String in tags:
			ResearchSystem.setup_country(state, state.countries[tag], countries[tag])
		ResearchSystem.refresh_known_counts(state)
		AiRaceSystem.setup_start(state)


## Crée un seul pays en cours de partie (sécession), avec les mêmes étapes qu'au départ : économie, budget,
## ressources, investissement, énergie, société, politique, lois, constitution, médias, gouvernement, armée,
## recherche. Le commerce, les relations, le territoire et les groupes d'armées sont faits par CountryFactory.
static func create_country(state: SimState, tag: String, data: Dictionary) -> CountryState:
	var country := CountryState.new()
	country.tag = tag
	var settings := state.economy_settings
	_setup_economy(country, data, state, CreditRating.new(settings), settings)
	_setup_budget(country, data, state)
	_setup_resources(country, data, state)
	_setup_investment(country, data)
	state.countries[tag] = country
	var currency: CurrencyState = state.currencies.get(country.economy.currency)
	if currency != null and not currency.members.has(tag):
		currency.members.append(tag)
	if not state.energy_definitions.is_empty():
		_setup_energy(country, data, state)
	if not state.society_definitions.is_empty():
		_setup_society(country, data, state)
	if not state.politics_definitions.is_empty():
		_setup_politics(country, data, state)
		_setup_laws(country, data, state)
		_setup_constitution(country, data)
		MediaSystem.refresh_media(country, (state.politics_definitions.get("settings", {}) as Dictionary).get("media", {}))
		if not (state.politics_definitions.get("portfolios", {}) as Dictionary).is_empty():
			GovernmentSystem.form_cabinet(country, state)
			GovernmentSystem.set_start(country, state)
	if not state.military_settings.is_empty():
		state.military.model.setup_country(country, data, state)
	if not state.technology_definitions.is_empty():
		ResearchSystem.setup_country(state, country, data)
	return country


## Relations de départ (données « relations » de chaque pays, symétriques), traités de 2026, ambassades et
## reconnaissance des États contestés. definitions : {settings, treaties, start}.
static func _setup_diplomacy(state: SimState, countries: Dictionary, definitions: Dictionary) -> void:
	var diplomacy := DiplomacyState.new()
	var settings: Dictionary = definitions.get("settings", {})
	state.diplomacy = diplomacy
	state.diplomacy_settings = settings
	state.treaty_definitions = definitions.get("treaties", {})
	state.diplomacy_start = definitions.get("start", {})
	state.organization_rules = definitions.get("organization_rules", {})
	state.sanction_definitions = definitions.get("sanctions", {})
	state.aid_definitions = definitions.get("aid", {})
	diplomacy.trust_base = float(settings.get("trust_base", 50.0))
	diplomacy.trust_per_relation = float(settings.get("trust_per_relation", 0.0))
	diplomacy.opinion_noise = float(settings.get("opinion_noise", 0.0))
	for tag: String in countries.keys():
		var relations: Dictionary = (countries[tag] as Dictionary).get("relations", {})
		for other: Variant in relations.keys():
			if countries.has(other):
				diplomacy.start_relations[DiplomacyState.pair_key(tag, str(other))] = float(relations[other])
	DiplomacySystem.setup_start(state)
	OrganizationSystem.setup_start(state, definitions.get("organizations", {}), countries)
	if not state.sanction_definitions.is_empty():
		SanctionSystem.setup_start(state)
	if not state.aid_definitions.is_empty():
		AidSystem.setup_start(state)
	InfluenceSystem.setup_start(state)
	TensionSystem.setup_start(state)


## Lois de départ, selon les règles de chaque loi (pays cités, régime, démocratie, revenu).
static func _setup_laws(country: CountryState, data: Dictionary, state: SimState) -> void:
	var definitions: Dictionary = state.politics_definitions.get("laws", {})
	if definitions.is_empty():
		return
	var regime: Dictionary = (state.society_definitions.get("regimes", {}) as Dictionary).get(str(data.get("regime", "")), {})
	var context := {"tag": country.tag, "democratic": bool(regime.get("democratic", false)),
		"democracy": country.society.democracy_index,
		"gdp_per_capita": country.economy.gdp_per_capita_usd(state.get_currency(country.economy.currency))
			if state.get_currency(country.economy.currency) != null else 0.0}
	for law_id: String in definitions.keys():
		country.laws[law_id] = LawModel.start_option(definitions[law_id], context)
	country.start_laws = country.laws.duplicate()


static func _setup_constitution(country: CountryState, data: Dictionary) -> void:
	var constitution: Dictionary = data.get("constitution", {})
	country.constitution = ConstitutionModel.start_options(country.politics, str(constitution.get("term_limit", "none")))


## Chambre basse de départ ; les sondages de départ sont ramenés à 100 % avec les petits partis, puis
## l'attrait de chaque parti est calé sur eux.
static func _setup_politics(country: CountryState, data: Dictionary, state: SimState) -> void:
	var source: Dictionary = data.get("parliament", {})
	if source.is_empty():
		return
	var definitions := state.politics_definitions
	var party_data: Dictionary = definitions.get("parties", {})
	var ideologies: Dictionary = state.society_definitions.get("ideologies", {})
	var politics := country.politics
	politics.seats = int(source.get("seats", 0))
	politics.other_seats = int(source.get("other_seats", 0))
	politics.other_vote = float(source.get("other_vote", 0.0))
	politics.other_poll = float(source.get("other_poll", 0.0))
	var election: Dictionary = source.get("election", {})
	politics.election_year = int(election.get("year", 0))
	politics.election_month = int(election.get("month", 1))
	politics.term_years = int(source.get("term_years", 0))
	politics.dissolved = bool(source.get("dissolved", false))
	var regime: Dictionary = (state.society_definitions.get("regimes", {}) as Dictionary).get(str(data.get("regime", "")), {})
	politics.democratic = bool(regime.get("democratic", false))
	politics.regime = str(data.get("regime", ""))
	politics.culture = str(data.get("culture", ""))
	var constitution: Dictionary = data.get("constitution", {})
	politics.term_limit = int(ConstitutionModel.TERM_LIMITS.get(str(constitution.get("term_limit", "none")), 0))
	politics.terms_served = int(constitution.get("terms_served", 1))
	politics.polls_published = politics.democratic
	politics.executive = PoliticsState.EXECUTIVE_PRESIDENTIAL if str(data.get("regime", "")) == PRESIDENTIAL_REGIME \
		else PoliticsState.EXECUTIVE_PARLIAMENTARY
	politics.suspended = bool(source.get("suspended", false))
	politics.cordon = bool(source.get("cordon", false))
	var system: Dictionary = source.get("system", {})
	politics.system_type = str(system.get("type", PoliticsState.SYSTEM_PROPORTIONAL))
	politics.threshold = float(system.get("threshold", 0.0))
	politics.list_share = float(system.get("list_share", 0.0))
	var next: Dictionary = source.get("next_election", {})
	politics.next_election_year = int(next.get("year", politics.election_year + politics.term_years))
	politics.next_election_month = int(next.get("month", politics.election_month))
	var presidency: Dictionary = source.get("presidency", {})
	politics.has_presidency = not presidency.is_empty()
	if politics.has_presidency:
		politics.presidential_year = int((presidency["election"] as Dictionary)["year"])
		politics.presidential_month = int((presidency["election"] as Dictionary)["month"])
		politics.presidential_term = int(presidency.get("term_years", 0))
		politics.two_rounds = bool(presidency.get("two_rounds", false))
		politics.next_presidential_year = int((presidency["next_election"] as Dictionary)["year"])
		politics.next_presidential_month = int((presidency["next_election"] as Dictionary)["month"])
	politics.head_of_state = str(data.get("head_of_state", ""))
	politics.head_of_government = str(data.get("head_of_government", politics.head_of_state))
	politics.ideology = str(data.get("ideology", ""))
	for party_id: Variant in source.get("government", []):
		politics.government.append(str(party_id))
	var parties: Dictionary = source.get("parties", {})
	var poll_total := 0.0
	for party_id: Variant in parties.keys():
		var entry: Dictionary = parties[party_id]
		var party := PartyState.new()
		party.id = str(party_id)
		party.ideology = str((party_data.get(party_id, {}) as Dictionary).get("ideology", ""))
		party.party_group = str((ideologies.get(party.ideology, {}) as Dictionary).get("party_group", ""))
		party.seats = int(entry.get("seats", 0))
		party.vote = float(entry.get("vote", 0.0))
		party.start_poll = float(entry.get("poll", 0.0))
		poll_total += party.start_poll
		politics.parties[party.id] = party
	var available := PoliticsModel.PERCENT - politics.other_poll
	for party: PartyState in politics.parties.values():
		party.start_poll = party.start_poll / poll_total * available if poll_total > 0.0 else 0.0
		party.poll = party.start_poll
		party.previous_poll = party.poll
	if not country.society.group_shares.is_empty():
		PoliticsModel.calibrate(politics, country.society, state.society_definitions.get("groups", {}),
			definitions.get("settings", {}))


## Société de départ : satisfaction des groupes calée sur la popularité du gouvernement, influence selon
## le régime, stabilité et corruption réelles, légitimité selon le régime et l'indice de démocratie.
static func _setup_society(country: CountryState, data: Dictionary, state: SimState) -> void:
	var source: Dictionary = data.get("society", {})
	if source.is_empty():
		return
	var definitions := state.society_definitions
	var groups: Dictionary = definitions.get("groups", {})
	var settings: Dictionary = definitions.get("settings", {})
	var regime: Dictionary = (definitions.get("regimes", {}) as Dictionary).get(str(data.get("regime", "")), {})
	var ideology: Dictionary = (definitions.get("ideologies", {}) as Dictionary).get(str(data.get("ideology", "")), {})
	var society := country.society
	var shares: Dictionary = source.get("groups", {})
	var total := 0.0
	for group_id: Variant in groups.keys():
		total += float(shares.get(group_id, 0.0))
	for group_id: Variant in groups.keys():
		society.group_shares[group_id] = float(shares.get(group_id, 0.0)) / total if total > 0.0 else 0.0
	society.influence = SocietyModel.influence_weights(society.group_shares, groups, regime.get("group_influence", {}))
	society.start_satisfaction = SocietyModel.start_satisfaction(float(source.get("approval", 0.0)),
		society.group_shares, groups, str(ideology.get("party_group", "")),
		settings.get("start_satisfaction_bounds", [0.0, SocietyModel.PERCENT]))
	society.satisfaction = society.start_satisfaction.duplicate()
	society.support = SocietyModel.weighted(society.satisfaction, society.group_shares)
	society.start_support = society.support
	society.stability = float(source.get("stability", 0.0))
	society.start_stability = society.stability
	society.corruption = float(source.get("corruption", 0.0))
	society.start_corruption = society.corruption
	society.democracy_index = float(source.get("democracy", 0.0))
	var legitimacy_settings: Dictionary = settings.get("legitimacy", {})
	society.legitimacy = SocietyModel.start_legitimacy(bool(regime.get("democratic", false)), society.democracy_index,
		float(regime.get("legitimacy", legitimacy_settings.get("default_regime_legitimacy", 0.0))), legitimacy_settings)
	society.start_legitimacy = society.legitimacy
	society.start_unemployment = country.economy.unemployment
	society.start_inflation = country.economy.inflation
	society.start_growth = country.economy.growth


static func _setup_investment(country: CountryState, data: Dictionary) -> void:
	var source: Dictionary = data.get("investment", {})
	var economy := country.economy
	var investment := economy.investment
	investment.public_ownership = (source.get("public_ownership", {}) as Dictionary).duplicate()
	for sector_id: Variant in economy.sectors.keys():
		if not investment.public_ownership.has(sector_id):
			investment.public_ownership[sector_id] = 0.0
	investment.start_public_ownership = investment.public_ownership.duplicate()
	investment.fdi_inflow = float(source.get("fdi_inflow", 0.0))
	investment.start_fdi_inflow = investment.fdi_inflow
	investment.fdi_policy = str(source.get("fdi_policy", InvestmentState.OPEN))
	investment.start_fdi_policy = investment.fdi_policy
	investment.start_growth = economy.growth
	investment.start_rating = economy.rating
	investment.start_corporate_tax = float(economy.budget.tax_rates.get("corporate_tax", 0.0))


static func _create_market(resource_id: String, data: Dictionary) -> MarketState:
	var market := MarketState.new()
	market.resource_id = resource_id
	market.base_price = float(data.get("base_price", 1.0))
	market.price = market.base_price
	market.unit_value = float(data.get("unit_value", 0.0))
	market.demand_elasticity = float(data.get("demand_elasticity", 0.0))
	market.supply_elasticity = float(data.get("supply_elasticity", 0.0))
	market.income_elasticity = float(data.get("income_elasticity", 0.0))
	market.demand_trend = float(data.get("demand_trend", 0.0))
	market.supply_trend = float(data.get("supply_trend", 0.0))
	return market


static func _setup_resources(country: CountryState, data: Dictionary, state: SimState) -> void:
	var resources := country.resources
	var source: Dictionary = data.get("resources", {})
	for resource_id: Variant in source.keys():
		if not state.markets.has(resource_id):
			continue
		var entry: Dictionary = source[resource_id]
		resources.production_base[resource_id] = float(entry.get("production", 0.0))
		resources.consumption_base[resource_id] = float(entry.get("consumption", 0.0))
	resources.production = resources.production_base.duplicate()
	resources.consumption = resources.consumption_base.duplicate()
	resources.start_consumption = resources.consumption_base.duplicate()
	var water: Dictionary = data.get("water", {})
	resources.water_renewable = float(water.get("renewable", 0.0))
	resources.water_withdrawal_ratio = float(water.get("withdrawal_ratio", 0.0))


## Commerce de départ : accords, surtaxes et flux du modèle gravitaire (données « trade.partners »).
## trade_definitions : {agreements, settings}.
static func _setup_trade(state: SimState, countries: Dictionary, definitions: Dictionary) -> void:
	var trade := TradeState.new()
	state.trade = trade
	var settings: Dictionary = definitions.get("settings", {})
	state.trade_settings = settings
	for agreement_id: String in (definitions.get("agreements", {}) as Dictionary).keys():
		var agreement: Dictionary = definitions["agreements"][agreement_id]
		trade.agreements[agreement_id] = {"kind": str(agreement["kind"]), "members": (agreement["members"] as Array).duplicate()}
	trade.refresh_pair_kinds(TradeModel.KIND_ORDER)
	var tags: Array = countries.keys()
	tags.sort()
	for tag: String in tags:
		var data: Dictionary = (countries[tag] as Dictionary).get("trade", {})
		trade.start_gdp[tag] = maxf(TradeSystem.current_gdp(state, tag), 0.001)
		trade.surcharges[tag] = (data.get("surcharges", {}) as Dictionary).duplicate()
		var row: Dictionary = {}
		var partners: Dictionary = data.get("partners", {})
		for partner: Variant in partners.keys():
			if countries.has(partner):
				row[str(partner)] = float(partners[partner])
		trade.start_flows[tag] = row
	for exporter: String in tags:
		var tariffs: Dictionary = {}
		for importer: String in (trade.start_flows[exporter] as Dictionary).keys():
			tariffs[importer] = TradeModel.tariff(trade, exporter, importer, TradeSystem.base_tariff(state, importer),
				settings)
		trade.start_tariffs[exporter] = tariffs
	TradeSystem.refresh_tariff_changes(state)


## Électricité de départ : capacités déduites de la production réelle, demande = production, part des
## combustibles brûlée dans les centrales.
static func _setup_energy(country: CountryState, data: Dictionary, state: SimState) -> void:
	var sources: Dictionary = state.energy_definitions.get("sources", {})
	var hours := float((state.energy_definitions.get("settings", {}) as Dictionary).get("hours_per_year", 1.0))
	var energy := country.energy
	var generation: Dictionary = (data.get("energy", {}) as Dictionary).get("generation", {})
	for source_id: Variant in generation.keys():
		var source: Dictionary = sources.get(source_id, {})
		if source.is_empty():
			continue
		var amount := float(generation[source_id])
		energy.capacity[source_id] = EnergyModel.capacity_for(amount, float(source.get("capacity_factor", 1.0)), hours)
		energy.start_output[source_id] = amount
		energy.output[source_id] = amount
		energy.demand += amount
		var fuel: Dictionary = source.get("fuel", {})
		if not fuel.is_empty():
			var resource_id := str(fuel["resource"])
			var used := float(country.resources.consumption_base.get(resource_id, 0.0))
			if used > 0.0:
				# Part de la consommation du pays brûlée dans ses centrales, plafonnée à la part mondiale typique.
				var share := amount * float(fuel["per_twh"]) / used
				country.resources.power_share[resource_id] = minf(float(country.resources.power_share.get(resource_id, 0.0))
					+ share, float(fuel["power_share"]))
	var result := EnergyModel.dispatch(energy.capacity, energy.demand, sources, {}, hours)
	energy.max_supply = float(result["max_supply"])


## Parc de départ dans les provinces (pour l'affichage et les limites de construction) : centrales réparties
## selon le relief et la population, mines sur les ressources riches, un port dans la grande ville côtière.
static func _place_start_buildings(state: SimState) -> void:
	var definitions := state.energy_definitions
	var provinces: Dictionary = definitions.get("provinces", {})
	var buildings: Dictionary = definitions.get("buildings", {})
	var sources: Dictionary = definitions.get("sources", {})
	var settings: Dictionary = definitions.get("settings", {})
	var outputs: Dictionary = definitions.get("mine_outputs", {})
	var richness := int(settings.get("start_mine_richness", 1))
	var ports := int(settings.get("start_port_count", 0))
	# Provinces de chaque pays, de la plus peuplée à la moins peuplée : [[population, id], …].
	var owned: Dictionary = {}
	for province_id: String in provinces.keys():
		var province: Dictionary = provinces[province_id]
		var owner := str(province.get("owner", ""))
		if owner.is_empty():
			continue
		if not owned.has(owner):
			owned[owner] = []
		(owned[owner] as Array).append([int(province.get("population", 0)), province_id])
	for tag: String in owned.keys():
		var country := state.get_country(tag)
		if country == null:
			continue
		var ranked: Array = owned[tag]
		ranked.sort_custom(func(a: Array, b: Array) -> bool:
			return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
		for source_id: Variant in country.energy.capacity.keys():
			var building_id := str((sources.get(source_id, {}) as Dictionary).get("building", ""))
			var definition: Dictionary = buildings.get(building_id, {})
			var unit := float(definition.get("capacity_gw", 0.0))
			if unit > 0.0:
				var count := maxi(roundi(float(country.energy.capacity[source_id]) / unit), 1)
				_spread_buildings(state, ranked, provinces, building_id, definition.get("terrains", []), count)
		var placed_ports := 0
		for entry: Array in ranked:
			var province_id: String = entry[1]
			var province: Dictionary = provinces[province_id]
			var resources: Dictionary = province.get("resources", {})
			for resource_id: Variant in resources.keys():
				if outputs.has(resource_id) and int(resources[resource_id]) >= richness:
					EnergySystem.add_building(state, province_id, "mine", 1)
					break
			if placed_ports < ports and bool(province.get("coastal", false)):
				EnergySystem.add_building(state, province_id, "port", 1)
				placed_ports += 1


## Répartit des bâtiments entre les provinces qui les acceptent (les plus peuplées d'abord), au prorata
## de leur population. ranked : [[population, id], …] triées.
static func _spread_buildings(state: SimState, ranked: Array, provinces: Dictionary, building_id: String,
		terrains: Array, count: int) -> void:
	var candidates: Array = []
	for entry: Array in ranked:
		if terrains.is_empty() or terrains.has(str((provinces[entry[1]] as Dictionary).get("terrain", ""))):
			candidates.append(entry)
			if candidates.size() >= count:
				break
	if candidates.is_empty():
		candidates = ranked.slice(0, maxi(mini(count, ranked.size()), 1))
	var total := 0.0
	for entry: Array in candidates:
		total += maxf(float(entry[0]), 1.0)
	var placed := 0
	for index: int in candidates.size():
		var share := maxf(float(candidates[index][0]), 1.0) / total
		var amount := count - placed if index == candidates.size() - 1 else roundi(count * share)
		if amount > 0:
			EnergySystem.add_building(state, str(candidates[index][1]), building_id, amount)
			placed += amount


static func _create_currency(currency_id: String, data: Dictionary) -> CurrencyState:
	var currency := CurrencyState.new()
	currency.id = currency_id
	currency.code = str(data.get("code", currency_id.to_upper()))
	currency.usd_rate = float(data.get("usd_rate", 1.0))
	currency.start_usd_rate = currency.usd_rate
	currency.policy_rate = float(data.get("policy_rate", 0.0))
	currency.inflation_target = float(data.get("inflation_target", 2.0))
	currency.independent = bool(data.get("independent", true))
	currency.peg = str(data.get("peg", ""))
	return currency


static func _setup_economy(country: CountryState, data: Dictionary, state: SimState, ratings: CreditRating,
		settings: Dictionary) -> void:
	var source: Dictionary = data.get("economy", {})
	var economy := country.economy
	var currency: CurrencyState = state.currencies.get(str(data.get("currency", "")))
	economy.currency = currency.id if currency != null else ""
	economy.population = int(data.get("population", 0))
	# Fonds souverain chargé avant le calage de la note, qui tient compte de la dette nette.
	economy.investment.sovereign_fund = float((data.get("investment", {}) as Dictionary).get("sovereign_fund", 0.0))
	economy.fund_rating_weight = float(state.investment_settings.get("fund_rating_weight", 0.0))
	economy.real_gdp = float(source.get("gdp_billion_usd", 0.0))
	economy.sectors = (source.get("sectors", {}) as Dictionary).duplicate()
	var growth_bounds: Array = settings["growth_bounds"]
	economy.growth = clampf(float(source.get("growth", 0.0)), float(growth_bounds[0]), float(growth_bounds[1]))
	economy.potential_growth = economy.growth
	economy.inflation = float(source.get("inflation", 0.0))
	economy.unemployment = float(source.get("unemployment", 0.0))
	economy.natural_unemployment = economy.unemployment
	if currency == null:
		return
	economy.neutral_real_rate = clamp_neutral(currency.policy_rate - economy.inflation, settings)

	# Dette : part en devises (sauf pour les pays qui utilisent la monnaie de référence).
	var debt := float(source.get("debt_to_gdp", 0.0)) * economy.nominal_gdp()
	var foreign_share := 0.0 if currency.id == str(settings["reference_currency"]) \
		else float(source.get("foreign_debt_share", 0.0))
	economy.local_debt = debt * (1.0 - foreign_share)
	economy.foreign_debt = debt * foreign_share

	# Note : celle des agences si elle existe, sinon estimée par le modèle.
	var reference: CurrencyState = state.currencies.get(str(settings["reference_currency"]))
	var gdp_per_capita := economy.gdp_per_capita_usd(currency)
	var rating_id := str(source.get("rating", ""))
	var known := ratings.index_of(rating_id)
	economy.rating = known if known != CreditRating.UNKNOWN else 0
	_set_debt_rates(economy, currency, reference, ratings)
	var score := EconomyModel.rating_score(gdp_per_capita, economy.rating_debt_ratio(currency), economy.inflation,
		currency.inflation_target, economy.growth, economy.real_interest_burden(currency), false, settings)
	if known == CreditRating.UNKNOWN:
		economy.rating = maxi(ratings.clamp_index(score), ratings.index_of(str(settings["min_estimated_rating"])))
		economy.rating_estimated = true
		_set_debt_rates(economy, currency, reference, ratings)
		score = EconomyModel.rating_score(gdp_per_capita, economy.rating_debt_ratio(currency), economy.inflation,
			currency.inflation_target, economy.growth, economy.real_interest_burden(currency), false, settings)
	var anchor := economy.rating
	# Pays déjà en défaut : la dette a été restructurée, la note remonte vers celle de sortie de crise.
	if ratings.is_default(economy.rating):
		anchor = ratings.index_of(str((settings["crisis"] as Dictionary)["recovery_rating"]))
	var max_offset := float(settings["max_rating_offset"])
	economy.rating_offset = clampf(anchor - score, -max_offset, max_offset)
	economy.review_phase = absi(hash(country.tag)) % int(settings["rating_review_months"])

	# Les taux effectifs de départ sont réduits si la charge d'intérêts dépasse le plafond : une grande partie
	# de la dette des pays à taux élevés a été émise plus tôt, à de meilleures conditions ou en devises.
	var burden := economy.interest_burden(currency)
	var max_burden := float(settings["max_start_interest_burden"])
	if burden > max_burden:
		economy.debt_rate_factor = max_burden / burden
		economy.local_debt_rate *= economy.debt_rate_factor
		economy.foreign_debt_rate *= economy.debt_rate_factor
	# Solde primaire : le solde réel de 2025 auquel on rajoute les intérêts calculés.
	economy.primary_balance = float(source.get("budget_balance", 0.0)) + economy.interest_burden(currency)
	economy.start_primary_balance = economy.primary_balance
	economy.start_debt_ratio = economy.debt_ratio(currency)


## Budget de départ : taux réels, recettes par point de taux, et dépenses ajustées dans la même proportion
## pour retrouver exactement le solde primaire de départ.
static func _setup_budget(country: CountryState, data: Dictionary, state: SimState) -> void:
	if state.budget_definitions.is_empty():
		return
	var budget := country.economy.budget
	var source: Dictionary = data.get("budget", {})
	var taxes: Dictionary = state.budget_definitions.get("taxes", {})
	var weights: Array = (state.budget_definitions.get("settings", {}) as Dictionary).get("income_bracket_weights", [])
	var tax_data: Dictionary = source.get("taxes", {})
	for tax_id: Variant in taxes.keys():
		var entry: Dictionary = tax_data.get(tax_id, {})
		var revenue := float(entry.get("revenue", 0.0))
		var rate := 0.0
		if str(tax_id) == BudgetModel.INCOME_TAX:
			for value: Variant in entry.get("brackets", []):
				budget.income_brackets.append(float(value))
			while budget.income_brackets.size() < weights.size():
				budget.income_brackets.append(0.0)
			budget.start_income_brackets = budget.income_brackets.duplicate()
			rate = BudgetModel.average_income_rate(budget.income_brackets, weights)
		else:
			rate = float(entry.get("rate", 0.0))
			budget.tax_rates[tax_id] = rate
			budget.start_tax_rates[tax_id] = rate
		budget.revenue_per_point[tax_id] = revenue / rate if rate > 0.0 \
			else float((taxes[tax_id] as Dictionary).get("default_revenue_per_point", 0.0))
	for line_id: Variant in (state.budget_definitions.get("spending", {}) as Dictionary).keys():
		budget.spending[line_id] = float((source.get("spending", {}) as Dictionary).get(line_id, 0.0))
	budget.revenues = BudgetModel.revenues(budget, taxes, weights)
	var total := budget.total_spending()
	var target := budget.total_revenue() - country.economy.primary_balance
	if total > 0.0 and target > 0.0:
		for line_id: Variant in budget.spending.keys():
			budget.spending[line_id] = float(budget.spending[line_id]) * target / total
	budget.start_spending = budget.spending.duplicate()


static func clamp_neutral(value: float, settings: Dictionary) -> float:
	var bounds: Array = settings["neutral_real_rate_bounds"]
	return clampf(value, float(bounds[0]), float(bounds[1]))


## Taux effectifs de départ = taux auxquels le pays emprunte aujourd'hui.
static func _set_debt_rates(economy: EconomyState, currency: CurrencyState, reference: CurrencyState,
		ratings: CreditRating) -> void:
	var spread := ratings.spread(economy.rating)
	economy.local_debt_rate = currency.policy_rate + spread
	economy.foreign_debt_rate = (reference.policy_rate if reference != null else currency.policy_rate) + spread


## Taux neutres et écarts de départ des monnaies, pour que la règle de Taylor et le change partent stables.
static func _calibrate_currencies(state: SimState, settings: Dictionary) -> void:
	for currency: CurrencyState in state.currencies.values():
		EconomySystem.update_currency_aggregates(currency, state)
	var reference: CurrencyState = state.currencies.get(str(settings["reference_currency"]))
	for currency: CurrencyState in state.currencies.values():
		var taylor_without_neutral := EconomyModel.taylor_rate(currency.inflation, 0.0, currency.inflation_target,
			0.0, currency.independent, settings)
		currency.neutral_real_rate = clamp_neutral(currency.policy_rate - taylor_without_neutral, settings)
		if currency.is_pegged():
			var anchor: CurrencyState = state.currencies.get(currency.peg)
			currency.peg_spread = currency.policy_rate - anchor.policy_rate if anchor != null else 0.0
		if reference != null:
			currency.start_real_rate_gap = (currency.policy_rate - currency.inflation) \
				- (reference.policy_rate - reference.inflation)

class_name GovernmentSystem
extends SimSystem
## Gouvernement, une fois par mois, avant la société : scandales des ministres corrompus et démissions des
## ministres peu loyaux ; le remplaçant est nommé aussitôt. Les effets du cabinet sont recalculés à chaque
## changement de ministre.

const PRIORITY := 5
const EVENT_SCANDAL := &"minister_scandal"
const EVENT_RESIGNATION := &"minister_resigned"
const CHARACTER_PREFIX := "sim_"


func get_id() -> StringName:
	return &"government"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.politics_definitions.is_empty():
		return
	var settings := GovernmentModel.settings_of(state)
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		var portfolios: Array = country.cabinet.keys()
		portfolios.sort()
		for portfolio_id: String in portfolios:
			var minister := character(state, str(country.cabinet[portfolio_id]))
			var scandal := float(settings.get("scandal_chance", 0.0)) * float(minister.get("corruption", 0.0)) / 50.0 \
				* country.politics.media_factor
			if state.rng.randf() < scandal:
				_scandal(country, state, portfolio_id, minister, settings)
				continue
			var threshold := float(settings.get("resignation_loyalty", 0.0))
			var loyalty := float(minister.get("loyalty", 100.0))
			if loyalty < threshold and state.rng.randf() < float(settings.get("resignation_chance", 0.0)) \
					* (threshold - loyalty) / threshold:
				state.add_event(EVENT_RESIGNATION, tag, {"portfolio": portfolio_id})
				replace(country, state, portfolio_id)


static func _scandal(country: CountryState, state: SimState, portfolio_id: String, minister: Dictionary,
		settings: Dictionary) -> void:
	var society := country.society
	society.stability = maxf(society.stability - float(settings.get("scandal_stability", 0.0)), 0.0)
	society.start_stability -= float(settings.get("scandal_start_stability", 0.0))
	var ruling: PartyState = country.politics.parties.get(country.politics.ruling_party())
	if ruling != null:
		ruling.drift -= float(settings.get("scandal_poll", 0.0))
	state.add_event(EVENT_SCANDAL, country.tag, {"portfolio": portfolio_id,
		"party": str(minister.get("party", ""))})
	replace(country, state, portfolio_id)


## Remplace un ministre par le premier candidat proposé.
static func replace(country: CountryState, state: SimState, portfolio_id: String) -> void:
	var proposed := candidates(country, state, portfolio_id)
	if not proposed.is_empty():
		appoint(country, state, portfolio_id, proposed[0])


## Personnage du jeu (créé pendant la partie) ou des données.
static func character(state: SimState, character_id: String) -> Dictionary:
	if state.characters.has(character_id):
		return state.characters[character_id]
	return (state.politics_definitions.get("characters", {}) as Dictionary).get(character_id, {})


## Candidats proposés pour un portefeuille, issus des partis du gouvernement (les mêmes tant que personne
## n'est nommé). Renvoie [] si les données de noms manquent.
static func candidates(country: CountryState, state: SimState, portfolio_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var government := country.politics.government
	var count := int(GovernmentModel.settings_of(state).get("candidates", 1))
	for index: int in count:
		var party := government[index % government.size()] if not government.is_empty() else ""
		var key := "%s|%s|%d|%d" % [country.tag, portfolio_id, country.cabinet_generation, index]
		var candidate := GovernmentModel.make_character(state, country, party, key, index % maxi(government.size(), 1) > 0,
			cabinet_last_names(country, state, portfolio_id))
		if not candidate.is_empty():
			result.append(candidate)
	return result


## Nomme un ministre et recalcule les effets du cabinet.
static func appoint(country: CountryState, state: SimState, portfolio_id: String, minister: Dictionary) -> void:
	if minister.is_empty():
		return
	var character_id := "%s%d" % [CHARACTER_PREFIX, state.next_character_id]
	state.next_character_id += 1
	state.characters[character_id] = minister
	country.cabinet[portfolio_id] = character_id
	country.cabinet_generation += 1
	refresh_effects(country, state)


## Noms de famille des autres ministres (pour éviter les homonymes dans un même gouvernement).
static func cabinet_last_names(country: CountryState, state: SimState, except_portfolio: String = "") -> Array:
	var result: Array = []
	for portfolio_id: Variant in country.cabinet.keys():
		if str(portfolio_id) != except_portfolio:
			result.append(character(state, str(country.cabinet[portfolio_id])).get("last_name", ""))
	return result


## Nouveau cabinet complet (début de partie ou alternance) : portefeuilles répartis entre les partis du
## gouvernement selon leurs sièges, le parti qui dirige d'abord.
static func form_cabinet(country: CountryState, state: SimState) -> void:
	var portfolios: Array = (state.politics_definitions.get("portfolios", {}) as Dictionary).keys()
	var parties := _portfolio_parties(country, portfolios.size())
	country.cabinet.clear()
	for index: int in portfolios.size():
		var party: String = parties[index]
		var key := "%s|%s|cabinet|%d" % [country.tag, portfolios[index], country.cabinet_generation]
		var minister := GovernmentModel.make_character(state, country, party, key,
			not party.is_empty() and party != country.politics.ruling_party(), cabinet_last_names(country, state))
		if minister.is_empty():
			continue
		var character_id := "%s%d" % [CHARACTER_PREFIX, state.next_character_id]
		state.next_character_id += 1
		state.characters[character_id] = minister
		country.cabinet[portfolios[index]] = character_id
	country.cabinet_generation += 1
	refresh_effects(country, state)


## Parti de chaque portefeuille, dans l'ordre : au prorata des sièges des partis du gouvernement.
static func _portfolio_parties(country: CountryState, count: int) -> Array[String]:
	var politics := country.politics
	var result: Array[String] = []
	if politics.government.is_empty():
		for _index: int in count:
			result.append("")
		return result
	var weights: Dictionary = {}
	for party_id: String in politics.government:
		var party: PartyState = politics.parties.get(party_id)
		weights[party_id] = maxf(float(party.seats) if party != null else 0.0, 1.0)
	var shares := ElectionModel.largest_remainder(weights, count)
	for party_id: String in politics.government:
		for _index: int in int(shares.get(party_id, 0)):
			result.append(party_id)
	while result.size() < count:
		result.append(politics.government[0])
	return result


## Fixe le cabinet de départ comme référence : ses effets sont nuls.
static func set_start(country: CountryState, state: SimState) -> void:
	var portfolios: Dictionary = state.politics_definitions.get("portfolios", {})
	var settings := GovernmentModel.settings_of(state)
	var corruption := 0.0
	for portfolio_id: Variant in country.cabinet.keys():
		var minister := character(state, str(country.cabinet[portfolio_id]))
		country.start_competence[portfolio_id] = GovernmentModel.competence(minister, portfolios.get(portfolio_id, {}),
			settings)
		corruption += float(minister.get("corruption", 0.0))
	country.start_minister_corruption = corruption / country.cabinet.size() if not country.cabinet.is_empty() else 0.0
	refresh_effects(country, state)


static func refresh_effects(country: CountryState, state: SimState) -> void:
	var ministers: Dictionary = {}
	for portfolio_id: Variant in country.cabinet.keys():
		ministers[portfolio_id] = character(state, str(country.cabinet[portfolio_id]))
	country.cabinet_effects = GovernmentModel.effects(ministers, state.politics_definitions.get("portfolios", {}),
		country.start_competence, country.start_minister_corruption, GovernmentModel.settings_of(state))
	country.economy.cabinet_growth = float(country.cabinet_effects.get("growth", 0.0))
	LawSystem.refresh_corruption(country)

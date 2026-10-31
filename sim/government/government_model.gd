class_name GovernmentModel
extends RefCounted
## Formules du gouvernement, sans état : création des ministres, compétence et effets du cabinet.
##
## Compétence d'un ministre (0 à 10) = son talent utile au portefeuille + bonus de son parcours. Chaque
## point de compétence de plus qu'au départ apporte les effets du portefeuille ; la corruption moyenne des
## ministres, comparée à celle du cabinet de départ, déplace la corruption du pays.

const GROUPS := "groups"
const SCALAR_EFFECTS := ["growth", "stability", "legitimacy", "corruption"]
const PERCENT := 100.0
const MAX_NAME_ATTEMPTS := 20


## Générateur de noms reproductible pour une clé donnée (pays, portefeuille, tirage…).
static func generator(state: SimState, key: String) -> NameGenerator:
	var names: Dictionary = state.politics_definitions.get("names", {})
	if names.is_empty():
		return null
	return NameGenerator.new(names.get("cultures", {}), names.get("party_styles", {}), names.get("ideologies", {}),
		names.get("traits", {}), names.get("settings", {}), ("%d|%s" % [state.game_seed, key]).hash())


## Nouveau personnage politique : nom de la culture du pays, idéologie de son parti, loyauté et corruption.
## Renvoie {} si les données de noms manquent.
## taken_last_names : noms de famille à éviter (autres membres du gouvernement).
static func make_character(state: SimState, country: CountryState, party_id: String, key: String,
		junior_partner: bool = false, taken_last_names: Array = []) -> Dictionary:
	var names := generator(state, key)
	if names == null:
		return {}
	var settings := settings_of(state)
	var party: PartyState = country.politics.parties.get(party_id)
	var ideology := party.ideology if party != null else country.politics.ideology
	var culture := country.politics.culture
	var character := names.generate_character(country.tag, culture, names.pick_gender(culture), 0, ideology)
	for _attempt: int in MAX_NAME_ATTEMPTS:
		if not taken_last_names.has(character.get("last_name", "")):
			break
		character.merge(names.generate_name(culture, str(character["gender"])), true)
	if not party_id.is_empty():
		character["party"] = party_id
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d|%s|traits" % [state.game_seed, key]).hash()
	var loyalty := float(settings.get("loyalty_base", 50.0)) + rng.randf_range(-1.0, 1.0) \
		* float(settings.get("loyalty_spread", 0.0))
	var corruption := country.society.start_corruption * float(settings.get("corruption_share", 1.0)) \
		+ rng.randf_range(-1.0, 1.0) * float(settings.get("corruption_spread", 0.0))
	for trait_id: Variant in character.get("traits", []):
		loyalty += float((settings.get("trait_loyalty", {}) as Dictionary).get(trait_id, 0.0))
		corruption += float((settings.get("trait_corruption", {}) as Dictionary).get(trait_id, 0.0))
	if junior_partner:
		loyalty += float(settings.get("junior_partner_loyalty", 0.0))
	character["loyalty"] = roundi(clampf(loyalty, 0.0, PERCENT))
	character["corruption"] = roundi(clampf(corruption, 0.0, PERCENT))
	return character


## Compétence d'un personnage pour un portefeuille (0 à 10).
static func competence(character: Dictionary, portfolio: Dictionary, settings: Dictionary) -> float:
	var value := float((character.get("skills", {}) as Dictionary).get(str(portfolio.get("skill", "")), 0.0))
	for trait_id: Variant in character.get("traits", []):
		value += float((portfolio.get("trait_bonus", {}) as Dictionary).get(trait_id, 0.0))
	return clampf(value, 0.0, float(settings.get("max_competence", 10.0)))


## Effets du cabinet par rapport au cabinet de départ.
## ministers : {portefeuille: personnage}, start_competence : {portefeuille: compétence de départ}.
static func effects(ministers: Dictionary, portfolios: Dictionary, start_competence: Dictionary,
		start_corruption: float, settings: Dictionary) -> Dictionary:
	var result: Dictionary = {GROUPS: {}}
	var corruption_total := 0.0
	for portfolio_id: Variant in ministers.keys():
		var portfolio: Dictionary = portfolios.get(portfolio_id, {})
		var character: Dictionary = ministers[portfolio_id]
		var change := competence(character, portfolio, settings) - float(start_competence.get(portfolio_id, 0.0))
		var portfolio_effects: Dictionary = portfolio.get("effects", {})
		for key: String in SCALAR_EFFECTS:
			if portfolio_effects.has(key):
				result[key] = float(result.get(key, 0.0)) + float(portfolio_effects[key]) * change
		var groups: Dictionary = result[GROUPS]
		for group_id: Variant in (portfolio_effects.get(GROUPS, {}) as Dictionary).keys():
			groups[group_id] = float(groups.get(group_id, 0.0)) + float(portfolio_effects[GROUPS][group_id]) * change
		corruption_total += float(character.get("corruption", 0.0))
	if not ministers.is_empty():
		result["corruption"] = float(result.get("corruption", 0.0)) \
			+ float(settings.get("corruption_effect", 0.0)) * (corruption_total / ministers.size() - start_corruption)
	return result


static func settings_of(state: SimState) -> Dictionary:
	return (state.politics_definitions.get("settings", {}) as Dictionary).get("government", {})

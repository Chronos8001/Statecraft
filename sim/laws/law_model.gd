class_name LawModel
extends RefCounted
## Formules des lois, sans état.
##
## Chaque option d'une loi déclare ses effets (groupes sociaux, stabilité, croissance, légitimité, corruption,
## coût budgétaire en % du PIB) et la position de chaque famille politique (-2 à +2). Les effets se mesurent
## par rapport à l'option de départ du pays : la situation de 2026 est neutre.

const GROUPS := "groups"
const SCALAR_EFFECTS := ["stability", "growth", "legitimacy", "corruption", "budget"]


## Option de départ : la règle par défaut, puis chaque règle qui correspond (la dernière l'emporte).
## context : {tag, democratic, religious_share, gdp_per_capita, democracy}.
static func start_option(definition: Dictionary, context: Dictionary) -> String:
	var start: Dictionary = definition.get("start", {})
	var result := str(start.get("default", ""))
	for rule: Dictionary in start.get("rules", []):
		if _matches(rule, context):
			result = str(rule["option"])
	return result


static func _matches(rule: Dictionary, context: Dictionary) -> bool:
	if rule.has("countries") and not (rule["countries"] as Array).has(context.get("tag", "")):
		return false
	if rule.has("democratic") and bool(rule["democratic"]) != bool(context.get("democratic", true)):
		return false
	if rule.has("democracy_max") and float(context.get("democracy", 10.0)) > float(rule["democracy_max"]):
		return false
	if rule.has("gdp_pc_max") and float(context.get("gdp_per_capita", 0.0)) > float(rule["gdp_pc_max"]):
		return false
	return true


static func option_of(definition: Dictionary, option_id: String) -> Dictionary:
	for option: Dictionary in definition.get("options", []):
		if str(option["id"]) == option_id:
			return option
	return {}


## Somme des effets des lois en vigueur moins ceux des lois de départ.
static func aggregate(definitions: Dictionary, current: Dictionary, start: Dictionary) -> Dictionary:
	var result: Dictionary = {GROUPS: {}}
	for law_id: Variant in current.keys():
		if current[law_id] == start.get(law_id):
			continue
		var definition: Dictionary = definitions.get(law_id, {})
		_add(result, (option_of(definition, str(current[law_id])).get("effects", {}) as Dictionary), 1.0)
		_add(result, (option_of(definition, str(start.get(law_id, ""))).get("effects", {}) as Dictionary), -1.0)
	return result


static func _add(result: Dictionary, effects: Dictionary, sign: float) -> void:
	for key: String in SCALAR_EFFECTS:
		if effects.has(key):
			result[key] = float(result.get(key, 0.0)) + sign * float(effects[key])
	var groups: Dictionary = result[GROUPS]
	for group_id: Variant in (effects.get(GROUPS, {}) as Dictionary).keys():
		groups[group_id] = float(groups.get(group_id, 0.0)) + sign * float(effects[GROUPS][group_id])


## Différence de position d'une famille politique entre deux options (positive : elle préfère la nouvelle).
static func preference(definition: Dictionary, from_option: String, to_option: String, party_group: String) -> float:
	var to_positions: Dictionary = option_of(definition, to_option).get("positions", {})
	var from_positions: Dictionary = option_of(definition, from_option).get("positions", {})
	return float(to_positions.get(party_group, 0.0)) - float(from_positions.get(party_group, 0.0))


## Vote de la chambre basse : un parti vote pour s'il préfère la nouvelle option ; les partis du gouvernement
## suivent la consigne tant que le texte ne les heurte pas trop. Petits partis et indépendants : abstention.
## Renvoie {yes, no, required, passed, votes: {parti: true/false}}.
static func vote(politics: PoliticsState, definition: Dictionary, from_option: String, to_option: String,
		settings: Dictionary, required_share: float = 0.5) -> Dictionary:
	var discipline := float(settings.get("government_discipline", 0.0))
	var yes := 0
	var no := 0
	var votes: Dictionary = {}
	for party: PartyState in politics.parties.values():
		var difference := preference(definition, from_option, to_option, party.party_group)
		var in_favour := difference > 0.0 or (politics.is_in_government(party.id) and difference >= -discipline)
		votes[party.id] = in_favour
		if in_favour:
			yes += party.seats
		else:
			no += party.seats
	var required := floori(politics.seats * required_share) + 1
	return {"yes": yes, "no": no, "required": required, "passed": yes >= required, "votes": votes}

class_name ScriptConditions
extends RefCounted
## Langage de conditions des événements (et plus tard des décisions), en JSON lisible :
##   {"stability": "<30", "democratic": true}           toutes les clés doivent être vraies
##   {"any": [{"at_war": true}, {"growth": "<-2"}]}     au moins une
##   {"not": {"regime": "absolute_monarchy"}}
##   {"relation": {"with": "USA", "value": "<-20"}}       "with" peut valoir "from" (pays à l'origine)
##   {"action": {"government_changed": true}}             détails de l'action qui a déclenché l'événement
##   {"from": {"gdp_rank": "<=15"}}                        condition sur le pays d'origine
##   {"any_neighbor": {"at_war": true}}                    au moins un voisin terrestre
## Valeurs numériques : nombre (égalité) ou texte « <, <=, >, >=, =, != » suivi d'un nombre.
## La portée (scope) est {"country": tag ou "" pour le monde, "from": tag à l'origine d'une chaîne}.

const NUMBERS := ["stability", "legitimacy", "growth", "unemployment", "inflation", "debt", "gdp", "year", "month",
	"world_tension", "ai_level", "corruption", "population", "gdp_rank", "leader_age"]
const COMBINATORS := ["all", "any", "not", "from", "any_neighbor"]
const OTHERS := ["tag", "regime", "democratic", "at_war", "has_tech", "has_flag", "has_world_flag", "relation",
	"law", "random", "is_player", "exists", "borders_player", "is_player_or_neighbor", "has_resource",
	"strait_closed", "action", "has_focus", "has_decision", "country_exists", "is_dissolved", "owns_province",
	"can_release", "member_of", "player_is"]
const OPERATORS := ["<=", ">=", "!=", "<", ">", "="]
const PERCENT := 100.0
const MILLION := 1.0e6


static func evaluate(state: SimState, scope: Dictionary, condition: Variant) -> bool:
	if condition == null:
		return true
	if condition is Array:
		for item: Variant in condition:
			if not evaluate(state, scope, item):
				return false
		return true
	if not condition is Dictionary:
		return false
	for key: Variant in (condition as Dictionary).keys():
		if not _check(state, scope, str(key), condition[key]):
			return false
	return true


static func _check(state: SimState, scope: Dictionary, key: String, value: Variant) -> bool:
	match key:
		"all":
			return evaluate(state, scope, value)
		"any":
			var items: Array = value if value is Array else _split(value)
			for item: Variant in items:
				if evaluate(state, scope, item):
					return true
			return false
		"not":
			return not evaluate(state, scope, value)
		"from":
			var origin := str(scope.get("from", ""))
			return not origin.is_empty() and evaluate(state, {"country": origin, "from": str(scope.get("country", ""))},
				value)
		"any_neighbor":
			var own := str(scope.get("country", ""))
			var neighbors: Array = (state.land_neighbors.get(own, {}) as Dictionary).keys()
			neighbors.sort()
			for neighbor: Variant in neighbors:
				if state.get_country(str(neighbor)) != null \
						and evaluate(state, {"country": str(neighbor), "from": own}, value):
					return true
			return false
		"random":
			return state.rng.randf() < float(value)
		"has_world_flag":
			return state.world_flags.has(str(value))
		"strait_closed":
			return state.closed_straits.has(str(value))
		"player_is":
			return str(state.player_tag) == str(value)
		"can_release":
			return CountryFactory.release_refusal(state, str(value)).is_empty()
		"country_exists":
			return state.get_country(target_tag(scope, str(value))) != null
		"is_dissolved":
			return state.dissolved.has(target_tag(scope, str(value)))
		"action":
			var details: Dictionary = scope.get("action", {})
			for detail: Variant in (value as Dictionary).keys():
				if str(details.get(detail, "")) != str(value[detail]):
					return false
			return true
	if NUMBERS.has(key):
		var number: Variant = number_of(state, scope, key)
		return number != null and compare(float(number), value)
	var country := state.get_country(str(scope.get("country", "")))
	if country == null:
		return key == "exists" and not bool(value)
	match key:
		"exists":
			return bool(value)
		"tag":
			return country.tag == str(value) if not value is Array else (value as Array).has(country.tag)
		"regime":
			return country.politics.regime == str(value) if not value is Array else (value as Array).has(country.politics.regime)
		"democratic":
			return country.politics.democratic == bool(value)
		"is_player":
			return (StringName(country.tag) == state.player_tag) == bool(value)
		"at_war":
			return (not WarSystem.wars_of(state, country.tag).is_empty()) == bool(value)
		"borders_player":
			return (state.land_neighbors.get(country.tag, {}) as Dictionary).has(str(state.player_tag)) == bool(value)
		"is_player_or_neighbor":
			var player := str(state.player_tag)
			var close := country.tag == player or (state.land_neighbors.get(country.tag, {}) as Dictionary).has(player)
			return close == bool(value)
		"has_resource":
			return float(country.resources.production_base.get(str(value), 0.0)) > 0.0
		"has_tech":
			return country.research != null and country.research.is_known(str(value))
		"has_flag":
			return (state.event_flags.get(country.tag, {}) as Dictionary).has(str(value))
		"has_focus":
			return country.focus_done.has(str(value))
		"member_of":
			return OrganizationSystem.is_member(state, str(value), country.tag)
		"owns_province":
			return ControlSystem.owner(state, str(value)) == country.tag
		"has_decision":
			return country.decisions_active.has(str(value))
		"law":
			for law_id: Variant in (value as Dictionary).keys():
				if str(country.laws.get(str(law_id), "")) != str(value[law_id]):
					return false
			return true
		"relation":
			var other := target_tag(scope, str((value as Dictionary).get("with", "")))
			return compare(state.diplomacy.relation(country.tag, other), (value as Dictionary).get("value", 0))
	return false


static func _split(value: Variant) -> Array:
	var result: Array = []
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			result.append({key: value[key]})
	return result


## Pays désigné dans un effet ou une condition : "from" (origine de la chaîne), "self", ou un code pays.
static func target_tag(scope: Dictionary, name: String) -> String:
	match name:
		"from":
			return str(scope.get("from", ""))
		"self", "":
			return str(scope.get("country", ""))
	return name


## Valeur numérique d'une clé ; null si elle n'a pas de sens dans cette portée.
static func number_of(state: SimState, scope: Dictionary, key: String) -> Variant:
	match key:
		"year":
			return float(state.date.year)
		"month":
			return float(state.date.month)
		"world_tension":
			return state.diplomacy.world_tension
	var country := state.get_country(str(scope.get("country", "")))
	if country == null:
		return null
	match key:
		"stability":
			return country.society.stability
		"legitimacy":
			return country.society.legitimacy
		"corruption":
			return country.society.corruption
		"growth":
			return country.economy.growth
		"unemployment":
			return country.economy.unemployment
		"inflation":
			return country.economy.inflation
		"debt":
			var currency := state.get_currency(country.economy.currency)
			return country.economy.debt_ratio(currency) * PERCENT if currency != null else 0.0
		"gdp":
			return TradeSystem.current_gdp(state, country.tag)
		"ai_level":
			return country.research.ai_level if country.research != null else 0.0
		"population":
			return float(country.economy.population) / MILLION
		"gdp_rank":
			return float(gdp_rank(state, country.tag))
		"leader_age":
			var leader := GovernmentSystem.character(state, country.politics.head_of_state)
			return float(state.date.year - int(leader["birth_year"])) if leader.has("birth_year") else null
	return null


## Rang du pays par PIB (1 = le plus riche), recalculé une fois par jour.
static func gdp_rank(state: SimState, tag: String) -> int:
	var today := state.date.to_day_number()
	if int(state.gdp_ranks.get("day", -1)) != today:
		var tags: Array = state.countries.keys()
		var gdps: Dictionary = {}
		for other: String in tags:
			gdps[other] = TradeSystem.current_gdp(state, other)
		tags.sort_custom(func(a: String, b: String) -> bool:
			return float(gdps[a]) > float(gdps[b]) or (is_equal_approx(float(gdps[a]), float(gdps[b])) and a < b))
		var ranks: Dictionary = {}
		for index: int in tags.size():
			ranks[tags[index]] = index + 1
		state.gdp_ranks = {"day": today, "ranks": ranks}
	return int((state.gdp_ranks["ranks"] as Dictionary).get(tag, state.countries.size()))


## Comparaison : nombre (égalité) ou « <30 », « >=2.5 », « !=0 »…
static func compare(actual: float, spec: Variant) -> bool:
	if spec is float or spec is int:
		return is_equal_approx(actual, float(spec))
	var text := str(spec).strip_edges()
	for operator: String in OPERATORS:
		if text.begins_with(operator):
			var target := float(text.substr(operator.length()).strip_edges())
			match operator:
				"<=":
					return actual <= target
				">=":
					return actual >= target
				"!=":
					return not is_equal_approx(actual, target)
				"<":
					return actual < target
				">":
					return actual > target
				"=":
					return is_equal_approx(actual, target)
	return false


static func _valid_comparison(spec: Variant) -> bool:
	if spec is float or spec is int:
		return true
	var text := str(spec).strip_edges()
	for operator: String in OPERATORS:
		if text.begins_with(operator):
			return text.substr(operator.length()).strip_edges().is_valid_float()
	return false


## Erreurs d'une condition (clés inconnues, comparaisons mal écrites), préfixées par where.
static func validate(condition: Variant, where: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if condition == null:
		return errors
	if condition is Array:
		for item: Variant in condition:
			errors.append_array(validate(item, where))
		return errors
	if not condition is Dictionary:
		errors.append("%s : condition invalide (%s)" % [where, str(condition)])
		return errors
	for key: Variant in (condition as Dictionary).keys():
		var name := str(key)
		var value: Variant = condition[key]
		if COMBINATORS.has(name):
			errors.append_array(validate(value if name != "any" or value is Array else _split(value), where))
		elif NUMBERS.has(name):
			if not _valid_comparison(value):
				errors.append("%s : comparaison invalide pour « %s » (%s)" % [where, name, str(value)])
		elif name == "relation":
			if not value is Dictionary or not (value as Dictionary).has("with") \
					or not _valid_comparison((value as Dictionary).get("value", null)):
				errors.append("%s : « relation » attend {with, value}" % where)
		elif name == "law" or name == "action":
			if not value is Dictionary:
				errors.append("%s : « %s » attend un objet" % [where, name])
		elif not OTHERS.has(name):
			errors.append("%s : condition inconnue « %s »" % [where, name])
	return errors

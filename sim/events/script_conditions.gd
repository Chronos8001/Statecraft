class_name ScriptConditions
extends RefCounted
## Langage de conditions des événements (et plus tard des décisions), en JSON lisible :
##   {"stability": "<30", "democratic": true}           toutes les clés doivent être vraies
##   {"any": [{"at_war": true}, {"growth": "<-2"}]}     au moins une
##   {"not": {"regime": "absolute_monarchy"}}
##   {"relation": {"with": "USA", "value": "<-20"}}       "with" peut valoir "from" (pays à l'origine)
## Valeurs numériques : nombre (égalité) ou texte « <, <=, >, >=, =, != » suivi d'un nombre.
## La portée (scope) est {"country": tag ou "" pour le monde, "from": tag à l'origine d'une chaîne}.

const NUMBERS := ["stability", "legitimacy", "growth", "unemployment", "inflation", "debt", "gdp", "year", "month",
	"world_tension", "ai_level", "corruption"]
const COMBINATORS := ["all", "any", "not"]
const OTHERS := ["tag", "regime", "democratic", "at_war", "has_tech", "has_flag", "has_world_flag", "relation",
	"law", "random", "is_player", "exists"]
const OPERATORS := ["<=", ">=", "!=", "<", ">", "="]
const PERCENT := 100.0


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
		"random":
			return state.rng.randf() < float(value)
		"has_world_flag":
			return state.world_flags.has(str(value))
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
		"has_tech":
			return country.research != null and country.research.is_known(str(value))
		"has_flag":
			return (state.event_flags.get(country.tag, {}) as Dictionary).has(str(value))
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
	return null


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
		elif name == "law":
			if not value is Dictionary:
				errors.append("%s : « law » attend {loi: option}" % where)
		elif not OTHERS.has(name):
			errors.append("%s : condition inconnue « %s »" % [where, name])
	return errors

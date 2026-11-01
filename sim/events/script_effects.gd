class_name ScriptEffects
extends RefCounted
## Langage d'effets des événements (et plus tard des décisions), en JSON lisible :
##   {"add_stability": -5, "add_modifier": {"growth": -0.5, "months": 12}}
##   {"if": {"democratic": true}, "then": {"add_legitimacy": 3}, "else": {"add_stability": -3}}
##   {"every_country": {"limit": {"at_war": true}, "effects": {"add_stability": -2}}}
##   {"trigger_event": {"id": "suite", "days": 30, "target": "from"}}
## Les chocs (stabilité, légitimité) touchent la valeur du moment, qui revient ensuite vers sa cible ; les
## modificateurs (croissance, chômage, stabilité visée) durent quelques mois.

const KEYS := ["add_stability", "add_legitimacy", "add_modifier", "add_debt", "add_relation", "add_tension",
	"add_group_satisfaction", "set_law", "add_research", "trigger_event", "set_flag", "clear_flag",
	"set_world_flag", "clear_world_flag", "every_country", "if", "then", "else"]
const MODIFIER_KEYS := ["growth", "unemployment", "stability", "months"]
const LIMIT := 100.0


static func apply(state: SimState, scope: Dictionary, effects: Variant) -> void:
	if not effects is Dictionary:
		return
	var data: Dictionary = effects
	if data.has("if"):
		var branch: Variant = data.get("then", {}) if ScriptConditions.evaluate(state, scope, data["if"]) \
			else data.get("else", {})
		apply(state, scope, branch)
	var country := state.get_country(str(scope.get("country", "")))
	for key: Variant in data.keys():
		var name := str(key)
		var value: Variant = data[key]
		match name:
			"add_tension":
				TensionSystem.add(state, float(value))
			"set_world_flag":
				state.world_flags[str(value)] = true
			"clear_world_flag":
				state.world_flags.erase(str(value))
			"trigger_event":
				_trigger(state, scope, value)
			"every_country":
				var limit: Variant = (value as Dictionary).get("limit", null)
				var tags: Array = state.countries.keys()
				tags.sort()
				for tag: String in tags:
					var inner := {"country": tag, "from": str(scope.get("country", ""))}
					if ScriptConditions.evaluate(state, inner, limit):
						apply(state, inner, (value as Dictionary).get("effects", {}))
		if country == null:
			continue
		match name:
			"add_stability":
				country.society.stability = clampf(country.society.stability + float(value), 0.0, LIMIT)
			"add_legitimacy":
				country.society.legitimacy = clampf(country.society.legitimacy + float(value), 0.0, LIMIT)
			"add_modifier":
				add_modifier(state, country, value)
			"add_debt":
				InvestmentSystem.add_debt_usd(country, state, float(value))
			"add_relation":
				var other := ScriptConditions.target_tag(scope, str((value as Dictionary).get("with", "")))
				state.diplomacy.change_relation(country.tag, other, float((value as Dictionary).get("value", 0.0)))
			"add_group_satisfaction":
				for group_id: Variant in (value as Dictionary).keys():
					country.society.bonuses[group_id] = float(country.society.bonuses.get(group_id, 0.0)) \
						+ float(value[group_id])
			"set_law":
				for law_id: Variant in (value as Dictionary).keys():
					country.laws[str(law_id)] = str(value[law_id])
				LawSystem.apply_effects(country, state)
			"add_research":
				_add_research(country, float(value))
			"set_flag":
				if not state.event_flags.has(country.tag):
					state.event_flags[country.tag] = {}
				(state.event_flags[country.tag] as Dictionary)[str(value)] = true
			"clear_flag":
				(state.event_flags.get(country.tag, {}) as Dictionary).erase(str(value))


## Modificateur temporaire : {growth, unemployment, stability, months} (durée par défaut dans les réglages).
static func add_modifier(state: SimState, country: CountryState, value: Variant) -> void:
	var modifier: Dictionary = (value as Dictionary).duplicate()
	modifier["months"] = int(modifier.get("months", int(state.event_settings.get("modifier_months", 12))))
	country.event_modifiers.append(modifier)
	EventSystem.refresh_modifiers(country)


## Points de recherche répartis entre les recherches en cours.
static func _add_research(country: CountryState, points: float) -> void:
	if country.research == null:
		return
	var busy: Array[String] = []
	for tech_id: String in country.research.slots:
		if not tech_id.is_empty():
			busy.append(tech_id)
	for tech_id: String in busy:
		country.research.progress[tech_id] = float(country.research.progress.get(tech_id, 0.0)) + points / busy.size()


static func _trigger(state: SimState, scope: Dictionary, value: Variant) -> void:
	var spec: Dictionary = value if value is Dictionary else {"id": str(value)}
	var target := ScriptConditions.target_tag(scope, str(spec.get("target", "self")))
	EventSystem.schedule(state, str(spec.get("id", "")), target, str(scope.get("country", "")),
		int(spec.get("days", 0)))


# --- Validation et description ----------------------------------------------------------------------------------

## Erreurs d'un bloc d'effets : clés inconnues, événements enchaînés inexistants, conditions des « if ».
static func validate(effects: Variant, where: String, event_ids: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if effects == null:
		return errors
	if not effects is Dictionary:
		errors.append("%s : effets invalides (%s)" % [where, str(effects)])
		return errors
	var data: Dictionary = effects
	for key: Variant in data.keys():
		var name := str(key)
		var value: Variant = data[key]
		if not KEYS.has(name):
			errors.append("%s : effet inconnu « %s »" % [where, name])
		elif (name == "then" or name == "else") and not data.has("if"):
			errors.append("%s : « %s » sans « if »" % [where, name])
		match name:
			"if":
				errors.append_array(ScriptConditions.validate(value, where))
			"then", "else":
				errors.append_array(validate(value, where, event_ids))
			"every_country":
				if not value is Dictionary:
					errors.append("%s : « every_country » attend {limit, effects}" % where)
				else:
					errors.append_array(ScriptConditions.validate((value as Dictionary).get("limit", null), where))
					errors.append_array(validate((value as Dictionary).get("effects", {}), where, event_ids))
			"trigger_event":
				var id := str((value as Dictionary).get("id", "")) if value is Dictionary else str(value)
				if not event_ids.has(id):
					errors.append("%s : événement enchaîné inconnu « %s »" % [where, id])
			"add_modifier":
				if not value is Dictionary:
					errors.append("%s : « add_modifier » attend un objet" % where)
				else:
					for part: Variant in (value as Dictionary).keys():
						if not MODIFIER_KEYS.has(str(part)):
							errors.append("%s : modificateur inconnu « %s »" % [where, str(part)])
			"add_relation":
				if not value is Dictionary or not (value as Dictionary).has("with"):
					errors.append("%s : « add_relation » attend {with, value}" % where)
	return errors


## Lignes lisibles des effets (infobulles des choix), avec les clés de localisation EFFECT_*.
static func describe(effects: Variant, locale: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if not effects is Dictionary:
		return lines
	var data: Dictionary = effects
	for key: Variant in data.keys():
		var name := str(key)
		var value: Variant = data[key]
		match name:
			"add_stability", "add_legitimacy", "add_tension", "add_debt", "add_research":
				lines.append(TranslationServer.translate("EFFECT_%s" % name.to_upper()) % _signed(float(value), locale))
			"add_modifier":
				var months := int((value as Dictionary).get("months", 12))
				for part: String in ["growth", "unemployment", "stability"]:
					if (value as Dictionary).has(part):
						lines.append(TranslationServer.translate("EFFECT_MODIFIER_%s" % part.to_upper()) % [
							_signed(float(value[part]), locale), months])
			"add_relation":
				lines.append(TranslationServer.translate("EFFECT_ADD_RELATION") % [
					_signed(float((value as Dictionary).get("value", 0.0)), locale), str(value.get("with", ""))])
			"add_group_satisfaction":
				for group_id: Variant in (value as Dictionary).keys():
					lines.append(TranslationServer.translate("EFFECT_ADD_GROUP") % [
						TranslationServer.translate("GROUP_%s" % str(group_id).to_upper()), _signed(float(value[group_id]), locale)])
			"set_law":
				lines.append(TranslationServer.translate("EFFECT_SET_LAW"))
			"trigger_event":
				lines.append(TranslationServer.translate("EFFECT_TRIGGER_EVENT"))
			"if", "every_country":
				lines.append(TranslationServer.translate("EFFECT_CONDITIONAL"))
	return lines


static func _signed(value: float, locale: String) -> String:
	return ("+" if value > 0.0 else "") + NumberFormat.decimal(value, 0 if is_equal_approx(value, roundf(value)) else 1, locale)

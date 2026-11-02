class_name ScriptEffects
extends RefCounted
## Langage d'effets des événements (et plus tard des décisions), en JSON lisible :
##   {"add_stability": -5, "add_modifier": {"growth": -0.5, "months": 12}}
##   {"if": {"democratic": true}, "then": {"add_legitimacy": 3}, "else": {"add_stability": -3}}
##   {"every_country": {"limit": {"at_war": true}, "effects": {"add_stability": -2}}}
##   {"trigger_event": {"id": "suite", "days": 30, "target": "from"}}
##   {"random_country": {"limit": {"gdp_rank": "<=20"}, "effects": {...}}}   un pays tiré au sort (« from » = portée)
##   {"random_province": {"limit": {"coastal": true}, "effects": {"damage_infrastructure": 3}}}
##   {"add_supply_shock": {"resource": "oil", "share": 0.1, "months": 6}, "close_strait": "hormuz"}
##   {"kill_leader": "head_of_state"}
## Les chocs (stabilité, légitimité) touchent la valeur du moment, qui revient ensuite vers sa cible ; les
## modificateurs (croissance, chômage, stabilité visée) durent quelques mois.

const KEYS := ["add_stability", "add_legitimacy", "add_modifier", "add_debt", "add_relation", "add_tension",
	"add_group_satisfaction", "set_law", "add_research", "trigger_event", "set_flag", "clear_flag",
	"set_world_flag", "clear_world_flag", "every_country", "random_country", "random_province", "if", "then", "else",
	"damage_infrastructure", "add_resource_capacity", "add_supply_shock", "close_strait", "open_strait", "kill_leader",
	"add_debt_gdp", "add_influence", "add_corruption", "add_tech", "every_neighbor",
	"annex_country", "join_country", "rename_country", "release_country"]
const MODIFIER_KEYS := ["growth", "unemployment", "inflation", "stability", "months"]
## Conditions propres aux provinces (filtre « limit » de random_province).
const PROVINCE_KEYS := ["coastal", "terrain", "population"]
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
			"release_country":
				CountryFactory.release(state, str(value))
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
			"random_country":
				_random_country(state, scope, value)
			"every_neighbor":
				var own := str(scope.get("country", ""))
				var neighbors: Array = (state.land_neighbors.get(own, {}) as Dictionary).keys()
				neighbors.sort()
				for neighbor: Variant in neighbors:
					if state.get_country(str(neighbor)) != null:
						apply(state, {"country": str(neighbor), "from": own}, value)
			"add_supply_shock":
				ResourceSystem.add_supply_shock(state, str((value as Dictionary).get("resource", "")),
					float((value as Dictionary).get("share", 0.0)), int((value as Dictionary).get("months", 0)))
			"close_strait":
				ResourceSystem.set_strait_closed(state, str(value), true)
			"open_strait":
				ResourceSystem.set_strait_closed(state, str(value), false)
			"damage_infrastructure":
				var province := str(scope.get("province", ""))
				if not province.is_empty():
					state.infrastructure_damage[province] = float(state.infrastructure_damage.get(province, 0.0)) \
						+ float(value)
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
			"add_influence":
				state.diplomacy.influence_points[country.tag] = maxf(float(state.diplomacy.influence_points.get(
					country.tag, 0.0)) + float(value), 0.0)
			"add_corruption":
				country.society.start_corruption = clampf(country.society.start_corruption + float(value), 0.0, LIMIT)
				country.society.corruption = clampf(country.society.corruption + float(value), 0.0, LIMIT)
			"add_tech":
				if country.research != null and state.technology_definitions.has(str(value)) \
						and not country.research.is_known(str(value)):
					ResearchSystem.complete(state, country, str(value))
			"annex_country":
				CountryLifecycle.annex(state, country.tag, ScriptConditions.target_tag(scope, str(value)))
			"join_country":
				CountryLifecycle.annex(state, ScriptConditions.target_tag(scope, str(value)), country.tag)
			"rename_country":
				CountryLifecycle.rename(state, country.tag, str((value as Dictionary).get("name_key", "")),
					str((value as Dictionary).get("color", "")), str((value as Dictionary).get("flag", "")))
			"add_debt_gdp":
				InvestmentSystem.add_debt_usd(country, state, TradeSystem.current_gdp(state, country.tag) * float(value)
					/ LIMIT)
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
			"random_province":
				_random_province(state, scope, country, value)
			"add_resource_capacity":
				var market: MarketState = state.markets.get(str((value as Dictionary).get("resource", "")))
				if market != null:
					# Un nouveau producteur n'a pas encore de consommation de base pour cette ressource.
					if not country.resources.consumption_base.has(market.resource_id):
						country.resources.consumption_base[market.resource_id] = 0.0
					country.resources.production_base[market.resource_id] = float(
						country.resources.production_base.get(market.resource_id, 0.0)) \
						+ market.supply * float((value as Dictionary).get("world_share", 0.0))
			"kill_leader":
				var spec: Dictionary = value if value is Dictionary else {"role": str(value)}
				LeaderSystem.kill(state, country, str(spec.get("role", "")), str(spec.get("cause", "event")))


## Modificateur temporaire : {growth, unemployment, inflation, stability, months} (durée par défaut dans les
## réglages ; « months » négatif : permanent).
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


## Un pays tiré au sort parmi ceux qui remplissent « limit » ; « from » désigne la portée d'origine.
static func _random_country(state: SimState, scope: Dictionary, value: Variant) -> void:
	var limit: Variant = (value as Dictionary).get("limit", null)
	var tags: Array = state.countries.keys()
	tags.sort()
	var chosen: Array[String] = []
	for tag: String in tags:
		if ScriptConditions.evaluate(state, {"country": tag, "from": str(scope.get("country", ""))}, limit):
			chosen.append(tag)
	if chosen.is_empty():
		return
	var tag := chosen[state.rng.randi_range(0, chosen.size() - 1)]
	apply(state, {"country": tag, "from": str(scope.get("country", ""))}, (value as Dictionary).get("effects", {}))


## Une province du pays tirée au sort (pondérée par la population) parmi celles qui remplissent « limit » ;
## elle devient la province de la portée (texte de l'événement, effets de province).
static func _random_province(state: SimState, scope: Dictionary, country: CountryState, value: Variant) -> void:
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var limit: Dictionary = (value as Dictionary).get("limit", {})
	var candidates: Array[String] = []
	var weights: Array[float] = []
	var total := 0.0
	for province_id: Variant in state.provinces_by_owner.get(country.tag, []):
		var province: Dictionary = provinces.get(str(province_id), {})
		if province.is_empty() or not province_matches(province, limit):
			continue
		var weight := maxf(float(province.get("population", 0.0)), 1.0)
		candidates.append(str(province_id))
		weights.append(weight)
		total += weight
	if candidates.is_empty():
		return
	var roll := state.rng.randf() * total
	var picked := candidates[candidates.size() - 1]
	for index: int in candidates.size():
		roll -= weights[index]
		if roll < 0.0:
			picked = candidates[index]
			break
	scope["province"] = picked
	apply(state, scope, (value as Dictionary).get("effects", {}))


static func province_matches(province: Dictionary, limit: Dictionary) -> bool:
	for key: Variant in limit.keys():
		var value: Variant = limit[key]
		match str(key):
			"coastal":
				if bool(province.get("coastal", false)) != bool(value):
					return false
			"terrain":
				var terrains: Array = value if value is Array else [value]
				if not terrains.has(str(province.get("terrain", ""))):
					return false
			"population":
				if not ScriptConditions.compare(float(province.get("population", 0.0)), value):
					return false
	return true


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
			"every_country", "random_country":
				if not value is Dictionary:
					errors.append("%s : « %s » attend {limit, effects}" % [where, name])
				else:
					errors.append_array(ScriptConditions.validate((value as Dictionary).get("limit", null), where))
					errors.append_array(validate((value as Dictionary).get("effects", {}), where, event_ids))
			"every_neighbor":
				errors.append_array(validate(value, where, event_ids))
			"rename_country":
				if not value is Dictionary:
					errors.append("%s : « rename_country » attend {name_key, color, flag}" % where)
			"random_province":
				if not value is Dictionary:
					errors.append("%s : « random_province » attend {limit, effects}" % where)
				else:
					for part: Variant in ((value as Dictionary).get("limit", {}) as Dictionary).keys():
						if not PROVINCE_KEYS.has(str(part)):
							errors.append("%s : condition de province inconnue « %s »" % [where, str(part)])
					errors.append_array(validate((value as Dictionary).get("effects", {}), where, event_ids))
			"add_supply_shock", "add_resource_capacity":
				if not value is Dictionary or not (value as Dictionary).has("resource"):
					errors.append("%s : « %s » attend {resource, …}" % [where, name])
			"kill_leader":
				var role := str((value as Dictionary).get("role", "")) if value is Dictionary else str(value)
				if not LeaderSystem.ROLES.has(role):
					errors.append("%s : « kill_leader » vaut head_of_state ou head_of_government" % where)
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
			"add_stability", "add_legitimacy", "add_tension", "add_debt", "add_research", "add_debt_gdp", "add_influence", "add_corruption":
				lines.append(TranslationServer.translate("EFFECT_%s" % name.to_upper()) % _signed(float(value), locale))
			"add_modifier":
				var months := int((value as Dictionary).get("months", 12))
				for part: String in ["growth", "unemployment", "inflation", "stability"]:
					if (value as Dictionary).has(part) and months < 0:
						lines.append(TranslationServer.translate("EFFECT_PERMANENT_%s" % part.to_upper()) %
							_signed(float(value[part]), locale))
					elif (value as Dictionary).has(part):
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
			"if", "every_country", "random_country", "random_province", "every_neighbor":
				lines.append(TranslationServer.translate("EFFECT_CONDITIONAL"))
			"damage_infrastructure":
				lines.append(TranslationServer.translate("EFFECT_DAMAGE_INFRASTRUCTURE") % _signed(-float(value), locale))
			"add_supply_shock":
				lines.append(TranslationServer.translate("EFFECT_SUPPLY_SHOCK") % [
					TranslationServer.translate("RESOURCE_%s" % str(value.get("resource", "")).to_upper()),
					_signed(-float(value.get("share", 0.0)) * LIMIT, locale), int(value.get("months", 0))])
			"add_resource_capacity":
				lines.append(TranslationServer.translate("EFFECT_RESOURCE_CAPACITY") %
					TranslationServer.translate("RESOURCE_%s" % str(value.get("resource", "")).to_upper()))
			"close_strait", "open_strait":
				lines.append(TranslationServer.translate("EFFECT_%s" % name.to_upper()) %
					TranslationServer.translate("STRAIT_%s" % str(value).to_upper()))
			"kill_leader":
				lines.append(TranslationServer.translate("EFFECT_KILL_LEADER"))
			"release_country":
				lines.append(TranslationServer.translate("EFFECT_RELEASE_COUNTRY") % str(value))
			"annex_country", "join_country":
				lines.append(TranslationServer.translate("EFFECT_%s" % name.to_upper()) %
					TranslationServer.translate("COUNTRY_%s" % str(value)))
			"rename_country":
				lines.append(TranslationServer.translate("EFFECT_RENAME_COUNTRY") %
					TranslationServer.translate(str((value as Dictionary).get("name_key", ""))))
			"add_tech":
				lines.append(TranslationServer.translate("EFFECT_ADD_TECH") %
					TranslationServer.translate("TECH_%s" % str(value).to_upper()))
			"set_flag", "set_world_flag", "clear_flag", "clear_world_flag":
				pass
	return lines


static func _signed(value: float, locale: String) -> String:
	return ("+" if value > 0.0 else "") + NumberFormat.decimal(value, 0 if is_equal_approx(value, roundf(value)) else 1, locale)

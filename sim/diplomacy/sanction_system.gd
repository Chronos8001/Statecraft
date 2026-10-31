class_name SanctionSystem
extends RefCounted
## Sanctions économiques : mesures ciblées, sectorielles, embargo total, gel d'avoirs, exclusion des systèmes
## de paiement. Chaque mesure pèse sur la cible à proportion de son exposition au pays qui sanctionne (part
## de son commerce avec lui et poids financier de sa monnaie) ; le pays qui sanctionne paie un coût lié à
## son propre commerce avec la cible. Les effets se mesurent par rapport aux sanctions de 2026, déjà comprises
## dans la situation de départ.

const EU_GROUP := "@eu"
const EU := "eu"
const PERCENT := 100.0
const EVENT_SANCTION := &"sanction_changed"


static func settings_of(state: SimState) -> Dictionary:
	return state.diplomacy_settings.get("sanctions", {})


static func key(sanctioner: String, target: String) -> String:
	return DiplomacyState.opinion_key(sanctioner, target)


static func measures(state: SimState, sanctioner: String, target: String) -> Array:
	return (state.diplomacy.sanctions.get(key(sanctioner, target), {}) as Dictionary).get("measures", [])


static func has_measure(state: SimState, sanctioner: String, target: String, measure: String) -> bool:
	return measures(state, sanctioner, target).has(measure)


## Pays qui sanctionnent une cible.
static func sanctioners_of(state: SimState, target: String) -> Array[String]:
	var result: Array[String] = []
	for entry: String in state.diplomacy.sanctions.keys():
		var parts := entry.split(">")
		if parts[1] == target and not measures(state, parts[0], target).is_empty():
			result.append(parts[0])
	return result


## Développe « @eu » en membres de l'Union européenne.
static func expand(state: SimState, tags: Array) -> Array[String]:
	var result: Array[String] = []
	for tag: Variant in tags:
		if str(tag) == EU_GROUP:
			for member: Variant in OrganizationSystem.members(state, EU):
				result.append(str(member))
		elif state.countries.has(tag):
			result.append(str(tag))
	return result


## Exposition de la cible au pays qui sanctionne (0 à 1) : commerce + poids financier.
## cache : parts de commerce déjà calculées (tag → {partenaire: part}), partagé entre appels.
static func exposure(state: SimState, sanctioner: String, target: String, cache: Dictionary = {}) -> float:
	var reach: Dictionary = settings_of(state).get("finance_reach", {})
	var finance := float(reach.get(sanctioner, 0.0))
	if finance <= 0.0 and OrganizationSystem.is_member(state, EU, sanctioner):
		finance = float(reach.get(EU_GROUP, 0.0))
	return clampf(share(state, target, sanctioner, cache) + finance, 0.0, 1.0)


## Part du commerce de tag réalisée avec partner, d'après les échanges de 2026 (calculées en une passe pour
## tous les pays et gardées dans cache).
static func share(state: SimState, tag: String, partner: String, cache: Dictionary) -> float:
	if cache.is_empty():
		var totals: Dictionary = {}
		var flows := state.trade.start_flows
		for exporter: String in flows.keys():
			var row: Dictionary = flows[exporter]
			for importer: Variant in row.keys():
				for pair: Array in [[exporter, str(importer)], [str(importer), exporter]]:
					if not totals.has(pair[0]):
						totals[pair[0]] = {}
					var partners: Dictionary = totals[pair[0]]
					partners[pair[1]] = float(partners.get(pair[1], 0.0)) + float(row[importer])
		for country: Variant in totals.keys():
			var partners: Dictionary = totals[country]
			var total := 0.0
			for value: Variant in partners.values():
				total += float(value)
			for key_partner: Variant in partners.keys():
				partners[key_partner] = float(partners[key_partner]) / total if total > 0.0 else 0.0
			cache[country] = partners
		cache[""] = {}
	return float((cache.get(tag, {}) as Dictionary).get(partner, 0.0))


## Saturation douce : proche de value tant qu'il est petit devant limit, sans jamais dépasser limit.
static func saturate(value: float, limit: float) -> float:
	if limit <= 0.0 or is_inf(limit):
		return value
	return signf(value) * limit * (1.0 - exp(-absf(value) / limit))


## Effets des sanctions sur un pays : {growth, inflation} (subies et coûts de celles qu'il impose).
static func penalties(state: SimState, tag: String, cache: Dictionary = {}) -> Dictionary:
	var definitions := state.sanction_definitions
	var settings := settings_of(state)
	var growth := 0.0
	var inflation := 0.0
	for entry: String in state.diplomacy.sanctions.keys():
		var parts := entry.split(">")
		var active: Array = measures(state, parts[0], parts[1])
		if parts[1] == tag:
			var weight := exposure(state, parts[0], tag, cache)
			for measure: Variant in active:
				var definition: Dictionary = definitions.get(measure, {})
				growth += float(definition.get("growth", 0.0)) * weight
				inflation += float(definition.get("inflation", 0.0)) * weight
		elif parts[0] == tag:
			var own_share := share(state, tag, parts[1], cache)
			for measure: Variant in active:
				growth -= float((definitions.get(measure, {}) as Dictionary).get("cost", 0.0)) * own_share
	return {"growth": saturate(growth, float(settings.get("max_growth_penalty", INF))),
		"inflation": saturate(inflation, float(settings.get("max_inflation", INF)))}


## Sanctions de 2026 et effets de référence de chaque pays.
static func setup_start(state: SimState) -> void:
	for entry: Variant in (state.diplomacy_start.get("sanctions", {}) as Dictionary).get("list", []):
		var values: Array = entry
		for sanctioner: String in expand(state, values[0] as Array):
			for target: String in expand(state, [values[1]]):
				if sanctioner != target:
					for measure: Variant in values[2]:
						_add(state, sanctioner, target, str(measure))
	state.diplomacy.start_sanction_effects = all_penalties(state, {})
	for country: CountryState in state.countries.values():
		country.economy.sanction_growth = 0.0
		country.economy.sanction_inflation = 0.0


## Effets des sanctions pour tous les pays en une seule passe : tag → {growth, inflation}.
static func all_penalties(state: SimState, cache: Dictionary) -> Dictionary:
	var definitions := state.sanction_definitions
	var settings := settings_of(state)
	var raw: Dictionary = {}
	for tag: String in state.countries.keys():
		raw[tag] = [0.0, 0.0]
	for entry: String in state.diplomacy.sanctions.keys():
		var parts := entry.split(">")
		if not raw.has(parts[0]) or not raw.has(parts[1]):
			continue
		var active: Array = measures(state, parts[0], parts[1])
		var weight := exposure(state, parts[0], parts[1], cache)
		var own_share := share(state, parts[0], parts[1], cache)
		for measure: Variant in active:
			var definition: Dictionary = definitions.get(measure, {})
			raw[parts[1]][0] += float(definition.get("growth", 0.0)) * weight
			raw[parts[1]][1] += float(definition.get("inflation", 0.0)) * weight
			raw[parts[0]][0] -= float(definition.get("cost", 0.0)) * own_share
	var result: Dictionary = {}
	for tag: String in raw.keys():
		result[tag] = {"growth": saturate(float(raw[tag][0]), float(settings.get("max_growth_penalty", INF))),
			"inflation": saturate(float(raw[tag][1]), float(settings.get("max_inflation", INF)))}
	return result


static func _add(state: SimState, sanctioner: String, target: String, measure: String) -> void:
	var entry_key := key(sanctioner, target)
	if not state.diplomacy.sanctions.has(entry_key):
		state.diplomacy.sanctions[entry_key] = {"measures": []}
	var active: Array = state.diplomacy.sanctions[entry_key]["measures"]
	if not active.has(measure):
		active.append(measure)


## Effets du moment par rapport à 2026, recopiés dans l'économie.
static func refresh(state: SimState, tag: String, cache: Dictionary = {}) -> void:
	var country := state.get_country(tag)
	if country == null:
		return
	var now := penalties(state, tag, cache)
	var start: Dictionary = state.diplomacy.start_sanction_effects.get(tag, {"growth": 0.0, "inflation": 0.0})
	country.economy.sanction_growth = float(now["growth"]) - float(start["growth"])
	country.economy.sanction_inflation = float(now["inflation"]) - float(start["inflation"])


## Imposer ou lever une mesure ; relations et confiance réagissent.
static func set_measure(state: SimState, sanctioner: String, target: String, measure: String, active: bool) -> void:
	var definition: Dictionary = state.sanction_definitions.get(measure, {})
	var settings := settings_of(state)
	var diplomacy := state.diplomacy
	if active:
		_add(state, sanctioner, target, measure)
		if TensionSystem.threshold(state, measure) > 0.0:
			TensionSystem.add_event(state, "heavy_sanction")
		diplomacy.change_relation(sanctioner, target, float(definition.get("relation", 0.0)))
		diplomacy.change_trust(sanctioner, target, float(settings.get("trust", 0.0)))
	else:
		(diplomacy.sanctions.get(key(sanctioner, target), {}).get("measures", []) as Array).erase(measure)
		diplomacy.change_relation(sanctioner, target, float(settings.get("lift_relation", 0.0)))
	refresh(state, sanctioner)
	refresh(state, target)
	state.add_event(EVENT_SANCTION, sanctioner, {"target": target, "measure": measure, "active": active})


## Recalcule les effets de tous les pays (après des sanctions de l'ONU).
static func refresh_all(state: SimState) -> void:
	var now := all_penalties(state, {})
	for tag: String in now.keys():
		var country := state.get_country(tag)
		var start: Dictionary = state.diplomacy.start_sanction_effects.get(tag, {"growth": 0.0, "inflation": 0.0})
		country.economy.sanction_growth = float(now[tag]["growth"]) - float(start["growth"])
		country.economy.sanction_inflation = float(now[tag]["inflation"]) - float(start["inflation"])


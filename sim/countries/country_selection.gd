class_name CountrySelection
extends RefCounted
## Difficulté et défis de départ de chaque pays, pour l'écran de sélection.
##
## Difficulté : score de puissance (PIB et armée, échelle logarithmique, avec un plancher)
## diminué du poids des défis, puis classé en niveaux par les seuils de defines.country_selection.
## Un pays peut imposer son niveau (« difficulty »).
## Défis : ceux écrits pour le pays (« challenges ») s'il en a, sinon les défis génériques
## dont la règle s'applique.

const MIN_DIFFICULTY := 1
const MAX_DIFFICULTY := 5
## Filtre « toutes les difficultés ».
const ANY_DIFFICULTY := 0
const USD_PER_BILLION := 1.0e9

## tag → niveau de difficulté (1 à 5).
var difficulties: Dictionary = {}
## tag → identifiants des défis, dans l'ordre d'affichage.
var challenges: Dictionary = {}
## tag → true pour les entités non reconnues (mode avancé).
var limited_recognition: Dictionary = {}


## settings : section « country_selection » de defines.json.
static func build(countries: Dictionary, provinces: Dictionary, challenge_defs: Dictionary,
		settings: Dictionary) -> CountrySelection:
	var selection := CountrySelection.new()
	var stats := province_stats(provinces)
	for tag: String in countries.keys():
		var country: Dictionary = countries[tag]
		var country_stats: Dictionary = stats.get(tag, {})
		var ids := challenges_for(country, country_stats, challenge_defs)
		selection.challenges[tag] = ids
		selection.difficulties[tag] = difficulty_for(country, ids, challenge_defs, settings)
		selection.limited_recognition[tag] = bool(country.get("limited_recognition", false))
	return selection


## Par pays : provinces occupées par un autre pays et accès à la mer.
static func province_stats(provinces: Dictionary) -> Dictionary:
	var stats: Dictionary = {}
	for province: Dictionary in provinces.values():
		var owner := str(province.get("owner", ""))
		if owner.is_empty():
			continue
		if not stats.has(owner):
			stats[owner] = {"occupied": 0, "coastal": false}
		var entry: Dictionary = stats[owner]
		if str(province.get("controller", owner)) != owner:
			entry["occupied"] = int(entry["occupied"]) + 1
		if bool(province.get("coastal", false)):
			entry["coastal"] = true
	return stats


static func challenges_for(country: Dictionary, stats: Dictionary, challenge_defs: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if country.has("challenges"):
		for challenge_id: Variant in country["challenges"]:
			if challenge_defs.has(str(challenge_id)):
				result.append(str(challenge_id))
		return result
	var ids: Array = challenge_defs.keys()
	ids.sort()
	for challenge_id: Variant in ids:
		var rule: Dictionary = (challenge_defs[challenge_id] as Dictionary).get("rule", {})
		if not rule.is_empty() and rule_matches(rule, country, stats):
			result.append(str(challenge_id))
	return result


static func rule_matches(rule: Dictionary, country: Dictionary, stats: Dictionary) -> bool:
	var threshold := float(rule.get("threshold", 0.0))
	var economy: Dictionary = country.get("economy", {})
	match str(rule.get("type", "")):
		"debt_above":
			return float(economy.get("debt_to_gdp", 0.0)) > threshold
		"gdp_per_capita_below":
			var population := int(country.get("population", 0))
			return population > 0 and float(economy.get("gdp_billion_usd", 0.0)) * USD_PER_BILLION / population < threshold
		"occupied_provinces":
			return int(stats.get("occupied", 0)) > 0
		"limited_recognition":
			return bool(country.get("limited_recognition", false))
		"coalition_partners_at_least":
			return (country.get("coalition_partners", []) as Array).size() >= int(threshold)
		"regime":
			return (rule.get("regimes", []) as Array).has(str(country.get("regime", "")))
		"landlocked":
			return not bool(stats.get("coastal", false))
		"military_below":
			return float((country.get("military", {}) as Dictionary).get("active_personnel", 0.0)) < threshold
	return false


## Puissance de départ : log10 du PIB (Md$) et des effectifs d'active, pondérés, avec un plancher.
static func power_score(country: Dictionary, settings: Dictionary) -> float:
	var gdp := maxf(float((country.get("economy", {}) as Dictionary).get("gdp_billion_usd", 0.0)), 0.0)
	var personnel := maxf(float((country.get("military", {}) as Dictionary).get("active_personnel", 0.0)), 0.0)
	var score := float(settings.get("gdp_weight", 1.0)) * _log10(gdp + 1.0) \
		+ float(settings.get("military_weight", 0.0)) * _log10(personnel + 1.0)
	return maxf(score, float(settings.get("power_floor", 0.0)))


static func difficulty_for(country: Dictionary, challenge_ids: Array[String], challenge_defs: Dictionary,
		settings: Dictionary) -> int:
	if country.has("difficulty"):
		return clampi(int(country["difficulty"]), MIN_DIFFICULTY, MAX_DIFFICULTY)
	var score := power_score(country, settings)
	for challenge_id: String in challenge_ids:
		score -= float((challenge_defs.get(challenge_id, {}) as Dictionary).get("weight", 0.0))
	var thresholds: Array = settings.get("difficulty_thresholds", [])
	for index: int in thresholds.size():
		if score >= float(thresholds[index]):
			return mini(MIN_DIFFICULTY + index, MAX_DIFFICULTY)
	return mini(MIN_DIFFICULTY + thresholds.size(), MAX_DIFFICULTY)


## Pays proposés : filtrés par difficulté (ANY_DIFFICULTY = toutes) et par reconnaissance.
func playable_tags(include_limited: bool, difficulty: int = ANY_DIFFICULTY) -> Array[String]:
	var result: Array[String] = []
	for tag: String in difficulties.keys():
		if not include_limited and bool(limited_recognition.get(tag, false)):
			continue
		if difficulty != ANY_DIFFICULTY and int(difficulties[tag]) != difficulty:
			continue
		result.append(tag)
	result.sort()
	return result


func is_playable(tag: String, include_limited: bool) -> bool:
	return difficulties.has(tag) and (include_limited or not bool(limited_recognition.get(tag, false)))


static func _log10(value: float) -> float:
	return log(value) / log(10.0)

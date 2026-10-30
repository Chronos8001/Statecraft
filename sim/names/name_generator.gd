class_name NameGenerator
extends RefCounted
## Génère des personnages et des noms de partis fictifs à partir des cultures de noms
## (data/names/cultures) et des styles de noms de partis (data/names/party_styles).
## Le tirage dépend uniquement de la graine : même graine, mêmes noms.

const GIVEN_FIRST := "given_first"
const FAMILY_FIRST := "family_first"
const MALE := "male"
const FEMALE := "female"

var _cultures: Dictionary
var _party_styles: Dictionary
var _ideologies: Dictionary
var _traits: Dictionary
var _settings: Dictionary
var _rng := RandomNumberGenerator.new()


## settings : section « characters » de defines.json.
func _init(cultures: Dictionary, party_styles: Dictionary, ideologies: Dictionary, traits: Dictionary,
		settings: Dictionary, seed_value: int) -> void:
	_cultures = cultures
	_party_styles = party_styles
	_ideologies = ideologies
	_traits = traits
	_settings = settings
	_rng.seed = seed_value


## Prénom et nom ({first_name, last_name}) tirés dans la culture.
func generate_name(culture_id: String, gender: String) -> Dictionary:
	var culture: Dictionary = _cultures.get(culture_id, {})
	var given: Array = culture.get("female_names" if gender == FEMALE else "male_names", [])
	var family: Array = culture.get("family_names", [])
	var female_family: Array = culture.get("female_family_names", [])
	var count: int = clampi(int(culture.get("family_name_count", 1)), 1, maxi(family.size(), 1))
	var parts := PackedStringArray()
	var used: Array[int] = []
	while parts.size() < count and not family.is_empty():
		var index := _rng.randi_range(0, family.size() - 1)
		if used.has(index):
			continue
		used.append(index)
		var use_female_form := gender == FEMALE and index < female_family.size()
		parts.append(str(female_family[index] if use_female_form else family[index]))
	return {
		"first_name": str(given[_rng.randi_range(0, given.size() - 1)]) if not given.is_empty() else "",
		"last_name": " ".join(parts),
	}


## Sexe tiré selon la part de femmes parmi les responsables politiques de la culture.
func pick_gender(culture_id: String) -> String:
	var culture: Dictionary = _cultures.get(culture_id, {})
	var share := float(culture.get("female_share", _settings.get("default_female_share", 0.0)))
	return FEMALE if _rng.randf() < share else MALE


## Personnage complet (sans identifiant). birth_year <= 0 : âge tiré dans la fourchette des réglages.
func generate_character(country: String, culture_id: String, gender: String, birth_year: int,
		ideology: String) -> Dictionary:
	var character := generate_name(culture_id, gender)
	if birth_year <= 0:
		var start_year := int(_settings.get("reference_year", 2026))
		birth_year = start_year - _rng.randi_range(int(_settings.get("min_age", 35)), int(_settings.get("max_age", 70)))
	character["birth_year"] = birth_year
	character["gender"] = gender
	character["country"] = country
	character["culture"] = culture_id
	character["ideology"] = ideology
	character["traits"] = generate_traits()
	character["skills"] = generate_skills()
	return character


## Au plus un trait par groupe de traits, chacun avec la probabilité des réglages.
## Les traits marqués "random": false (orientation diplomatique…) ne sont jamais tirés.
func generate_traits() -> Array:
	var by_group: Dictionary = {}
	var trait_ids: Array = _traits.keys()
	trait_ids.sort()
	for trait_id: Variant in trait_ids:
		var trait_data: Dictionary = _traits[trait_id]
		if not bool(trait_data.get("random", true)):
			continue
		var group := str(trait_data.get("group", ""))
		if not by_group.has(group):
			by_group[group] = []
		(by_group[group] as Array).append(trait_id)
	var groups: Array = by_group.keys()
	groups.sort()
	var chance := float(_settings.get("trait_chance", 1.0))
	var result: Array = []
	for group: Variant in groups:
		var candidates: Array = by_group[group]
		if _rng.randf() < chance:
			result.append(candidates[_rng.randi_range(0, candidates.size() - 1)])
	return result


func generate_skills() -> Dictionary:
	var low := int(_settings.get("min_skill", 1))
	var high := int(_settings.get("max_skill", 10))
	var skills: Dictionary = {}
	for skill: Variant in _settings.get("skills", []):
		skills[str(skill)] = _rng.randi_range(low, high)
	return skills


## Nom de parti ({name, abbreviation}) adapté à l'idéologie, différent des noms déjà pris.
## Renvoie un dictionnaire vide si la culture n'a aucun nom disponible.
func generate_party_name(culture_id: String, ideology: String, taken: Array = []) -> Dictionary:
	var culture: Dictionary = _cultures.get(culture_id, {})
	var style: Dictionary = _party_styles.get(str(culture.get("party_style", "")), {})
	var names: Dictionary = style.get("names", {})
	var group := str((_ideologies.get(ideology, {}) as Dictionary).get("party_group", ""))
	var fallbacks: Dictionary = _settings.get("party_group_fallbacks", {})
	var visited: Array[String] = []
	while not group.is_empty() and not visited.has(group):
		visited.append(group)
		var candidates: Array = []
		for candidate: Variant in names.get(group, []):
			if not taken.has(candidate):
				candidates.append(candidate)
		if not candidates.is_empty():
			var picked: Variant = candidates[_rng.randi_range(0, candidates.size() - 1)]
			return {"name": picked, "abbreviation": abbreviate(picked, style.get("stopwords", []))}
		group = str(fallbacks.get(group, ""))
	return {}


## Couleur d'un nouveau parti : celle de son idéologie, éclaircie ou assombrie au hasard.
func party_color(ideology: String) -> String:
	var base := Color.html(str((_ideologies.get(ideology, {}) as Dictionary).get("color", "#808080")))
	var spread := float(_settings.get("party_color_spread", 0.0))
	var shift := _rng.randf_range(-spread, spread)
	var color := base.lightened(shift) if shift >= 0.0 else base.darkened(-shift)
	return "#" + color.to_html(false).to_upper()


## Sigle d'un nom : initiales des mots qui ne sont pas des mots vides (« de », « of »…).
## Pour un nom traduit, le sigle est tiré du nom anglais.
static func abbreviate(name: Variant, stopwords: Array = []) -> String:
	var text := str((name as Dictionary).get("en", "")) if name is Dictionary else str(name)
	var letters := ""
	for raw_word: String in text.replace("-", " ").split(" ", false):
		var word := raw_word
		var apostrophe := maxi(word.rfind("'"), word.rfind("’"))
		if apostrophe >= 0:
			word = word.substr(apostrophe + 1)
		if word.is_empty() or stopwords.has(word.to_lower()):
			continue
		letters += word.left(1).to_upper()
	return letters


## Nom affiché d'un personnage, dans l'ordre de sa culture (« Wei Jianguo » pour une culture family_first).
static func full_name(character: Dictionary, cultures: Dictionary) -> String:
	if character.is_empty():
		return ""
	var first := str(character.get("first_name", ""))
	var last := str(character.get("last_name", ""))
	var culture: Dictionary = cultures.get(str(character.get("culture", "")), {})
	var parts := [last, first] if str(culture.get("name_order", GIVEN_FIRST)) == FAMILY_FIRST else [first, last]
	return ("%s %s" % parts).strip_edges()

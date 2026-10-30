extends SceneTree
## Génère les dirigeants et partis fictifs des pays décrits dans config.json, avec le même
## générateur de noms que le jeu. Résultat stable : la graine dépend uniquement du pays.
## Lancer : godot --headless --path . -s tools/leader_gen/generate_leaders.gd

const CONFIG_PATH := "res://tools/leader_gen/config.json"
const DATA_ROOT := "res://data"
const NAMES_OUTPUT := "res://data/names/generated.json"
const POLITICS_OUTPUT := "res://data/countries/politics_generated.json"
const HAND_WRITTEN_POLITICS := "res://data/countries/politics.json"
const HAND_WRITTEN_PARTIES := "res://data/names/parties.json"
const HAND_WRITTEN_CHARACTERS := "res://data/names/characters.json"
const SHARED_PREFIX := "@"
const NONPARTISAN_FLAG := "np"
const CULTURE_FLAG := "culture="
const ROLE_HEAD_OF_STATE := "head_of_state"
const ROLE_HEAD_OF_GOVERNMENT := "head_of_government"
const ROYAL_TRAIT := "royal"
const NO_PARTY := -1
const MAX_NAME_ATTEMPTS := 50

var _repository := DataRepository.new()
var _characters: Dictionary = {}
var _parties: Dictionary = {}
var _politics: Dictionary = {}
## Noms de partis déjà pris dans le monde (partis écrits à la main, puis partis générés).
var _used_party_names: Array = []
## Noms complets déjà portés (homonymes interdits) et noms exclus (personnes réelles connues).
var _used_full_names: Dictionary = {}
var _forbidden_full_names: Array = []
## Noms de famille déjà portés dans le pays en cours.
var _country_family_names: Dictionary = {}


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	_repository.load_roots(PackedStringArray([DATA_ROOT]))
	var config: Dictionary = _read(CONFIG_PATH)
	_forbidden_full_names = config.get("forbidden_full_names", [])
	for party: Variant in (_read(HAND_WRITTEN_PARTIES).get("parties", {}) as Dictionary).values():
		_used_party_names.append((party as Dictionary).get("name"))
	for character: Variant in (_read(HAND_WRITTEN_CHARACTERS).get("characters", {}) as Dictionary).values():
		_used_full_names[_full_name(character)] = true
	var hand_written: Dictionary = _read(HAND_WRITTEN_POLITICS)
	var countries: Dictionary = config.get("countries", {})
	var errors := PackedStringArray()
	for tag: String in _sorted_keys(countries):
		if hand_written.has(tag):
			errors.append("%s : décrit à la fois dans config.json et dans politics.json." % tag)
			continue
		errors.append_array(_generate_country(tag, countries[tag], str(config.get("seed_salt", ""))))
	if not errors.is_empty():
		for error: String in errors:
			printerr(error)
		return 1
	_write_table(NAMES_OUTPUT, {"characters": _characters, "parties": _parties}, 2)
	_write_table(POLITICS_OUTPUT, _politics, 1)
	print("%d pays, %d personnages, %d partis générés." % [_politics.size(), _characters.size(), _parties.size()])
	return 0


func _generate_country(tag: String, spec: Dictionary, salt: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var culture := str(spec.get("culture", ""))
	if not _repository.get_category("names/cultures").has(culture):
		errors.append("%s : culture inconnue « %s »." % [tag, culture])
		return errors
	var generator := NameGenerator.new(_repository.get_category("names/cultures"),
		_repository.get_category("names/party_styles"), _repository.get_category("ideologies"),
		_repository.get_category("traits"), _repository.get_value("defines", "characters", {}),
		(salt + tag).hash())
	var prefix := tag.to_lower()
	_country_family_names.clear()

	# Partis : le premier gouverne, les suivants sont ses partenaires de coalition.
	var party_ids: Array[String] = []
	var taken: Array = []
	var party_ideologies: Array = spec.get("parties", [])
	for index: int in party_ideologies.size():
		var ideology := str(party_ideologies[index])
		# Un nom libre dans le monde entier si possible, sinon seulement dans le pays.
		var party_name := generator.generate_party_name(culture, ideology, _used_party_names + taken)
		if party_name.is_empty():
			party_name = generator.generate_party_name(culture, ideology, taken)
		if party_name.is_empty():
			errors.append("%s : aucun nom de parti disponible pour l'idéologie « %s »." % [tag, ideology])
			continue
		taken.append(party_name["name"])
		_used_party_names.append(party_name["name"])
		var party_id := "pty_%s_%d" % [prefix, index + 1]
		_parties[party_id] = {
			"name": party_name["name"], "abbreviation": party_name["abbreviation"], "country": tag,
			"ideology": ideology, "color": generator.party_color(ideology),
		}
		party_ids.append(party_id)
	if not errors.is_empty():
		return errors

	var has_government := spec.has(ROLE_HEAD_OF_GOVERNMENT)
	var head_of_state := _person(tag, prefix, ROLE_HEAD_OF_STATE, spec[ROLE_HEAD_OF_STATE], culture,
		generator, party_ids, not has_government, errors)
	var head_of_government := head_of_state
	if has_government:
		head_of_government = _person(tag, prefix, ROLE_HEAD_OF_GOVERNMENT,
			spec[ROLE_HEAD_OF_GOVERNMENT], culture, generator, party_ids, true, errors)

	# Chef de chaque parti : le dirigeant qui en est membre, sinon un nouveau personnage.
	for index: int in party_ids.size():
		var party_id := party_ids[index]
		var leader := ""
		for candidate: String in [head_of_government, head_of_state]:
			if str((_characters.get(candidate, {}) as Dictionary).get("party", "")) == party_id:
				leader = candidate
				break
		if leader.is_empty():
			leader = "chr_%s_party_%d_leader" % [prefix, index + 1]
			var ideology := str(_parties[party_id]["ideology"])
			var character := generator.generate_character(tag, culture, generator.pick_gender(culture), 0,
				ideology)
			_make_unique(character, generator)
			character["party"] = party_id
			_characters[leader] = character
		_parties[party_id]["leader"] = leader

	var politics: Dictionary = {
		"culture": culture, "ideology": str(spec.get("ideology", "")),
		ROLE_HEAD_OF_STATE: head_of_state, ROLE_HEAD_OF_GOVERNMENT: head_of_government,
	}
	if not party_ids.is_empty():
		politics["ruling_party"] = party_ids[0]
	if party_ids.size() > 1:
		politics["coalition_partners"] = party_ids.slice(1)
	_politics[tag] = politics
	return errors


## Crée un dirigeant décrit par [année, sexe, idéologie, options…] ou reprend celui d'un autre
## pays (« @GBR » : le chef de l'État britannique). Options : index de parti, « np » (sans parti),
## « culture=… » ou identifiant de trait imposé.
func _person(tag: String, prefix: String, role: String, spec: Variant, culture: String,
		generator: NameGenerator, party_ids: Array[String], member_by_default: bool,
		errors: PackedStringArray) -> String:
	if spec is String and (spec as String).begins_with(SHARED_PREFIX):
		var other := (spec as String).substr(SHARED_PREFIX.length())
		var shared := str(_repository.get_entry("countries", other).get(ROLE_HEAD_OF_STATE, ""))
		if shared.is_empty():
			errors.append("%s : pas de chef de l'État pour %s." % [tag, other])
		return shared
	var values: Array = spec
	var forced_traits: Array = []
	var party_index := 0 if member_by_default else NO_PARTY
	var explicit_party := false
	var character_culture := culture
	for option: Variant in values.slice(3):
		if option is float or option is int:
			party_index = int(option)
			explicit_party = true
		elif str(option) == NONPARTISAN_FLAG:
			party_index = NO_PARTY
			explicit_party = true
		elif str(option).begins_with(CULTURE_FLAG):
			character_culture = str(option).substr(CULTURE_FLAG.length())
		elif _repository.get_category("traits").has(str(option)):
			forced_traits.append(str(option))
		else:
			errors.append("%s : option inconnue « %s »." % [tag, str(option)])
	# Un monarque n'appartient à aucun parti, sauf indication contraire.
	if forced_traits.has(ROYAL_TRAIT) and not explicit_party:
		party_index = NO_PARTY
	var character := generator.generate_character(tag, character_culture, str(values[1]),
		int(values[0]), str(values[2]))
	_make_unique(character, generator)
	character["traits"] = _merge_traits(character["traits"], forced_traits)
	if party_index >= 0 and party_index < party_ids.size():
		character["party"] = party_ids[party_index]
	var character_id := "chr_%s_%s" % [prefix, role]
	_characters[character_id] = character
	return character_id


## Tire un autre nom tant que le personnage serait l'homonyme d'un autre, porterait un nom exclu
## ou le même nom de famille qu'un autre dirigeant du pays.
func _make_unique(character: Dictionary, generator: NameGenerator) -> void:
	var attempts := 0
	while not _is_name_free(character) and attempts < MAX_NAME_ATTEMPTS:
		character.merge(generator.generate_name(str(character["culture"]), str(character["gender"])), true)
		attempts += 1
	_used_full_names[_full_name(character)] = true
	_country_family_names[str(character["last_name"])] = true


func _is_name_free(character: Dictionary) -> bool:
	var full_name := _full_name(character)
	if _used_full_names.has(full_name) or _country_family_names.has(str(character["last_name"])):
		return false
	for forbidden: Variant in _forbidden_full_names:
		if full_name.begins_with(str(forbidden)):
			return false
	return true


static func _full_name(character: Dictionary) -> String:
	return "%s %s" % [character.get("first_name", ""), character.get("last_name", "")]


## Ajoute les traits imposés en remplaçant le trait tiré au hasard du même groupe.
func _merge_traits(random_traits: Array, forced_traits: Array) -> Array:
	var traits := _repository.get_category("traits")
	var forced_groups: Array = forced_traits.map(func(t: Variant) -> String: return str(traits[t]["group"]))
	var result: Array = forced_traits.duplicate()
	for trait_id: Variant in random_traits:
		if not forced_groups.has(str(traits[trait_id]["group"])):
			result.append(trait_id)
	return result


## Écrit un objet JSON avec une entrée par ligne à la profondeur donnée (1 ou 2).
func _write_table(path: String, table: Dictionary, depth: int) -> void:
	var lines := PackedStringArray()
	if depth == 1:
		for key: String in _sorted_keys(table):
			lines.append('  "%s": %s' % [key, JSON.stringify(table[key], "", false)])
	else:
		for section: String in table.keys():
			var section_table: Dictionary = table[section]
			var entries := PackedStringArray()
			for key: String in _sorted_keys(section_table):
				entries.append('    "%s": %s' % [key, JSON.stringify(section_table[key], "", false)])
			lines.append('  "%s": {\n%s\n  }' % [section, ",\n".join(entries)])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\n" + ",\n".join(lines) + "\n}\n")


static func _read(path: String) -> Dictionary:
	return DataRepository.read_json(path).get("data", {})


static func _sorted_keys(table: Dictionary) -> Array:
	var keys: Array = table.keys()
	keys.sort()
	return keys

extends SceneTree
## Génère les chambres basses de départ (sièges, dernier scrutin, sondages) et les partis d'opposition
## fictifs, avec le même générateur de noms que le jeu. Pays décrits dans config.json : composition
## réelle au 1er janvier 2026 ; autres pays : règles de config.json. Résultat stable (graine par pays).
## Lancer : godot --headless --path . -s tools/parliament_gen/generate_parliaments.gd

const CONFIG_PATH := "res://tools/parliament_gen/config.json"
const DATA_ROOT := "res://data"
const NAMES_OUTPUT := "res://data/names/opposition.json"
const PARLIAMENT_OUTPUT := "res://data/countries/parliament.json"
const RULING := "ruling"
const PARTNER_PREFIX := "p"
const GOVERNMENT_PREFIX := "+"
const OTHERS := "others"
const PERCENT := 100.0
const MAX_NAME_ATTEMPTS := 50

var _repository := DataRepository.new()
var _characters: Dictionary = {}
var _parties: Dictionary = {}
var _parliaments: Dictionary = {}
var _used_party_names: Array = []
var _used_full_names: Dictionary = {}
## Noms de famille déjà portés dans chaque pays : tag → {nom: true}.
var _family_names: Dictionary = {}
var _rules: Dictionary = {}
## Sigles de vrais partis à ne pas reprendre (en majuscules).
var _forbidden_abbreviations: Array = []


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	_repository.load_roots(PackedStringArray([DATA_ROOT]))
	var config: Dictionary = DataRepository.read_json(CONFIG_PATH).get("data", {})
	_rules = config.get("rules", {})
	_forbidden_abbreviations = config.get("forbidden_abbreviations", [])
	var names: Dictionary = _repository.get_category("names")
	# Les partis déjà générés par ce même outil sont ignorés (on les recrée).
	for party_id: String in (names.get("parties", {}) as Dictionary).keys():
		if not party_id.contains("_opp_"):
			_used_party_names.append(names["parties"][party_id].get("name"))
	for character_id: String in (names.get("characters", {}) as Dictionary).keys():
		if not character_id.contains("_opp_"):
			var character: Dictionary = names["characters"][character_id]
			_used_full_names[_full_name(character)] = true
			_remember_family_name(character)
	var described: Dictionary = config.get("countries", {})
	var countries := _repository.get_category("countries")
	var errors := PackedStringArray()
	var tags: Array = countries.keys()
	tags.sort()
	for tag: String in tags:
		var generator := NameGenerator.new(_repository.get_category("names/cultures"),
			_repository.get_category("names/party_styles"), _repository.get_category("ideologies"),
			_repository.get_category("traits"), _repository.get_value("defines", "characters", {}),
			("%s-%s" % [config.get("seed_salt", ""), tag]).hash())
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s-%s-rules" % [config.get("seed_salt", ""), tag])
		if described.has(tag):
			errors.append_array(_from_config(tag, countries[tag], described[tag], generator))
		else:
			_from_rules(tag, countries[tag], generator, rng)
	if not errors.is_empty():
		for error: String in errors:
			printerr(error)
		return 1
	_write_table(NAMES_OUTPUT, {"characters": _characters, "parties": _parties}, 2)
	_write_table(PARLIAMENT_OUTPUT, _parliaments, 1)
	print("%d parlements (%d décrits), %d partis d'opposition, %d chefs de parti." % [_parliaments.size(),
		described.size(), _parties.size(), _characters.size()])
	return 0


func _from_config(tag: String, country: Dictionary, spec: Dictionary, generator: NameGenerator) -> PackedStringArray:
	var errors := PackedStringArray()
	var ruling := str(country.get("ruling_party", ""))
	var partners: Array = country.get("coalition_partners", [])
	var seats := int(spec["seats"])
	var parliament := _empty_parliament(seats, spec["election"], int(spec.get("term", _rules["term_years"])))
	if bool(spec.get("dissolved", false)):
		parliament["dissolved"] = true
	var entries: Array = spec["parties"]
	var total_seats := 0
	var total_seat_share := 0.0
	var index := 0
	for entry: Array in entries:
		var ref := str(entry[0])
		var party_seats := int(entry[1])
		total_seats += party_seats
		var vote: float = float(entry[2]) if entry[2] != null else party_seats * PERCENT / seats
		var poll: float = float(entry[3]) if entry[3] != null else vote
		if ref == OTHERS:
			parliament["other_seats"] = party_seats
			parliament["other_vote"] = vote
			parliament["other_poll"] = poll
			continue
		var party_id := ""
		var in_government := false
		if ref == RULING:
			party_id = ruling
			in_government = true
		elif ref.begins_with(PARTNER_PREFIX) and ref.substr(1).is_valid_int():
			var partner_index := int(ref.substr(1))
			party_id = str(partners[partner_index]) if partner_index < partners.size() else ""
			in_government = true
		else:
			in_government = ref.begins_with(GOVERNMENT_PREFIX)
			index += 1
			party_id = _new_party(tag, country, ref.trim_prefix(GOVERNMENT_PREFIX), index, generator)
		if party_id.is_empty():
			errors.append("%s : « %s » ne correspond à aucun parti au pouvoir." % [tag, ref])
			continue
		parliament["parties"][party_id] = {"seats": party_seats, "vote": snappedf(vote, 0.1), "poll": snappedf(poll, 0.1)}
		if in_government:
			parliament["government"].append(party_id)
	if total_seats != seats:
		errors.append("%s : %d sièges répartis pour %d." % [tag, total_seats, seats])
	for party_id: Variant in [ruling] + partners:
		if not str(party_id).is_empty() and not parliament["parties"].has(party_id):
			errors.append("%s : le parti au pouvoir %s manque." % [tag, party_id])
	_parliaments[tag] = {"parliament": parliament}
	return errors


## Chambre estimée : majorité de gouvernement et deux ou trois partis d'opposition en démocratie,
## parti dominant et un petit parti toléré ailleurs, chambre sans partis quand personne ne gouverne.
func _from_rules(tag: String, country: Dictionary, generator: NameGenerator, rng: RandomNumberGenerator) -> void:
	var bounds: Array = _rules["seat_bounds"]
	var seats := clampi(roundi(pow(float(country.get("population", 0)), 1.0 / 3.0) * float(_rules["seats_per_cube_root"])),
		int(bounds[0]), int(bounds[1]))
	var term := int(_rules["term_years"])
	var parliament := _empty_parliament(seats, [2025 - rng.randi_range(0, term - 1), rng.randi_range(1, 12)], term)
	_parliaments[tag] = {"parliament": parliament}
	var ruling := str(country.get("ruling_party", ""))
	if ruling.is_empty():
		parliament["other_seats"] = seats
		return
	var partners: Array = country.get("coalition_partners", [])
	var democratic := bool(_repository.get_entry("regimes", str(country.get("regime", ""))).get("democratic", false))
	var ideologies := _repository.get_category("ideologies")
	var ruling_ideology := str(_repository.resolve_ref("names#parties").get(ruling, {}).get("ideology", ""))
	var ruling_group := str((ideologies.get(ruling_ideology, {}) as Dictionary).get("party_group", ""))
	var opposite := str((_rules["group_ideology"] as Dictionary).get(
		str((_rules["opposite_groups"] as Dictionary).get(ruling_group, "liberal")), "liberal"))
	var others := roundi(seats * float(_rules["others_share"]))
	var share_bounds: Array = _rules["democratic_government_share" if democratic else "dominant_share"]
	var government := roundi(seats * rng.randf_range(float(share_bounds[0]), float(share_bounds[1])))
	var ruling_seats := government if partners.is_empty() else roundi(government * float(_rules["government_ruling_share"]))
	_add_seats(parliament, ruling, ruling_seats, true)
	var left := government - ruling_seats
	for i: int in partners.size():
		var partner_seats := left / (partners.size() - i)
		_add_seats(parliament, str(partners[i]), partner_seats, true)
		left -= partner_seats
	var opposition_ideologies: Array[String] = [opposite]
	for ideology: Variant in _rules["third_ideologies"]:
		if opposition_ideologies.size() < 3 and str(ideology) != ruling_ideology and not opposition_ideologies.has(str(ideology)):
			opposition_ideologies.append(str(ideology))
	var opposition := seats - government - others
	if not democratic:
		opposition = mini(roundi(seats * float(_rules["allowed_party_share"])), opposition)
		opposition_ideologies = [opposite]
		others = seats - government - opposition
	var split: Array = _rules["opposition_split"] if democratic else [1.0]
	var placed := 0
	for i: int in opposition_ideologies.size():
		var party_seats := opposition - placed if i == opposition_ideologies.size() - 1 \
			else roundi(opposition * float(split[i]))
		placed += party_seats
		var party_id := _new_party(tag, country, opposition_ideologies[i], i + 1, generator)
		_add_seats(parliament, party_id, party_seats, false)
	parliament["other_seats"] = others
	var vote := others * PERCENT / seats
	parliament["other_vote"] = snappedf(vote, 0.1)
	parliament["other_poll"] = snappedf(vote, 0.1)


func _add_seats(parliament: Dictionary, party_id: String, seats: int, in_government: bool) -> void:
	var share := snappedf(seats * PERCENT / int(parliament["seats"]), 0.1)
	parliament["parties"][party_id] = {"seats": seats, "vote": share, "poll": share}
	if in_government:
		parliament["government"].append(party_id)


func _empty_parliament(seats: int, election: Array, term: int) -> Dictionary:
	return {"seats": seats, "parties": {}, "government": [], "other_seats": 0, "other_vote": 0.0, "other_poll": 0.0,
		"election": {"year": int(election[0]), "month": int(election[1])}, "term_years": term}


## Nouveau parti fictif et son chef.
func _new_party(tag: String, country: Dictionary, ideology: String, index: int, generator: NameGenerator) -> String:
	var culture := str(country.get("culture", ""))
	# Nom unique dans le monde si possible, sinon seulement dans le pays ; jamais le sigle d'un vrai parti.
	var party_name := _pick_party_name(culture, ideology, _used_party_names.duplicate(), generator)
	if party_name.is_empty():
		party_name = _pick_party_name(culture, ideology, _country_party_names(tag), generator)
	if party_name.is_empty():
		party_name = generator.generate_party_name(culture, ideology, [])
	_used_party_names.append(party_name["name"])
	var prefix := tag.to_lower()
	var party_id := "pty_%s_opp_%d" % [prefix, index]
	var leader_id := "chr_%s_opp_%d_leader" % [prefix, index]
	var years: Array = _rules["leader_birth_years"]
	var birth := int(years[0]) + absi(hash(leader_id)) % (int(years[1]) - int(years[0]) + 1)
	var leader := generator.generate_character(tag, culture, generator.pick_gender(culture), birth, ideology)
	var attempts := 0
	while not _is_name_free(leader) and attempts < MAX_NAME_ATTEMPTS:
		leader.merge(generator.generate_name(culture, str(leader["gender"])), true)
		attempts += 1
	_used_full_names[_full_name(leader)] = true
	_remember_family_name(leader)
	leader["party"] = party_id
	_characters[leader_id] = leader
	_parties[party_id] = {"name": party_name["name"], "abbreviation": party_name["abbreviation"], "country": tag,
		"ideology": ideology, "color": generator.party_color(ideology), "leader": leader_id}
	return party_id


## Premier nom proposé dont le sigle n'est pas celui d'un vrai parti ; vide si les noms sont épuisés.
func _pick_party_name(culture: String, ideology: String, taken: Array, generator: NameGenerator) -> Dictionary:
	for _attempt: int in MAX_NAME_ATTEMPTS:
		var party_name := generator.generate_party_name(culture, ideology, taken)
		if party_name.is_empty():
			return {}
		if not _forbidden_abbreviations.has(str(party_name["abbreviation"]).to_upper()):
			return party_name
		taken.append(party_name["name"])
	return {}


func _country_party_names(tag: String) -> Array:
	var result: Array = []
	for party: Dictionary in _repository.resolve_ref("names#parties").values():
		if str(party.get("country", "")) == tag and not str(party.get("name", "")).is_empty():
			result.append(party["name"])
	for party: Dictionary in _parties.values():
		if str(party.get("country", "")) == tag:
			result.append(party["name"])
	return result


func _is_name_free(character: Dictionary) -> bool:
	var family: Dictionary = _family_names.get(str(character.get("country", "")), {})
	return not _used_full_names.has(_full_name(character)) and not family.has(str(character.get("last_name", "")))


func _remember_family_name(character: Dictionary) -> void:
	var tag := str(character.get("country", ""))
	if not _family_names.has(tag):
		_family_names[tag] = {}
	_family_names[tag][str(character.get("last_name", ""))] = true


static func _full_name(character: Dictionary) -> String:
	return "%s %s" % [character.get("first_name", ""), character.get("last_name", "")]


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


static func _sorted_keys(table: Dictionary) -> Array:
	var keys: Array = table.keys()
	keys.sort()
	return keys

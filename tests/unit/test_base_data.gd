extends GutTest
## Vérifie que les données livrées avec le jeu sont valides et cohérentes.

const DETAILED_COUNTRIES := ["BRA", "CHN", "DEU", "FRA", "USA"]
const MIN_COUNTRY_COUNT := 190
const MIN_PROVINCE_COUNT := 4000
const LOCALIZATION_DIR := "res://data/localization"
const TRANSLATED_CATEGORIES := ["countries", "provinces", "sea_zones", "straits", "ideologies", "regimes",
	"terrains", "resources"]
const MIN_SEA_ZONE_COUNT := 150

const LocalizationScript := preload("res://core/localization/localization.gd")

var _repository: DataRepository
var _messages: Dictionary = {}


func before_all() -> void:
	_repository = DataRepository.new()
	_repository.load_roots(PackedStringArray([ModManager.BASE_DATA_ROOT]))
	_repository.validate()
	for file_name: String in DirAccess.get_files_at(LOCALIZATION_DIR):
		if file_name.get_extension() == "csv":
			_messages = JsonMerge.merge(_messages, LocalizationScript.parse_csv(LOCALIZATION_DIR.path_join(file_name)))


func test_base_data_has_no_error() -> void:
	assert_eq(_repository.errors.size(), 0, "\n".join(_repository.errors.slice(0, 20)))
	assert_eq(_repository.warnings.size(), 0, "\n".join(_repository.warnings))


func test_world_is_covered() -> void:
	var countries := _repository.get_category("countries")
	assert_gt(countries.size(), MIN_COUNTRY_COUNT)
	assert_gt(_repository.get_category("provinces").size(), MIN_PROVINCE_COUNT)
	for tag: String in DETAILED_COUNTRIES:
		assert_true((countries[tag] as Dictionary).has("head_of_state"), "%s détaillé" % tag)


func test_each_country_capital_belongs_to_it() -> void:
	var countries := _repository.get_category("countries")
	for tag: String in countries.keys():
		var capital := SchemaValidator.to_key(countries[tag]["capital"])
		assert_eq(_repository.get_entry("provinces", capital).get("owner"), tag, "capitale de %s" % tag)


func test_province_color_encodes_its_id() -> void:
	var provinces := _repository.get_category("provinces").merged(_repository.get_category("sea_zones"))
	var mismatches: Array[String] = []
	for province_id: String in provinces.keys():
		var id := int(province_id)
		var expected := "#%02X%02X00" % [id & 0xFF, (id >> 8) & 0xFF]
		if str(provinces[province_id]["color"]).to_upper() != expected:
			mismatches.append(province_id)
	assert_eq(mismatches.size(), 0, "provinces : %s" % str(mismatches.slice(0, 10)))


func test_sea_zones_follow_provinces() -> void:
	var info: Dictionary = _repository.get_category("map")["map"]
	var sea_zones := _repository.get_category("sea_zones")
	assert_gt(sea_zones.size(), MIN_SEA_ZONE_COUNT)
	assert_eq(int(info["max_id"]), int(info["province_count"]) + sea_zones.size())
	for zone_id: String in sea_zones.keys():
		assert_gt(int(zone_id), int(info["province_count"]), "zone %s numérotée après les provinces" % zone_id)


func test_coastal_flag_matches_sea_neighbors() -> void:
	var provinces := _repository.get_category("provinces")
	var sea_zones := _repository.get_category("sea_zones")
	var mismatches: int = 0
	for province_id: String in provinces.keys():
		var province: Dictionary = provinces[province_id]
		var sea_neighbors: Array = province["sea_neighbors"]
		if bool(province["coastal"]) != not sea_neighbors.is_empty():
			mismatches += 1
		for zone: Variant in sea_neighbors:
			var coasts: Array = sea_zones[SchemaValidator.to_key(zone)]["coasts"]
			if not coasts.has(float(province_id)):
				mismatches += 1
	assert_eq(mismatches, 0)


func test_straits_connect_two_sea_zones() -> void:
	var straits := _repository.get_category("straits")
	for strait_id: String in ["suez", "panama", "hormuz", "malacca", "bosphorus", "gibraltar"]:
		assert_true(straits.has(strait_id), strait_id)
		var strait: Dictionary = straits[strait_id]
		assert_eq((strait["sea_zones"] as Array).size(), 2, strait_id)
		assert_gt((strait["provinces"] as Array).size(), 0, strait_id)


func test_owned_provinces_have_a_controller() -> void:
	var provinces := _repository.get_category("provinces")
	for province_id: String in provinces.keys():
		var province: Dictionary = provinces[province_id]
		assert_eq(province.has("owner"), province.has("controller"), "province %s" % province_id)


func test_neighbors_are_symmetric() -> void:
	var provinces := _repository.get_category("provinces")
	var broken: int = 0
	for province_id: String in provinces.keys():
		for neighbor: Variant in provinces[province_id]["neighbors"]:
			var other: Dictionary = provinces[SchemaValidator.to_key(neighbor)]
			if not (other["neighbors"] as Array).has(float(province_id)):
				broken += 1
	assert_eq(broken, 0)


func test_characters_belong_to_their_country() -> void:
	var characters: Dictionary = _repository.resolve_ref("names#characters")
	var countries := _repository.get_category("countries")
	for tag: String in countries.keys():
		for role: String in ["head_of_state", "head_of_government"]:
			if (countries[tag] as Dictionary).has(role):
				var character: Dictionary = characters[countries[tag][role]]
				assert_eq(character["country"], tag, "%s de %s" % [role, tag])


func test_start_date_is_january_first_2026() -> void:
	var start := GameDate.from_dict(_repository.get_value("defines", "game.start_date", {}))
	assert_eq(start.format_iso(), "2026-01-01 00:00")


func test_every_name_key_is_translated() -> void:
	var missing: Array[String] = []
	for category: String in TRANSLATED_CATEGORIES:
		var table := _repository.get_category(category)
		for entry_id: String in table.keys():
			var key: String = table[entry_id]["name_key"]
			for locale: String in ["en", "fr"]:
				if not (_messages[locale] as Dictionary).has(key):
					missing.append("%s (%s)" % [key, locale])
	assert_eq(missing.size(), 0, str(missing.slice(0, 10)))

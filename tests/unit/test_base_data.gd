extends GutTest
## Vérifie que les données livrées avec le jeu sont valides et cohérentes.

const EXPECTED_COUNTRIES := ["BRA", "CHN", "DEU", "FRA", "USA"]

var _repository: DataRepository


func before_all() -> void:
	_repository = DataRepository.new()
	_repository.load_roots(PackedStringArray([ModManager.BASE_DATA_ROOT]))
	_repository.validate()


func test_base_data_has_no_error() -> void:
	assert_eq(_repository.errors.size(), 0, "\n".join(_repository.errors))
	assert_eq(_repository.warnings.size(), 0, "\n".join(_repository.warnings))


func test_sample_countries_are_present() -> void:
	var tags: Array = _repository.get_category("countries").keys()
	tags.sort()
	assert_eq(tags, EXPECTED_COUNTRIES)


func test_each_country_capital_belongs_to_it() -> void:
	var countries := _repository.get_category("countries")
	for tag: String in countries.keys():
		var capital := SchemaValidator.to_key(countries[tag]["capital"])
		assert_eq(_repository.get_entry("provinces", capital).get("owner"), tag, "capitale de %s" % tag)


func test_characters_belong_to_their_country() -> void:
	var characters: Dictionary = _repository.resolve_ref("names#characters")
	var countries := _repository.get_category("countries")
	for tag: String in countries.keys():
		for role: String in ["head_of_state", "head_of_government"]:
			var character: Dictionary = characters[countries[tag][role]]
			assert_eq(character["country"], tag, "%s de %s" % [role, tag])


func test_start_date_is_january_first_2026() -> void:
	var start := GameDate.from_dict(_repository.get_value("defines", "game.start_date", {}))
	assert_eq(start.format_iso(), "2026-01-01 00:00")


func test_every_name_key_is_translated() -> void:
	var messages := Localization.parse_csv("res://data/localization/data.csv")
	for category: String in ["countries", "provinces", "ideologies", "regimes", "terrains", "resources"]:
		var table := _repository.get_category(category)
		for entry_id: String in table.keys():
			var key: String = table[entry_id]["name_key"]
			for locale: String in ["en", "fr"]:
				assert_true((messages[locale] as Dictionary).has(key), "%s manquant en %s" % [key, locale])

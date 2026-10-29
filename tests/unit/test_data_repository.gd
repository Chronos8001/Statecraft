extends GutTest

const BASE_ROOT := "res://tests/fixtures/base_data"
const MOD_ROOT := "res://tests/fixtures/mods/mod_alpha/data"
const TEMP_ROOT := "user://test_tmp/broken_data"


func after_all() -> void:
	DirAccess.remove_absolute(TEMP_ROOT.path_join("broken.json"))
	DirAccess.remove_absolute(TEMP_ROOT)


func test_category_names() -> void:
	assert_eq(DataRepository.category_for("defines.json"), "defines")
	assert_eq(DataRepository.category_for("countries/a.json"), "countries")
	assert_eq(DataRepository.category_for("names/cultures/fr.json"), "names/cultures")


func test_lists_files_recursively_and_sorted() -> void:
	var files := DataRepository.list_json_files(BASE_ROOT)
	assert_eq(files, PackedStringArray(["defines.json", "countries/a.json", "countries/b.json", "schemas/core.json"]))


func test_loads_and_merges_files_of_a_category() -> void:
	var repository := DataRepository.new()
	repository.load_roots(PackedStringArray([BASE_ROOT]))
	assert_eq(repository.get_file_count(), 4)
	assert_eq(repository.get_category("countries").size(), 3)
	assert_eq(repository.get_value("defines", "time.default_speed"), 3.0)
	assert_eq(repository.get_value("defines", "time.missing", 7), 7)


func test_mod_overrides_base_data() -> void:
	var repository := DataRepository.new()
	repository.load_roots(PackedStringArray([BASE_ROOT, MOD_ROOT]))
	var countries := repository.get_category("countries")
	assert_eq(repository.get_file_count(), 5)
	assert_eq(countries["AAA"]["population"], 99.0, "valeur surchargée")
	assert_eq(countries["AAA"]["name"], "Alpha", "valeur non touchée conservée")
	assert_eq(countries["AAA"]["tags"], ["z"], "tableau remplacé")
	assert_false(countries.has("BBB"), "entrée supprimée par null")
	assert_true(countries.has("DDD"), "entrée ajoutée")


func test_valid_data_passes_schema() -> void:
	var repository := DataRepository.new()
	repository.load_roots(PackedStringArray([BASE_ROOT, MOD_ROOT]))
	repository.validate()
	assert_eq(repository.errors.size(), 0, str(repository.errors))


func test_schema_errors_are_reported() -> void:
	var repository := DataRepository.new()
	repository.load_roots(PackedStringArray([BASE_ROOT]))
	repository.categories["countries"]["CCC"]["color"] = "#111111"
	repository.validate()
	assert_eq(repository.errors.size(), 1, str(repository.errors))


func test_invalid_json_is_reported_not_loaded() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_ROOT)
	var file := FileAccess.open(TEMP_ROOT.path_join("broken.json"), FileAccess.WRITE)
	file.store_string("{ \"a\": ")
	file.close()
	var repository := DataRepository.new()
	repository.load_roots(PackedStringArray([TEMP_ROOT]))
	assert_eq(repository.get_file_count(), 0)
	assert_eq(repository.errors.size(), 1)
	assert_string_contains(repository.errors[0], "broken.json")


func test_missing_root_is_a_warning() -> void:
	var repository := DataRepository.new()
	repository.load_roots(PackedStringArray(["res://tests/fixtures/does_not_exist"]))
	assert_eq(repository.warnings.size(), 1)
	assert_eq(repository.errors.size(), 0)

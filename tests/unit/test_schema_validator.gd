extends GutTest

const ENTRY_SCHEMA := {
	"type": "object",
	"strict": true,
	"required": ["name", "population"],
	"properties": {
		"name": {"type": "string"},
		"population": {"type": "int", "min": 0},
		"color": {"type": "color"},
		"kind": {"type": "string", "enum": ["a", "b"]},
		"tags": {"type": "array", "unique_items": true, "items": {"type": "string"}},
		"label": {"type": "loc_string"},
	},
}


func _validate(value: Variant, schema: Dictionary, repository: DataRepository = null) -> PackedStringArray:
	return SchemaValidator.new(repository).validate(value, schema, "root")


func test_valid_entry_has_no_error() -> void:
	var entry := {"name": "France", "population": 68700000.0, "color": "#4F6EC9", "kind": "a",
		"tags": ["x"], "label": {"en": "Hi", "fr": "Salut"}}
	assert_eq(_validate(entry, ENTRY_SCHEMA).size(), 0)


func test_missing_required_field() -> void:
	var errors := _validate({"name": "France"}, ENTRY_SCHEMA)
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "population")


func test_wrong_types_and_bounds() -> void:
	var entry := {"name": 12, "population": -5.0, "color": "bleu", "kind": "c"}
	assert_eq(_validate(entry, ENTRY_SCHEMA).size(), 4)


func test_int_rejects_decimal_number() -> void:
	assert_eq(_validate({"name": "X", "population": 1.5}, ENTRY_SCHEMA).size(), 1)


func test_strict_rejects_unknown_field() -> void:
	var errors := _validate({"name": "X", "population": 1, "typo": true}, ENTRY_SCHEMA)
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "typo")


func test_unique_items() -> void:
	assert_eq(_validate({"name": "X", "population": 1, "tags": ["a", "a"]}, ENTRY_SCHEMA).size(), 1)


func test_table_keys_and_unique_fields() -> void:
	var schema := {"type": "object", "keys_pattern": "^[A-Z]{3}$", "unique_fields": ["color"], "values": ENTRY_SCHEMA}
	var table := {
		"FRA": {"name": "A", "population": 1, "color": "#000001"},
		"fr": {"name": "B", "population": 1, "color": "#000001"},
	}
	var errors := _validate(table, schema)
	assert_eq(errors.size(), 2, str(errors))


func test_references_are_checked() -> void:
	var repository := DataRepository.new()
	repository.categories = {"countries": {"FRA": {}}, "names": {"characters": {"chr_a": {}}}}
	var schema := {"type": "object", "properties": {
		"owner": {"type": "string", "ref": "countries"},
		"leader": {"type": "string", "ref": "names#characters"},
	}}
	assert_eq(_validate({"owner": "FRA", "leader": "chr_a"}, schema, repository).size(), 0)
	assert_eq(_validate({"owner": "XXX", "leader": "chr_b"}, schema, repository).size(), 2)


func test_numeric_reference_matches_string_key() -> void:
	var repository := DataRepository.new()
	repository.categories = {"provinces": {"12": {}}}
	var schema := {"type": "int", "ref": "provinces"}
	assert_eq(_validate(12.0, schema, repository).size(), 0)

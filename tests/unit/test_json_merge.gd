extends GutTest


func test_merges_nested_objects() -> void:
	var base := {"a": {"x": 1, "y": 2}, "b": 3}
	var result: Dictionary = JsonMerge.merge(base, {"a": {"y": 20, "z": 30}})
	assert_eq(result, {"a": {"x": 1, "y": 20, "z": 30}, "b": 3})


func test_arrays_are_replaced_not_concatenated() -> void:
	var result: Dictionary = JsonMerge.merge({"list": [1, 2]}, {"list": [3]})
	assert_eq(result["list"], [3])


func test_null_removes_key() -> void:
	var result: Dictionary = JsonMerge.merge({"keep": 1, "drop": 2}, {"drop": null})
	assert_eq(result, {"keep": 1})


func test_replace_marker_replaces_whole_object() -> void:
	var base := {"entry": {"a": 1, "b": 2}}
	var result: Dictionary = JsonMerge.merge(base, {"entry": {"__replace": true, "c": 3}})
	assert_eq(result, {"entry": {"c": 3}})


func test_base_is_not_modified() -> void:
	var base := {"a": {"x": 1}}
	JsonMerge.merge(base, {"a": {"x": 2}})
	assert_eq(base, {"a": {"x": 1}})

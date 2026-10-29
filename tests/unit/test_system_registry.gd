extends GutTest

const RegistryScript := preload("res://core/system_registry.gd")

var _registry: Node


func before_each() -> void:
	_registry = autofree(RegistryScript.new())


func test_unknown_key_resolves_to_null() -> void:
	assert_null(_registry.resolve(&"war_resolver"))
	assert_false(_registry.has_provider(&"war_resolver"))


func test_highest_priority_wins() -> void:
	var base := RefCounted.new()
	var dlc := RefCounted.new()
	_registry.register(&"war_resolver", dlc, 10, "dlc")
	_registry.register(&"war_resolver", base, 0, "base")
	assert_eq(_registry.resolve(&"war_resolver"), dlc)
	assert_eq(_registry.get_source(&"war_resolver"), "dlc")


func test_same_priority_last_registered_wins() -> void:
	var first := RefCounted.new()
	var second := RefCounted.new()
	_registry.register(&"military_ai", first)
	_registry.register(&"military_ai", second)
	assert_eq(_registry.resolve(&"military_ai"), second)


func test_unregister_falls_back_to_previous_provider() -> void:
	var base := RefCounted.new()
	var dlc := RefCounted.new()
	_registry.register(&"military_model", base, 0)
	_registry.register(&"military_model", dlc, 10)
	_registry.unregister(&"military_model", dlc)
	assert_eq(_registry.resolve(&"military_model"), base)
	_registry.unregister(&"military_model", base)
	assert_false(_registry.has_provider(&"military_model"))

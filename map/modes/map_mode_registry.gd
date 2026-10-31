class_name MapModeRegistry
extends RefCounted
## Crée les modes de carte décrits dans data/map_modes/, triés par « order ».


var modes: Array[MapMode] = []


static func from_definitions(definitions: Dictionary) -> MapModeRegistry:
	var registry := MapModeRegistry.new()
	var ids: Array = definitions.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(definitions[a].get("order", 0)) < int(definitions[b].get("order", 0)))
	for mode_id: String in ids:
		var definition: Dictionary = definitions[mode_id]
		var mode := create_mode(mode_id, definition)
		if mode == null:
			GameLog.warn("MapModeRegistry", "Type de mode de carte inconnu : %s" % definition.get("kind", ""))
			continue
		registry.modes.append(mode)
	return registry


static func create_mode(mode_id: String, definition: Dictionary) -> MapMode:
	match str(definition.get("kind", "")):
		"political":
			return PoliticalMapMode.new(mode_id, definition)
		"terrain":
			return TerrainMapMode.new(mode_id, definition)
		"province_gradient":
			return ProvinceGradientMapMode.new(mode_id, definition)
		"country_gradient":
			return CountryGradientMapMode.new(mode_id, definition)
		"ideology":
			return IdeologyMapMode.new(mode_id, definition)
		"alliance":
			return AllianceMapMode.new(mode_id, definition)
		"relations":
			return RelationsMapMode.new(mode_id, definition)
		"resources":
			return ResourceMapMode.new(mode_id, definition)
		"control":
			return ControlMapMode.new(mode_id, definition)
		"trade":
			return TradeMapMode.new(mode_id, definition)
	return null


func get_mode(mode_id: String) -> MapMode:
	var index := index_of(mode_id)
	return modes[index] if index >= 0 else null


func index_of(mode_id: String) -> int:
	for i: int in modes.size():
		if modes[i].id == mode_id:
			return i
	return -1

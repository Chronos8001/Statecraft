extends Node
## Registre des modules remplaçables (point d'extension pour les DLC et les mods).
## Chaque clé (ex. &"war_resolver") peut avoir plusieurs fournisseurs : celui de plus haute
## priorité gagne, et à priorité égale le plus récemment enregistré.

const SOURCE := "SystemRegistry"

var _providers: Dictionary = {}
var _sequence: int = 0


func register(key: StringName, provider: Object, priority: int = 0, source: String = "base") -> void:
	if provider == null:
		GameLog.error(SOURCE, "Fournisseur nul pour « %s »." % key)
		return
	_sequence += 1
	var entries: Array = _providers.get(key, [])
	entries.append({"provider": provider, "priority": priority, "source": source, "order": _sequence})
	entries.sort_custom(_is_before)
	_providers[key] = entries
	EventBus.system_registered.emit(key)


func unregister(key: StringName, provider: Object) -> void:
	var entries: Array = _providers.get(key, [])
	entries = entries.filter(func(entry: Dictionary) -> bool: return entry["provider"] != provider)
	if entries.is_empty():
		_providers.erase(key)
	else:
		_providers[key] = entries


func resolve(key: StringName) -> Object:
	var entries: Array = _providers.get(key, [])
	if entries.is_empty():
		return null
	return entries[0]["provider"]


func has_provider(key: StringName) -> bool:
	return _providers.has(key)


func get_source(key: StringName) -> String:
	var entries: Array = _providers.get(key, [])
	if entries.is_empty():
		return ""
	return str(entries[0]["source"])


func get_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for key: StringName in _providers.keys():
		keys.append(key)
	return keys


func clear() -> void:
	_providers.clear()


static func _is_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["priority"]) != int(b["priority"]):
		return int(a["priority"]) > int(b["priority"])
	return int(a["order"]) > int(b["order"])

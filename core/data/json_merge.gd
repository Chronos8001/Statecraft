class_name JsonMerge
extends RefCounted
## Fusion profonde de données JSON (données de base + surcharges de DLC et de mods).
## Règles :
##   - objet + objet : fusion clé par clé, récursive ;
##   - autre cas : la surcharge remplace la valeur (les tableaux sont remplacés, pas concaténés) ;
##   - valeur null dans la surcharge : la clé est supprimée ;
##   - "__replace": true dans un objet de surcharge : l'objet remplace entièrement l'existant.

const REPLACE_KEY := "__replace"


static func merge(base: Variant, overlay: Variant) -> Variant:
	if not (base is Dictionary and overlay is Dictionary):
		return _clean(overlay)
	var over: Dictionary = overlay
	if bool(over.get(REPLACE_KEY, false)):
		return _clean(over)
	var result: Dictionary = (base as Dictionary).duplicate(true)
	for key: Variant in over.keys():
		if key == REPLACE_KEY:
			continue
		var value: Variant = over[key]
		if typeof(value) == TYPE_NIL:
			result.erase(key)
		elif result.has(key):
			result[key] = merge(result[key], value)
		else:
			result[key] = _clean(value)
	return result


## Copie profonde qui retire les marqueurs de fusion et les valeurs null.
static func _clean(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var out: Dictionary = {}
		for key: Variant in source.keys():
			if key == REPLACE_KEY or typeof(source[key]) == TYPE_NIL:
				continue
			out[key] = _clean(source[key])
		return out
	if value is Array:
		var out_array: Array = []
		for item: Variant in (value as Array):
			out_array.append(_clean(item))
		return out_array
	return value

class_name SchemaValidator
extends RefCounted
## Valide des données selon un sous-ensemble simple de JSON Schema, décrit dans data/schemas/.
##
## Mots-clés reconnus :
##   type          any | string | int | number | bool | array | object | color | loc_string
##   enum          liste des valeurs autorisées
##   min, max      bornes numériques
##   pattern       expression régulière (chaînes)
##   ref           la valeur doit être une clé existante : "countries" ou "names#characters"
##   required      champs obligatoires (objets)
##   properties    schéma de chaque champ connu (objets)
##   values        schéma appliqué aux autres champs (objets utilisés comme tables d'entrées)
##   strict        refuse les champs non décrits (objets)
##   keys_pattern  regex des clés (objets)
##   keys_ref      les clés doivent exister dans une autre table (objets)
##   unique_fields champs dont la valeur doit être unique parmi les entrées (objets)
##   items         schéma des éléments (tableaux)
##   min_items     taille minimale (tableaux)
##   unique_items  éléments sans doublon (tableaux)

const COLOR_PATTERN := "^#[0-9A-Fa-f]{6}$"

var _repository: DataRepository
var _errors: PackedStringArray = PackedStringArray()
var _regex_cache: Dictionary = {}


func _init(repository: DataRepository = null) -> void:
	_repository = repository


func validate(value: Variant, schema: Dictionary, path: String) -> PackedStringArray:
	_errors = PackedStringArray()
	_check(value, schema, path)
	return _errors


## Convertit une valeur JSON en clé de table (les nombres entiers arrivent en float).
static func to_key(value: Variant) -> String:
	if value is float and is_equal_approx(value, floorf(value)):
		return str(int(value))
	return str(value)


func _check(value: Variant, schema: Dictionary, path: String) -> void:
	if not _check_type(value, str(schema.get("type", "any")), path):
		return
	if schema.has("enum"):
		var allowed: Array = schema["enum"]
		if not allowed.has(value):
			_fail(path, "valeur « %s » non autorisée (attendu : %s)" % [str(value), str(allowed)])
	if value is float or value is int:
		var number: float = value
		if schema.has("min") and number < float(schema["min"]):
			_fail(path, "%s est inférieur au minimum %s" % [str(value), str(schema["min"])])
		if schema.has("max") and number > float(schema["max"]):
			_fail(path, "%s est supérieur au maximum %s" % [str(value), str(schema["max"])])
	if value is String and schema.has("pattern"):
		if not _matches(value, str(schema["pattern"])):
			_fail(path, "« %s » ne respecte pas le format %s" % [value, schema["pattern"]])
	if schema.has("ref"):
		_check_ref(value, str(schema["ref"]), path)
	if value is Array:
		_check_array(value, schema, path)
	elif value is Dictionary:
		_check_object(value, schema, path)


func _check_type(value: Variant, type_name: String, path: String) -> bool:
	var ok: bool = false
	match type_name:
		"any":
			ok = true
		"string":
			ok = value is String
		"int":
			ok = value is int or (value is float and is_equal_approx(value, floorf(value)))
		"number":
			ok = value is int or value is float
		"bool":
			ok = value is bool
		"array":
			ok = value is Array
		"object":
			ok = value is Dictionary
		"color":
			ok = value is String and _matches(value, COLOR_PATTERN)
		"loc_string":
			ok = _is_loc_string(value)
		_:
			_fail(path, "type de schéma inconnu « %s »" % type_name)
			return false
	if not ok:
		_fail(path, "type attendu %s, reçu %s" % [type_name, type_string(typeof(value))])
	return ok


func _check_array(array: Array, schema: Dictionary, path: String) -> void:
	if schema.has("min_items") and array.size() < int(schema["min_items"]):
		_fail(path, "au moins %d élément(s) attendu(s)" % int(schema["min_items"]))
	if schema.has("items"):
		var item_schema: Dictionary = schema["items"]
		for i: int in array.size():
			_check(array[i], item_schema, "%s[%d]" % [path, i])
	if bool(schema.get("unique_items", false)):
		var seen: Dictionary = {}
		for item: Variant in array:
			var key := to_key(item)
			if seen.has(key):
				_fail(path, "élément « %s » en double" % key)
			seen[key] = true


func _check_object(object: Dictionary, schema: Dictionary, path: String) -> void:
	var properties: Dictionary = schema.get("properties", {})
	var required: Array = schema.get("required", [])
	for field: Variant in required:
		if not object.has(field):
			_fail(path, "champ obligatoire « %s » manquant" % str(field))
	var is_strict: bool = bool(schema.get("strict", false))
	for key: Variant in object.keys():
		var child_path := "%s.%s" % [path, str(key)]
		if properties.has(key):
			_check(object[key], properties[key], child_path)
		elif schema.has("values"):
			_check(object[key], schema["values"], child_path)
		elif is_strict:
			_fail(child_path, "champ inconnu")
		if schema.has("keys_pattern") and not _matches(str(key), str(schema["keys_pattern"])):
			_fail(child_path, "identifiant invalide (format %s)" % schema["keys_pattern"])
		if schema.has("keys_ref"):
			_check_ref(key, str(schema["keys_ref"]), child_path)
	var unique_fields: Array = schema.get("unique_fields", [])
	for field: Variant in unique_fields:
		_check_unique_field(object, str(field), path)


func _check_unique_field(table: Dictionary, field: String, path: String) -> void:
	var seen: Dictionary = {}
	for entry_id: Variant in table.keys():
		var entry: Variant = table[entry_id]
		if not entry is Dictionary or not (entry as Dictionary).has(field):
			continue
		var value := to_key((entry as Dictionary)[field]).to_upper()
		if seen.has(value):
			_fail("%s.%s.%s" % [path, str(entry_id), field], "valeur « %s » déjà utilisée par « %s »" % [value, seen[value]])
		else:
			seen[value] = str(entry_id)


func _check_ref(value: Variant, ref: String, path: String) -> void:
	if _repository == null:
		return
	var key := to_key(value)
	if not _repository.resolve_ref(ref).has(key):
		_fail(path, "référence « %s » introuvable dans %s" % [key, ref])


func _is_loc_string(value: Variant) -> bool:
	if value is String:
		return true
	if not value is Dictionary or (value as Dictionary).is_empty():
		return false
	for text: Variant in (value as Dictionary).values():
		if not text is String:
			return false
	return true


func _matches(text: String, pattern: String) -> bool:
	if not _regex_cache.has(pattern):
		var regex := RegEx.new()
		if regex.compile(pattern) != OK:
			_fail("schéma", "expression régulière invalide : %s" % pattern)
			return false
		_regex_cache[pattern] = regex
	var compiled: RegEx = _regex_cache[pattern]
	return compiled.search(text) != null


func _fail(path: String, message: String) -> void:
	_errors.append("%s : %s" % [path, message])

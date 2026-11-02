class_name EventModStore
extends RefCounted
## Événements d'un mod pour l'éditeur : liste et création des mods, lecture et écriture de leurs événements
## (data/events/editor_events.json) et de leurs textes (data/localization/editor_events.csv, colonnes keys,en,fr),
## validation d'un événement (schéma des données et langage de conditions et d'effets).

const EVENTS_FILE := "data/events/editor_events.json"
const TEXTS_FILE := "data/localization/editor_events.csv"
const MANIFEST := "mod.json"
const LOCALES := ["en", "fr"]
const ID_PATTERN := "^[a-z0-9_]+$"
const KEY_PREFIX := "EVENT_"
const MAX_OPTIONS := 4


static func list_mods(base_dir: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(base_dir):
		return result
	var folders := DirAccess.get_directories_at(base_dir)
	folders.sort()
	for folder: String in folders:
		var path := base_dir.path_join(folder)
		var manifest := path.path_join(MANIFEST)
		if not FileAccess.file_exists(manifest):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		var name := str((data as Dictionary).get("name", folder)) if data is Dictionary else folder
		result.append({"id": folder, "name": name, "path": path})
	return result


## Crée un mod vide (manifeste) ; renvoie son dossier, ou "" si l'identifiant est invalide ou déjà pris.
static func create_mod(base_dir: String, mod_id: String, mod_name: String) -> String:
	if not RegEx.create_from_string(ID_PATTERN).search(mod_id):
		return ""
	var path := base_dir.path_join(mod_id)
	if DirAccess.dir_exists_absolute(path):
		return ""
	DirAccess.make_dir_recursive_absolute(path)
	var manifest := {"id": mod_id, "name": mod_name, "version": "1.0.0", "load_order": 0, "enabled": true}
	_write(path.path_join(MANIFEST), JSON.stringify(manifest, "  ") + "\n")
	return path


static func load_events(mod_path: String) -> Dictionary:
	var path := mod_path.path_join(EVENTS_FILE)
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## Textes du mod : clé → {en, fr}.
static func load_texts(mod_path: String) -> Dictionary:
	var path := mod_path.path_join(TEXTS_FILE)
	var result: Dictionary = {}
	if not FileAccess.file_exists(path):
		return result
	var by_locale := Localization.parse_csv(path)
	for locale: Variant in by_locale.keys():
		for key: Variant in (by_locale[locale] as Dictionary).keys():
			if not result.has(key):
				result[key] = {}
			(result[key] as Dictionary)[str(locale)] = str(by_locale[locale][key])
	return result


static func save(mod_path: String, events: Dictionary, texts: Dictionary) -> void:
	var ids: Array = events.keys()
	ids.sort()
	var ordered: Dictionary = {}
	for id: Variant in ids:
		ordered[id] = events[id]
	_write(mod_path.path_join(EVENTS_FILE), JSON.stringify(ordered, "  ", false) + "\n")
	var lines := PackedStringArray(["keys," + ",".join(LOCALES)])
	var keys: Array = texts.keys()
	keys.sort()
	for key: Variant in keys:
		var cells := PackedStringArray([str(key)])
		for locale: String in LOCALES:
			cells.append(_csv_cell(str((texts[key] as Dictionary).get(locale, ""))))
		lines.append(",".join(cells))
	_write(mod_path.path_join(TEXTS_FILE), "\n".join(lines) + "\n")


static func _csv_cell(text: String) -> String:
	if text.contains(",") or text.contains("\"") or text.contains("\n"):
		return "\"%s\"" % text.replace("\"", "\"\"")
	return text


static func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)


## Clés de texte d'un événement : titre, description, puis un nom par choix.
static func text_keys(id: String, option_count: int) -> PackedStringArray:
	var base := KEY_PREFIX + id.to_upper()
	var keys := PackedStringArray([base + "_TITLE", base + "_DESC"])
	for index: int in option_count:
		keys.append("%s_%s" % [base, String.chr("A".unicode_at(0) + index)])
	return keys


## Nouvel événement de pays, avec un choix, prêt à être modifié.
static func new_event(id: String) -> Dictionary:
	var keys := text_keys(id, 1)
	return {"title_key": keys[0], "desc_key": keys[1], "scope": "country", "mtth_months": 60,
		"trigger": {}, "options": [{"name_key": keys[2], "effects": {}, "ai_weight": 1}]}


## Erreurs d'un événement : identifiant, schéma des données, conditions et effets (avec les autres événements
## connus pour les chaînes), textes manquants.
static func validate(id: String, definition: Dictionary, known_events: Dictionary, texts: Dictionary,
		schema: Dictionary, repository: DataRepository) -> PackedStringArray:
	var errors := PackedStringArray()
	if not RegEx.create_from_string(ID_PATTERN).search(id):
		errors.append(TranslationServer.translate("EDITOR_ERROR_ID"))
	if not schema.is_empty() and repository != null:
		errors.append_array(SchemaValidator.new(repository).validate({id: definition}, schema, "events"))
	var all := known_events.duplicate()
	all[id] = definition
	# Les chaînes peuvent viser tous les événements connus : on valide l'ensemble et on garde ceux de cet événement.
	var prefix := "événement %s " % id
	for message: String in EventSystem.validate_definitions(all):
		if message.begins_with(prefix) or message.begins_with("événement %s :" % id):
			errors.append(message)
	if (definition.get("options", []) as Array).size() > MAX_OPTIONS:
		errors.append(TranslationServer.translate("EDITOR_ERROR_OPTIONS") % MAX_OPTIONS)
	for key: String in _used_keys(definition):
		var entry: Dictionary = texts.get(key, {})
		if str(entry.get("en", "")).is_empty() and str(entry.get("fr", "")).is_empty() \
				and TranslationServer.translate(key) == key:
			errors.append(TranslationServer.translate("EDITOR_ERROR_TEXT") % key)
	return errors


static func _used_keys(definition: Dictionary) -> PackedStringArray:
	var keys := PackedStringArray([str(definition.get("title_key", "")), str(definition.get("desc_key", ""))])
	for option: Variant in definition.get("options", []):
		keys.append(str((option as Dictionary).get("name_key", "")))
	return keys

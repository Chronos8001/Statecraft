extends Node
## Localisation FR / EN. Les textes sont dans des fichiers CSV <racine de données>/localization/*.csv
## (colonnes : keys,en,fr…), lus au démarrage pour que les mods puissent ajouter ou remplacer
## des traductions. Les nœuds d'interface affichent des clés traduites automatiquement par Godot.

const SOURCE := "Localization"
const LOCALIZATION_SUBDIR := "localization"
const CSV_EXTENSION := "csv"
const KEY_COLUMN := "keys"
const COMMENT_PREFIX := "#"
const FALLBACK_LOCALE := "en"
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "general"
const SETTINGS_LOCALE_KEY := "locale"

var available_locales: PackedStringArray = PackedStringArray()
var _messages: Dictionary = {}
var _translations: Array[Translation] = []


func _ready() -> void:
	reload()
	set_locale(_initial_locale(), false)


func reload() -> void:
	for translation: Translation in _translations:
		TranslationServer.remove_translation(translation)
	_translations.clear()
	_messages = {}
	for root: String in ModManager.get_data_roots():
		var directory := root.path_join(LOCALIZATION_SUBDIR)
		if not DirAccess.dir_exists_absolute(directory):
			continue
		var files := DirAccess.get_files_at(directory)
		files.sort()
		for file_name: String in files:
			if file_name.get_extension().to_lower() == CSV_EXTENSION:
				_messages = JsonMerge.merge(_messages, parse_csv(directory.path_join(file_name)))
	available_locales = PackedStringArray()
	var key_count: int = 0
	for locale: String in _messages.keys():
		var translation := Translation.new()
		translation.locale = locale
		var table: Dictionary = _messages[locale]
		for key: String in table.keys():
			translation.add_message(key, str(table[key]))
		TranslationServer.add_translation(translation)
		_translations.append(translation)
		available_locales.append(locale)
		key_count = maxi(key_count, table.size())
	available_locales.sort()
	GameLog.info(SOURCE, "%d langue(s) (%s), %d clé(s)." % [available_locales.size(), ", ".join(available_locales), key_count])


func get_locale() -> String:
	return TranslationServer.get_locale()


func set_locale(locale: String, save: bool = true) -> void:
	var chosen := locale if available_locales.has(locale) else FALLBACK_LOCALE
	TranslationServer.set_locale(chosen)
	if save:
		var config := ConfigFile.new()
		config.load(SETTINGS_PATH)
		config.set_value(SETTINGS_SECTION, SETTINGS_LOCALE_KEY, chosen)
		config.save(SETTINGS_PATH)
	EventBus.locale_changed.emit(chosen)


## Texte d'une clé dans une langue précise (ex. nom natif d'une langue pour le menu Options).
func get_message_in(locale: String, key: String) -> String:
	var table: Dictionary = _messages.get(locale, {})
	return str(table.get(key, key))


## Texte d'une valeur de données localisable : chaîne simple ou {"en": "...", "fr": "..."}.
func pick_text(value: Variant) -> String:
	return pick_text_for(value, get_locale())


static func pick_text_for(value: Variant, locale: String) -> String:
	if not value is Dictionary:
		return str(value)
	var texts: Dictionary = value
	if texts.has(locale):
		return str(texts[locale])
	if texts.has(FALLBACK_LOCALE):
		return str(texts[FALLBACK_LOCALE])
	return str(texts.values()[0]) if not texts.is_empty() else ""


## Lit un CSV de traductions : renvoie {locale: {clé: texte}}.
static func parse_csv(path: String) -> Dictionary:
	var result: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		GameLog.warn(SOURCE, "Fichier illisible : %s" % path)
		return result
	var header := file.get_csv_line()
	if header.size() < 2 or header[0].strip_edges() != KEY_COLUMN:
		GameLog.warn(SOURCE, "En-tête invalide (attendu « keys,en,fr… ») : %s" % path)
		return result
	for column: int in range(1, header.size()):
		result[header[column].strip_edges()] = {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty():
			continue
		var key := row[0].strip_edges()
		if key.is_empty() or key.begins_with(COMMENT_PREFIX):
			continue
		for column: int in range(1, mini(row.size(), header.size())):
			var text := row[column].trim_suffix("\r")
			if not text.is_empty():
				(result[header[column].strip_edges()] as Dictionary)[key] = text
	return result


func _initial_locale() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK and config.has_section_key(SETTINGS_SECTION, SETTINGS_LOCALE_KEY):
		return str(config.get_value(SETTINGS_SECTION, SETTINGS_LOCALE_KEY))
	var system_language := OS.get_locale_language()
	return system_language if available_locales.has(system_language) else FALLBACK_LOCALE

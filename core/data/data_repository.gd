class_name DataRepository
extends RefCounted
## Charge, fusionne et valide les fichiers JSON d'une liste de dossiers de données.
## Classe pure (sans nœud) : utilisée par l'autoload DataLoader et directement par les tests.
##
## Catégories : un fichier data/<dossier>/<x>.json appartient à la catégorie « <dossier> »
## (ex. countries/, names/cultures/) ; un fichier à la racine data/<x>.json forme la
## catégorie « <x> » (ex. defines). Tous les fichiers d'une catégorie sont fusionnés,
## dans l'ordre alphabétique puis dans l'ordre des sources (base, DLC, mods).

const SCHEMA_CATEGORY := "schemas"
const DATA_EXTENSION := "json"
const REF_SEPARATOR := "#"

var categories: Dictionary = {}
var loaded_files: PackedStringArray = PackedStringArray()
var errors: PackedStringArray = PackedStringArray()
var warnings: PackedStringArray = PackedStringArray()


func get_file_count() -> int:
	return loaded_files.size()


func load_roots(roots: PackedStringArray) -> void:
	for root: String in roots:
		if not DirAccess.dir_exists_absolute(root):
			warnings.append("%s : dossier de données introuvable." % root)
			continue
		for relative_path: String in list_json_files(root):
			_load_file(root, relative_path)


func validate() -> void:
	var schemas: Dictionary = categories.get(SCHEMA_CATEGORY, {})
	var validator := SchemaValidator.new(self)
	for category: String in schemas.keys():
		var schema: Variant = schemas[category]
		if not schema is Dictionary:
			errors.append("schemas.%s : le schéma doit être un objet." % category)
			continue
		if not categories.has(category):
			warnings.append("Catégorie « %s » décrite par un schéma mais absente des données." % category)
			continue
		errors.append_array(validator.validate(categories[category], schema, category))


func get_category(category: String) -> Dictionary:
	return categories.get(category, {})


func get_entry(category: String, entry_id: String) -> Dictionary:
	var entry: Variant = get_category(category).get(entry_id, {})
	return entry if entry is Dictionary else {}


## Lit une valeur par chemin pointé, ex. get_value("defines", "time.default_speed", 1).
func get_value(category: String, path: String, default_value: Variant = null) -> Variant:
	var node: Variant = categories.get(category, null)
	for part: String in path.split("."):
		if not node is Dictionary or not (node as Dictionary).has(part):
			return default_value
		node = (node as Dictionary)[part]
	return node


## Résout une référence de schéma : "countries" ou "names#characters".
func resolve_ref(ref: String) -> Dictionary:
	var parts := ref.split(REF_SEPARATOR)
	var node: Variant = categories.get(parts[0], {})
	if parts.size() > 1:
		for key: String in parts[1].split("."):
			node = (node as Dictionary).get(key, {}) if node is Dictionary else {}
	return node if node is Dictionary else {}


static func category_for(relative_path: String) -> String:
	var directory := relative_path.get_base_dir()
	return relative_path.get_file().get_basename() if directory.is_empty() else directory


## Liste récursive et triée des fichiers JSON, en chemins relatifs à root.
static func list_json_files(root: String, relative_dir: String = "") -> PackedStringArray:
	var result := PackedStringArray()
	var absolute_dir := root if relative_dir.is_empty() else root.path_join(relative_dir)
	var files := DirAccess.get_files_at(absolute_dir)
	files.sort()
	for file_name: String in files:
		if file_name.get_extension().to_lower() == DATA_EXTENSION:
			result.append(file_name if relative_dir.is_empty() else relative_dir.path_join(file_name))
	var directories := DirAccess.get_directories_at(absolute_dir)
	directories.sort()
	for directory: String in directories:
		if directory.begins_with("."):
			continue
		var child := directory if relative_dir.is_empty() else relative_dir.path_join(directory)
		result.append_array(list_json_files(root, child))
	return result


## Renvoie {"data": valeur} ou {"error": message}.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "%s : fichier introuvable." % path}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"error": "%s:%d : JSON invalide (%s)." % [path, json.get_error_line(), json.get_error_message()]}
	return {"data": json.data}


func _load_file(root: String, relative_path: String) -> void:
	var path := root.path_join(relative_path)
	var parsed := read_json(path)
	if parsed.has("error"):
		errors.append(str(parsed["error"]))
		return
	if not parsed["data"] is Dictionary:
		errors.append("%s : la racine du fichier doit être un objet JSON." % path)
		return
	var category := category_for(relative_path)
	categories[category] = JsonMerge.merge(categories.get(category, {}), parsed["data"])
	loaded_files.append(path)

extends Node
## Découvre les DLC (res://dlc/) et les mods (user://mods/) et fournit l'ordre des dossiers
## de données : jeu de base, puis DLC, puis mods. Chaque source surcharge les précédentes.
##
## Structure d'un mod :
##   user://mods/<id>/mod.json    {"id", "name", "version", "load_order", "enabled"}
##   user://mods/<id>/data/...    mêmes chemins que res://data/
##
## Les mods utilisateur sont désactivés pour l'instant (USER_MODS_ENABLED) : seuls le jeu de base
## et les DLC sont chargés. Le mécanisme reste en place pour pouvoir les réactiver.

const SOURCE := "ModManager"
const USER_MODS_ENABLED := false
const BASE_DATA_ROOT := "res://data"
const DLC_DIR := "res://dlc"
const MODS_DIR := "user://mods"
const DLC_MANIFEST := "dlc.json"
const MOD_MANIFEST := "mod.json"
const DATA_SUBDIR := "data"

var dlcs: Array[Dictionary] = []
var mods: Array[Dictionary] = []


func _ready() -> void:
	if USER_MODS_ENABLED:
		DirAccess.make_dir_recursive_absolute(MODS_DIR)


## Relit les DLC et mods présents sur le disque.
func discover() -> void:
	dlcs = scan_packages(DLC_DIR, DLC_MANIFEST)
	mods = scan_packages(MODS_DIR, MOD_MANIFEST) if USER_MODS_ENABLED else ([] as Array[Dictionary])
	for package: Dictionary in dlcs:
		GameLog.info(SOURCE, "DLC actif : %s %s" % [package["name"], package["version"]])
	for package: Dictionary in mods:
		GameLog.info(SOURCE, "Mod actif : %s %s" % [package["name"], package["version"]])
	EventBus.mods_discovered.emit(mods.size())


func get_data_roots() -> PackedStringArray:
	var roots := PackedStringArray([BASE_DATA_ROOT])
	for package: Dictionary in dlcs:
		roots.append(str(package["data_path"]))
	for package: Dictionary in mods:
		roots.append(str(package["data_path"]))
	return roots


## Liste les paquets actifs d'un dossier, triés par load_order puis par id.
static func scan_packages(dir_path: String, manifest_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return result
	for sub: String in DirAccess.get_directories_at(dir_path):
		var package_path := dir_path.path_join(sub)
		var manifest_path := package_path.path_join(manifest_name)
		if not FileAccess.file_exists(manifest_path):
			continue
		var parsed := DataRepository.read_json(manifest_path)
		if parsed.has("error") or not parsed["data"] is Dictionary:
			GameLog.warn(SOURCE, "Manifeste illisible, paquet ignoré : %s" % manifest_path)
			continue
		var manifest: Dictionary = parsed["data"]
		if not bool(manifest.get("enabled", true)):
			continue
		result.append({
			"id": str(manifest.get("id", sub)),
			"name": str(manifest.get("name", sub)),
			"version": str(manifest.get("version", "")),
			"load_order": int(manifest.get("load_order", 0)),
			"path": package_path,
			"data_path": package_path.path_join(DATA_SUBDIR),
		})
	result.sort_custom(_is_loaded_before)
	return result


static func _is_loaded_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["load_order"]) != int(b["load_order"]):
		return int(a["load_order"]) < int(b["load_order"])
	return str(a["id"]) < str(b["id"])

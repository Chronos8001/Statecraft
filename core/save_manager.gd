extends Node
## Sauvegardes de partie (user://saves/). Pour l'instant : liste des sauvegardes uniquement,
## la sérialisation complète de GameState arrive avec le système de sauvegarde.

const SOURCE := "SaveManager"
const SAVE_DIR := "user://saves"
const SAVE_EXTENSION := "sav"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func list_saves() -> PackedStringArray:
	var saves := PackedStringArray()
	for file_name: String in DirAccess.get_files_at(SAVE_DIR):
		if file_name.get_extension() == SAVE_EXTENSION:
			saves.append(file_name.get_basename())
	saves.sort()
	return saves


func has_saves() -> bool:
	return not list_saves().is_empty()


func save_game(_save_name: String) -> Error:
	GameLog.warn(SOURCE, "La sauvegarde n'est pas encore disponible.")
	return ERR_UNAVAILABLE


func load_game(_save_name: String) -> Error:
	GameLog.warn(SOURCE, "Le chargement n'est pas encore disponible.")
	return ERR_UNAVAILABLE

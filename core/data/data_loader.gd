extends Node
## Charge toutes les données de jeu au démarrage (base + DLC + mods), les valide
## et les expose au reste du jeu.

const SOURCE := "DataLoader"
const DEFINES_CATEGORY := "defines"

var repository: DataRepository = DataRepository.new()


func _ready() -> void:
	reload()


func reload() -> void:
	ModManager.discover()
	var repo := DataRepository.new()
	repo.load_roots(ModManager.get_data_roots())
	repo.validate()
	repository = repo
	for message: String in repo.warnings:
		GameLog.warn(SOURCE, message)
	for message: String in repo.errors:
		GameLog.error(SOURCE, message)
	GameLog.info(SOURCE, "%d fichier(s) de données chargé(s), %d catégorie(s), %d erreur(s), %d avertissement(s)." % [
		repo.get_file_count(), repo.categories.size(), repo.errors.size(), repo.warnings.size()])
	EventBus.data_loaded.emit(repo.get_file_count(), repo.errors.size())


func get_file_count() -> int:
	return repository.get_file_count()


func get_error_count() -> int:
	return repository.errors.size()


func get_category(category: String) -> Dictionary:
	return repository.get_category(category)


func get_entry(category: String, entry_id: String) -> Dictionary:
	return repository.get_entry(category, entry_id)


## Constante d'équilibrage de data/defines.json, ex. get_define("time.default_speed", 1).
func get_define(path: String, default_value: Variant = null) -> Variant:
	return repository.get_value(DEFINES_CATEGORY, path, default_value)

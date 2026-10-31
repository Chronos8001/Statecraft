extends GutTest
## Chaque script du jeu se charge sans erreur (y compris l'interface, que les autres tests n'ouvrent pas).

const ROOTS := ["res://core", "res://map", "res://sim", "res://ui"]


func test_every_script_loads() -> void:
	var paths: Array[String] = []
	for root: String in ROOTS:
		_collect(root, paths)
	assert_gt(paths.size(), 50)
	for path: String in paths:
		var script: Script = load(path)
		assert_not_null(script, path)
		if script != null:
			assert_true(script.can_instantiate(), path)


func _collect(directory: String, paths: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			paths.append(directory.path_join(file))
	for child: String in DirAccess.get_directories_at(directory):
		_collect(directory.path_join(child), paths)

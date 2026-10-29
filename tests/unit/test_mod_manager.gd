extends GutTest

const MODS_ROOT := "res://tests/fixtures/mods"


func test_scans_only_enabled_packages_with_manifest() -> void:
	var packages := ModManager.scan_packages(MODS_ROOT, ModManager.MOD_MANIFEST)
	var ids: Array = packages.map(func(package: Dictionary) -> String: return package["id"])
	assert_eq(ids, ["mod_beta", "mod_alpha"], "trié par load_order, sans le mod désactivé ni le dossier sans manifeste")


func test_package_paths() -> void:
	var packages := ModManager.scan_packages(MODS_ROOT, ModManager.MOD_MANIFEST)
	var alpha: Dictionary = packages[1]
	assert_eq(alpha["data_path"], MODS_ROOT.path_join("mod_alpha/data"))
	assert_eq(alpha["version"], "1.0.0")


func test_missing_directory_gives_no_package() -> void:
	assert_eq(ModManager.scan_packages("res://tests/fixtures/nothing_here", ModManager.MOD_MANIFEST).size(), 0)


func test_base_data_root_comes_first() -> void:
	assert_eq(ModManager.get_data_roots()[0], ModManager.BASE_DATA_ROOT)


func test_user_mods_are_not_loaded_while_disabled() -> void:
	if ModManager.USER_MODS_ENABLED:
		pass_test("mods utilisateur activés")
		return
	ModManager.discover()
	assert_eq(ModManager.mods.size(), 0)
	for root: String in ModManager.get_data_roots():
		assert_false(root.begins_with(ModManager.MODS_DIR), root)

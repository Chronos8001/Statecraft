extends GutTest
## Éditeur d'événements : mods (création, aller-retour JSON et CSV), validation, essai dans une partie de test,
## modèles d'insertion pour chaque condition et chaque effet.

const TEST_DIR := "user://test_event_editor"


func before_each() -> void:
	_remove(TEST_DIR)


func after_all() -> void:
	_remove(TEST_DIR)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for folder: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(folder))
	DirAccess.remove_absolute(path)


func test_mod_round_trip() -> void:
	var path := EventModStore.create_mod(TEST_DIR, "my_mod", "Mon mod")
	assert_ne(path, "")
	assert_eq(EventModStore.create_mod(TEST_DIR, "my_mod", "Encore"), "", "identifiant déjà pris")
	assert_eq(EventModStore.create_mod(TEST_DIR, "Bad Id", "x"), "", "identifiant invalide")
	var mods := EventModStore.list_mods(TEST_DIR)
	assert_eq(mods.size(), 1)
	assert_eq(str(mods[0]["name"]), "Mon mod")
	var event := EventModStore.new_event("harvest_festival")
	event["trigger"] = {"stability": ">50"}
	var texts := {"EVENT_HARVEST_FESTIVAL_TITLE": {"en": "Harvest festival", "fr": "Fête des moissons"},
		"EVENT_HARVEST_FESTIVAL_DESC": {"en": "People celebrate, \"loudly\", in {country}.", "fr": "On fête, à {country}."},
		"EVENT_HARVEST_FESTIVAL_A": {"en": "Join in", "fr": "Se joindre à la fête"}}
	EventModStore.save(path, {"harvest_festival": event}, texts)
	var events := EventModStore.load_events(path)
	assert_eq((events["harvest_festival"] as Dictionary)["trigger"], {"stability": ">50"})
	var loaded := EventModStore.load_texts(path)
	assert_eq(str(loaded["EVENT_HARVEST_FESTIVAL_DESC"]["en"]), "People celebrate, \"loudly\", in {country}.",
		"virgules et guillemets conservés")
	assert_eq(str(loaded["EVENT_HARVEST_FESTIVAL_TITLE"]["fr"]), "Fête des moissons")


func test_validation() -> void:
	var schema: Dictionary = DataLoader.get_category("schemas").get("events", {})
	var known := DataLoader.get_category("events")
	var event := EventModStore.new_event("my_event")
	var texts := {"EVENT_MY_EVENT_TITLE": {"en": "T"}, "EVENT_MY_EVENT_DESC": {"en": "D"}, "EVENT_MY_EVENT_A": {"en": "A"}}
	assert_eq(EventModStore.validate("my_event", event, known, texts, schema, DataLoader.repository).size(), 0)
	assert_gt(EventModStore.validate("My Event", event, known, texts, schema, DataLoader.repository).size(), 0,
		"identifiant invalide")
	var broken := event.duplicate(true)
	(broken["options"][0] as Dictionary)["effects"] = {"add_happiness": 5, "trigger_event": "pandemic_spread"}
	var errors := EventModStore.validate("my_event", broken, known, texts, schema, DataLoader.repository)
	assert_eq(errors.size(), 1, "effet inconnu ; la chaîne vers un événement du jeu est acceptée : %s" % str(errors))
	broken["trigger"] = {"stability": "beaucoup"}
	assert_eq(EventModStore.validate("my_event", broken, known, texts, schema, DataLoader.repository).size(), 2)
	assert_gt(EventModStore.validate("my_event", event, known, {}, schema, DataLoader.repository).size(), 0,
		"textes manquants")


func test_tester_reports_changes() -> void:
	GameState.new_game(1, &"")
	var event := EventModStore.new_event("tax_cut")
	event["trigger"] = {"exists": true}
	event["immediate"] = {"add_stability": 5}
	(event["options"][0] as Dictionary)["effects"] = {"add_modifier": {"growth": 0.5, "months": 12}}
	var report := EventTester.run(GameState.sim, "tax_cut", event, "FRA", 0)
	assert_true(bool(report["trigger"]))
	assert_gt(float(report["chance"]), 0.0)
	assert_almost_eq(float(report["after"]["stability"]) - float(report["before"]["stability"]), 5.0, 0.01)
	assert_almost_eq(float(report["after"]["growth"]) - float(report["before"]["growth"]), 0.5, 0.01)
	assert_eq(str(EventTester.run(GameState.sim, "tax_cut", event, "XXX", 0)["error"]), "EDITOR_TEST_NO_COUNTRY")


func test_every_key_has_a_template() -> void:
	var templates := DataLoader.get_category("editor")
	var conditions: Dictionary = templates["conditions"]
	for key: String in ScriptConditions.NUMBERS + ScriptConditions.OTHERS + ScriptConditions.COMBINATORS \
			+ [ScriptConditions.OTHER_COUNTRY]:
		assert_true(conditions.has(key), "modèle de condition : %s" % key)
	var effects: Dictionary = templates["effects"]
	for key: String in ScriptEffects.KEYS:
		assert_true(effects.has(key), "modèle d'effet : %s" % key)
	for key: Variant in conditions.keys():
		assert_eq(ScriptConditions.validate({key: conditions[key]}, "modèle").size(), 0, "modèle valide : %s" % key)


## Parcours complet dans l'écran de l'éditeur (sans affichage) : nouveau mod, nouvel événement, champs remplis,
## choix ajouté, modèle inséré, enregistrement puis relecture.
func test_editor_screen_workflow() -> void:
	var editor := (load("res://ui/editor/event_editor.tscn") as PackedScene).instantiate() as EventEditor
	editor.mods_dir = TEST_DIR
	add_child_autofree(editor)
	await wait_process_frames(1)
	editor._new_mod()
	assert_false(editor._mod_path.is_empty())
	editor._new_event()
	assert_eq(editor._current_id, "new_event")
	editor._id_edit.text = "royal_wedding"
	editor._rename_current()
	assert_true(editor._mod_events.has("royal_wedding"))
	(editor._title_edits["fr"] as LineEdit).text = "Mariage royal"
	(editor._title_edits["en"] as LineEdit).text = "Royal wedding"
	(editor._desc_edits["fr"] as TextEdit).text = "Tout {country} célèbre."
	editor._trigger_edit.text = "{\"regime\": \"constitutional_monarchy\"}"
	editor._add_option()
	editor._focused_json = editor._immediate_edit
	editor._insert_template("add_stability", 5)
	editor._changed()
	editor._validate()
	var definition: Dictionary = editor._mod_events["royal_wedding"]
	assert_eq(definition["trigger"], {"regime": "constitutional_monarchy"})
	assert_eq(definition["immediate"], {"add_stability": 5.0})
	assert_eq((definition["options"] as Array).size(), 2)
	editor._save()
	var events := EventModStore.load_events(editor._mod_path)
	assert_true(events.has("royal_wedding"))
	var texts := EventModStore.load_texts(editor._mod_path)
	assert_eq(str(texts[str(definition["title_key"])]["fr"]), "Mariage royal")
	editor._duplicate_event()
	assert_true(editor._mod_events.has("royal_wedding_copy"))
	editor._delete_event()
	assert_false(editor._mod_events.has("royal_wedding_copy"))

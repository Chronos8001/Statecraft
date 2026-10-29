extends GutTest

const SAMPLE_CSV := "res://tests/fixtures/localization/sample.csv"


func test_parse_csv() -> void:
	var messages := Localization.parse_csv(SAMPLE_CSV)
	assert_eq(messages.keys().size(), 2)
	assert_eq(messages["fr"]["HELLO"], "Bonjour")
	assert_eq(messages["en"]["WITH_COMMA"], "One, two")
	assert_false((messages["fr"] as Dictionary).has("ONLY_EN"), "cellule vide ignorée")
	assert_false((messages["en"] as Dictionary).has("# commentaire ignoré"))


func test_pick_text_for() -> void:
	var value := {"en": "United Nations", "fr": "Organisation des Nations unies"}
	assert_eq(Localization.pick_text_for(value, "fr"), "Organisation des Nations unies")
	assert_eq(Localization.pick_text_for(value, "de"), "United Nations", "repli sur l'anglais")
	assert_eq(Localization.pick_text_for("Cap Avenir", "en"), "Cap Avenir")


func test_game_locales_are_loaded() -> void:
	assert_has(Localization.available_locales, "en")
	assert_has(Localization.available_locales, "fr")
	assert_eq(Localization.get_message_in("fr", "MENU_QUIT"), "Quitter")
	assert_eq(Localization.get_message_in("en", "MENU_QUIT"), "Quit")

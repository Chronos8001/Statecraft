extends Control
## Écran titre : Nouvelle partie / Charger / Options / Quitter.

const FOOTER_SEPARATOR := "   ·   "
const GAME_SCENE := "res://ui/game/game_screen.tscn"

var _locale_codes: PackedStringArray = PackedStringArray()

@onready var _new_game_button: Button = %NewGameButton
@onready var _load_button: Button = %LoadButton
@onready var _options_button: Button = %OptionsButton
@onready var _quit_button: Button = %QuitButton
@onready var _footer: Label = %Footer
@onready var _options_panel: PanelContainer = %OptionsPanel
@onready var _language_option: OptionButton = %LanguageOption
@onready var _close_button: Button = %CloseButton
@onready var _info_dialog: AcceptDialog = %InfoDialog


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_close_button.pressed.connect(_close_options)
	_language_option.item_selected.connect(_on_language_selected)
	EventBus.locale_changed.connect(_on_locale_changed)

	_load_button.disabled = not SaveManager.has_saves()
	if _load_button.disabled:
		_load_button.tooltip_text = "MENU_LOAD_NONE"
	_fill_languages()
	_update_footer()
	_new_game_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _options_panel.visible and event.is_action_pressed("ui_cancel"):
		_close_options()
		get_viewport().set_input_as_handled()


func _fill_languages() -> void:
	_language_option.clear()
	_locale_codes = Localization.available_locales
	var current := Localization.get_locale()
	for index: int in _locale_codes.size():
		var code := _locale_codes[index]
		_language_option.add_item(Localization.get_message_in(code, "LANGUAGE_NATIVE_NAME"), index)
		if current.begins_with(code):
			_language_option.select(index)


func _update_footer() -> void:
	var parts := PackedStringArray([
		tr("FOOTER_VERSION") % str(ProjectSettings.get_setting("application/config/version", "")),
		tr("FOOTER_DATA_FILES") % DataLoader.get_file_count(),
	])
	if DataLoader.get_error_count() > 0:
		parts.append(tr("FOOTER_DATA_ERRORS") % DataLoader.get_error_count())
	_footer.text = FOOTER_SEPARATOR.join(parts)


func _close_options() -> void:
	_options_panel.visible = false
	_options_button.grab_focus()


func _on_new_game_pressed() -> void:
	GameState.new_game(randi())
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_load_pressed() -> void:
	SaveManager.load_game("")
	_info_dialog.dialog_text = "INFO_LOAD_UNAVAILABLE"
	_info_dialog.popup_centered()


func _on_options_pressed() -> void:
	_options_panel.visible = true
	_language_option.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_language_selected(index: int) -> void:
	Localization.set_locale(_locale_codes[index])


func _on_locale_changed(_locale: String) -> void:
	_update_footer()

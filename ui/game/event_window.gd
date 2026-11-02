class_name EventWindow
extends AcceptDialog
## Fenêtre d'un événement du joueur : titre, texte, un bouton par choix (effets en infobulle). Elle ne se
## ferme qu'en choisissant ; le jeu reste en pause tant qu'elle est ouverte.

signal command_requested(command: Command)
signal answered

const WIDTH := 520

var _event_id: String = ""
var _answered: bool = false


func setup(entry: Dictionary) -> void:
	var state := GameState.sim
	_event_id = str(entry.get("id", ""))
	var definition: Dictionary = state.event_definitions.get(_event_id, {})
	var country := str(entry.get("country", ""))
	title = tr(str(definition.get("title_key", "")))
	get_ok_button().visible = false
	dialog_close_on_escape = false
	exclusive = true
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(WIDTH, 0)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.text = fill(tr(str(definition.get("desc_key", ""))), state, country, entry)
	box.add_child(text)
	var options: Array = definition.get("options", [])
	var locale := Localization.get_locale()
	for index: int in options.size():
		var option: Dictionary = options[index]
		var button := Button.new()
		button.text = tr(str(option.get("name_key", "")))
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var lines := ScriptEffects.describe(option.get("effects", {}), locale)
		button.tooltip_text = "\n".join(lines) if not lines.is_empty() else tr("EFFECT_NONE")
		var choice := index
		button.pressed.connect(func() -> void: _choose(choice))
		box.add_child(button)
	close_requested.connect(func() -> void: pass)
	visibility_changed.connect(_on_visibility_changed)


## Remplace {country}, {from} et {province} dans un texte d'événement.
static func fill(text: String, state: SimState, country: String, entry: Dictionary) -> String:
	var province := str(entry.get("province", ""))
	var province_name: String = TranslationServer.translate(str(DataLoader.get_entry("provinces", province).get("name_key",
		""))) if not province.is_empty() else ""
	return text.replace("{country}", MilitaryUI.side_name(state, country)) \
		.replace("{from}", MilitaryUI.side_name(state, str(entry.get("from", "")))).replace("{province}", province_name)


func _choose(index: int) -> void:
	if _answered:
		return
	_answered = true
	command_requested.emit(ChooseEventOptionCommand.new(GameState.sim.player_tag, _event_id, index))
	hide()


## Fermée sans choix (Échap, croix) : elle se rouvre ; après un choix, elle disparaît.
func _on_visibility_changed() -> void:
	if visible:
		return
	if not _answered:
		popup_centered.call_deferred(Vector2i(WIDTH, 0))
		return
	answered.emit()
	queue_free()

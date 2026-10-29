class_name MapModeBar
extends PanelContainer
## Barre de choix du mode de carte (un bouton par mode).

signal mode_selected(mode_id: String)

var _buttons: Dictionary = {}
var _group: ButtonGroup = ButtonGroup.new()

@onready var _row: HBoxContainer = %ModeRow


func set_modes(modes: Array[MapMode]) -> void:
	for child: Node in _row.get_children():
		child.queue_free()
	_buttons.clear()
	for mode: MapMode in modes:
		var button := Button.new()
		button.text = mode.name_key
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: mode_selected.emit(mode.id))
		_row.add_child(button)
		_buttons[mode.id] = button


func set_current(mode_id: String) -> void:
	if _buttons.has(mode_id):
		(_buttons[mode_id] as Button).set_pressed_no_signal(true)

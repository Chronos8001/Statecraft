class_name BuildingsSection
extends VBoxContainer
## Bâtiments d'une province (fiche de province) : bâtiments présents, chantiers en cours et, si la
## province appartient au joueur, construction d'un nouveau bâtiment.

const LABEL_COLOR := Color(0.62, 0.68, 0.76)
const TITLE_COLOR := Color(0.92, 0.95, 0.98)
const REFUSAL_COLOR := Color(0.95, 0.6, 0.45)

var _province_id: String = ""
var _building_ids: Array[String] = []
var _option: OptionButton
var _cost_label: Label
var _build_button: Button
var _refusal_label: Label


func _ready() -> void:
	EventBus.command_executed.connect(func(_command: Command) -> void: refresh())
	EventBus.month_passed.connect(func(_date: GameDate) -> void: refresh())


func show_province(province_id: String) -> void:
	_province_id = province_id
	refresh()


func refresh() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_option = null
	var state := GameState.sim
	if _province_id.is_empty() or state.energy_definitions.is_empty():
		visible = false
		return
	visible = true
	var definitions: Dictionary = state.energy_definitions.get("buildings", {})
	add_child(_label("BUILDINGS_TITLE", TITLE_COLOR))
	var present: Dictionary = state.buildings.get(_province_id, {})
	if present.is_empty():
		add_child(_label(tr("BUILDINGS_NONE"), LABEL_COLOR, false))
	for building_id: String in definitions.keys():
		if present.has(building_id):
			add_child(_label(tr("BUILDINGS_COUNT_VALUE") % [tr(str(definitions[building_id]["name_key"])),
				int(present[building_id])], Color.WHITE, false))
	for project: Dictionary in state.projects:
		if str(project["province"]) == _province_id:
			add_child(_label(tr("BUILDINGS_PROJECT_VALUE") % [tr(str(definitions[project["building"]]["name_key"])),
				int(project["months_left"])], LABEL_COLOR, false))
	var province: Dictionary = (state.energy_definitions.get("provinces", {}) as Dictionary).get(_province_id, {})
	if str(province.get("owner", "")) == str(state.player_tag) and not str(state.player_tag).is_empty():
		_add_build_controls(definitions)


func _add_build_controls(definitions: Dictionary) -> void:
	add_child(_label("BUILDINGS_BUILD", TITLE_COLOR))
	var row := HBoxContainer.new()
	_option = OptionButton.new()
	_option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_option.focus_mode = Control.FOCUS_NONE
	_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_ids.clear()
	for building_id: String in definitions.keys():
		_option.add_item(tr(str(definitions[building_id]["name_key"])))
		_building_ids.append(building_id)
	_option.item_selected.connect(func(_index: int) -> void: _update_choice())
	row.add_child(_option)
	_build_button = Button.new()
	_build_button.text = "BUILDINGS_BUILD_BUTTON"
	_build_button.focus_mode = Control.FOCUS_NONE
	_build_button.pressed.connect(_on_build_pressed)
	row.add_child(_build_button)
	add_child(row)
	_cost_label = _label("", LABEL_COLOR, false)
	add_child(_cost_label)
	_refusal_label = _label("", REFUSAL_COLOR, false)
	add_child(_refusal_label)
	_update_choice()


func _selected() -> String:
	var index := _option.selected if _option != null else -1
	return _building_ids[index] if index >= 0 and index < _building_ids.size() else ""


func _update_choice() -> void:
	var building_id := _selected()
	if building_id.is_empty():
		return
	var state := GameState.sim
	var definition: Dictionary = state.energy_definitions["buildings"][building_id]
	var locale := Localization.get_locale()
	var text := tr("BUILDINGS_COST_VALUE") % [NumberFormat.decimal(float(definition["cost_billion"]), 2, locale),
		int(definition["build_months"])]
	if definition.has("capacity_gw"):
		text += " · " + tr("BUILDINGS_CAPACITY_VALUE") % NumberFormat.decimal(float(definition["capacity_gw"]), 1, locale)
	if definition.has("output_billion"):
		text += " · " + tr("BUILDINGS_OUTPUT_VALUE") % NumberFormat.decimal(float(definition["output_billion"]), 2, locale)
	_cost_label.text = text
	var reason := BuildCommand.new(state.player_tag, building_id, _province_id).refusal_reason(state)
	_refusal_label.text = tr(reason) if not reason.is_empty() else ""
	_build_button.disabled = not reason.is_empty()


func _on_build_pressed() -> void:
	var command := BuildCommand.new(GameState.sim.player_tag, _selected(), _province_id)
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


func _label(text: String, color: Color, translate: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if not translate:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

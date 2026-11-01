class_name WarSection
extends VBoxContainer
## Section « Guerre » du panneau Diplomatie : guerres en cours avec ce pays ou qui le concernent (rejoindre
## un camp), déclaration de guerre avec le choix du but, sa justification, ses coûts et les alliés appelés.

## Une commande à soumettre (le panneau la transmet à la simulation).
signal command_requested(command: Command)

const TITLE_COLOR := Color(0.92, 0.95, 0.98)
const BAD_COLOR := Color(0.95, 0.5, 0.45)

var _tag: String = ""
var _goal_ids: Array[String] = []
var _status_box: VBoxContainer
var _goal_option: OptionButton
var _declare_button: Button
var _preview_label: Label
var _cyber_row: HBoxContainer


func _ready() -> void:
	var title := Label.new()
	title.text = "DIPLOMACY_WAR_TITLE"
	title.add_theme_color_override("font_color", TITLE_COLOR)
	add_child(title)
	_status_box = VBoxContainer.new()
	add_child(_status_box)
	var row := HBoxContainer.new()
	_goal_option = OptionButton.new()
	_goal_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal_option.focus_mode = Control.FOCUS_NONE
	_goal_option.item_selected.connect(func(_index: int) -> void: _update_declaration())
	row.add_child(_goal_option)
	_declare_button = Button.new()
	_declare_button.text = "DIPLOMACY_DECLARE_WAR"
	_declare_button.focus_mode = Control.FOCUS_NONE
	_declare_button.pressed.connect(func() -> void:
		var goal := _selected_goal()
		if not goal.is_empty():
			command_requested.emit(DeclareWarCommand.new(GameState.sim.player_tag, _tag, goal)))
	row.add_child(_declare_button)
	add_child(row)
	_preview_label = Label.new()
	_preview_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.add_theme_color_override("font_color", InfoPanel.LABEL_COLOR)
	add_child(_preview_label)
	_cyber_row = HBoxContainer.new()
	add_child(_cyber_row)


func show_country(tag: String) -> void:
	_tag = tag
	refresh()


func refresh() -> void:
	var state := GameState.sim
	var player := str(state.player_tag)
	for child: Node in _status_box.get_children():
		_status_box.remove_child(child)
		child.queue_free()
	visible = not player.is_empty() and player != _tag and not WarSystem.settings_of(state).is_empty()
	if not visible:
		return
	var at_war := WarSystem.war_between(state, player, _tag)
	if at_war != null:
		_add_line(tr("DIPLOMACY_AT_WAR") % MilitaryUI.war_name(state, at_war), BAD_COLOR)
	for war: War in WarSystem.wars_of(state, _tag):
		if war == at_war or war.civil:
			continue
		var row := HBoxContainer.new()
		var label := Label.new()
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = MilitaryUI.war_name(state, war)
		row.add_child(label)
		var side := war.side_of(_tag)
		var command := JoinWarCommand.new(state.player_tag, war.id, side)
		var refusal := command.refusal_reason(state)
		if refusal != "WAR_ALREADY":
			var button := Button.new()
			button.text = "DIPLOMACY_JOIN_WAR"
			button.focus_mode = Control.FOCUS_NONE
			button.disabled = not refusal.is_empty()
			button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("DIPLOMACY_JOIN_WAR_TOOLTIP")
			button.pressed.connect(func() -> void: command_requested.emit(JoinWarCommand.new(state.player_tag, war.id, side)))
			row.add_child(button)
		_status_box.add_child(row)
	_fill_cyber(state)
	var previous := _selected_goal()
	_goal_ids.clear()
	_goal_option.clear()
	for goal: String in state.war_goal_definitions.keys():
		_goal_ids.append(goal)
		_goal_option.add_item(tr(str((state.war_goal_definitions[goal] as Dictionary)["name_key"])))
	var index := _goal_ids.find(previous)
	if not _goal_ids.is_empty():
		_goal_option.select(index if index >= 0 else 0)
	_update_declaration()


## Cyberattaques (possibles en paix) : économie, réseau électrique, armée ; chance et risque d'être découvert.
func _fill_cyber(state: SimState) -> void:
	for child: Node in _cyber_row.get_children():
		_cyber_row.remove_child(child)
		child.queue_free()
	if MilitaryActions.settings_of(state).is_empty():
		return
	var player := str(state.player_tag)
	var label := Label.new()
	label.text = "ACTION_CYBER_TITLE"
	label.add_theme_color_override("font_color", InfoPanel.LABEL_COLOR)
	_cyber_row.add_child(label)
	for kind: String in [MilitaryActions.ECONOMY, MilitaryActions.GRID, MilitaryActions.ARMY]:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.text = tr("ACTION_CYBERATTACK_%s" % kind.to_upper()) % roundi(MilitaryActions.chance(state, player,
			MilitaryActions.CYBER, kind, _tag) * 100.0)
		var refusal := MilitaryActions.refusal(state, player, MilitaryActions.CYBER, kind, _tag)
		button.disabled = not refusal.is_empty()
		button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("ACTION_CYBERATTACK_TOOLTIP") % roundi(
			MilitaryActions.discovery_chance(state, _tag, true) * 100.0)
		button.pressed.connect(func() -> void:
			command_requested.emit(MilitaryActionCommand.new(state.player_tag, MilitaryActions.CYBER, kind, _tag)))
		_cyber_row.add_child(button)


func _selected_goal() -> String:
	return _goal_ids[_goal_option.selected] if _goal_option.selected >= 0 and _goal_option.selected < _goal_ids.size() \
		else ""


## Justification du but choisi, coûts pour nous et alliés de la cible qui seront appelés.
func _update_declaration() -> void:
	var state := GameState.sim
	var player := str(state.player_tag)
	var goal := _selected_goal()
	var refusal := WarSystem.declare_refusal(state, player, _tag, goal)
	_declare_button.disabled = not refusal.is_empty()
	_declare_button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("DIPLOMACY_DECLARE_WAR_TOOLTIP")
	if goal.is_empty() or refusal == "WAR_ALREADY":
		_preview_label.text = ""
		return
	var lines: PackedStringArray = []
	var definition: Dictionary = state.war_goal_definitions[goal]
	var tension_threshold := float(definition.get("min_tension", 0.0))
	lines.append(tr("WAR_GOAL_%s_DESC" % goal.to_upper()))
	if tension_threshold > 0.0:
		lines.append(tr("WAR_REQUIRES_TENSION") % roundi(tension_threshold))
	var provinces := WarSystem.goal_provinces(state, player, _tag, goal)
	if not provinces.is_empty():
		var names: PackedStringArray = []
		for province_id: String in provinces:
			names.append(tr(str(DataLoader.get_entry("provinces", province_id).get("name_key", province_id))))
		lines.append(tr("WAR_TARGET_PROVINCES") % ", ".join(names))
	var costs := WarSystem.declaration_costs(state, player, goal)
	lines.append(tr("WAR_COSTS") % [roundi(float(costs["legitimacy"])), roundi(float(costs["stability"])),
		roundi(float(costs["world_opinion"]))])
	var called := WarSystem.defenders_called(state, player, _tag)
	if not called.is_empty():
		var allies: PackedStringArray = []
		for tag: String in called:
			allies.append(MilitaryUI.side_name(state, tag))
		lines.append(tr("WAR_ALLIES_CALLED") % ", ".join(allies))
	_preview_label.text = "\n".join(lines)


func _add_line(text: String, color: Color) -> void:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.add_theme_color_override("font_color", color)
	_status_box.add_child(label)

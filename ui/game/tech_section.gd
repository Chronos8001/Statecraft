class_name TechSection
extends VBoxContainer
## Section « Technologie » du panneau Diplomatie : projet de recherche conjoint avec ce pays, espionnage
## industriel d'une technologie qu'il connaît (chance, risque d'être démasqué).

signal command_requested(command: Command)

const TITLE_COLOR := Color(0.92, 0.95, 0.98)

var _tag: String = ""
var _joint_ids: Array[String] = []
var _steal_ids: Array[String] = []
var _joint_option: OptionButton
var _joint_button: Button
var _steal_option: OptionButton
var _steal_button: Button


func _ready() -> void:
	var title := Label.new()
	title.text = "DIPLOMACY_TECH_TITLE"
	title.add_theme_color_override("font_color", TITLE_COLOR)
	add_child(title)
	var joint_row := HBoxContainer.new()
	_joint_option = _option(joint_row)
	_joint_button = _button(joint_row, "DIPLOMACY_JOINT_PROJECT")
	_joint_button.pressed.connect(func() -> void:
		var tech := _selected(_joint_option, _joint_ids)
		if not tech.is_empty():
			command_requested.emit(JointProjectCommand.new(GameState.sim.player_tag, _tag, tech)))
	add_child(joint_row)
	var steal_row := HBoxContainer.new()
	_steal_option = _option(steal_row)
	_steal_button = _button(steal_row, "DIPLOMACY_STEAL_TECH")
	_steal_button.pressed.connect(func() -> void:
		var tech := _selected(_steal_option, _steal_ids)
		if not tech.is_empty():
			command_requested.emit(StealTechnologyCommand.new(GameState.sim.player_tag, _tag, tech)))
	add_child(steal_row)
	_joint_option.item_selected.connect(func(_index: int) -> void: _update())
	_steal_option.item_selected.connect(func(_index: int) -> void: _update())


func _option(row: HBoxContainer) -> OptionButton:
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.focus_mode = Control.FOCUS_NONE
	option.fit_to_longest_item = false
	row.add_child(option)
	return option


func _button(row: HBoxContainer, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	row.add_child(button)
	return button


func show_country(tag: String) -> void:
	_tag = tag
	var state := GameState.sim
	var player := state.get_country(str(state.player_tag))
	var other := state.get_country(tag)
	visible = player != null and other != null and player != other and player.research != null and other.research != null
	if not visible:
		return
	_joint_ids.clear()
	_steal_ids.clear()
	_joint_option.clear()
	_steal_option.clear()
	for tech_id: String in state.technology_definitions.keys():
		var name := tr(str((state.technology_definitions[tech_id] as Dictionary).get("name_key", tech_id)))
		if ResearchSystem.availability(state, player, tech_id).is_empty():
			if other.research.is_known(tech_id):
				_steal_ids.append(tech_id)
				_steal_option.add_item(name)
			elif ResearchSystem.availability(state, other, tech_id).is_empty():
				_joint_ids.append(tech_id)
				_joint_option.add_item(name)
	_update()


func _selected(option: OptionButton, ids: Array[String]) -> String:
	return ids[option.selected] if option.selected >= 0 and option.selected < ids.size() else ""


func _update() -> void:
	var state := GameState.sim
	var player := str(state.player_tag)
	var joint := _selected(_joint_option, _joint_ids)
	var refusal := ResearchCooperation.joint_refusal(state, player, _tag, joint) if not joint.is_empty() else "RESEARCH_NOTHING"
	_joint_button.disabled = not refusal.is_empty()
	var likely := ResearchCooperation.joint_score(state, _tag, player) > 0.0
	_joint_button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr(
		"DIPLOMACY_JOINT_LIKELY_YES" if likely else "DIPLOMACY_JOINT_LIKELY_NO")
	var steal := _selected(_steal_option, _steal_ids)
	var steal_refusal := ResearchCooperation.espionage_refusal(state, player, _tag, steal) if not steal.is_empty() \
		else "RESEARCH_NOTHING"
	_steal_button.disabled = not steal_refusal.is_empty()
	_steal_button.tooltip_text = tr(steal_refusal) if not steal_refusal.is_empty() else tr("DIPLOMACY_STEAL_TOOLTIP") % [
		roundi(ResearchCooperation.espionage_chance(state, player, _tag) * 100.0),
		roundi(ResearchCooperation.discovery_chance(state, _tag) * 100.0)]

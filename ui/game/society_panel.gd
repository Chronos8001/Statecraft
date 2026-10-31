class_name SocietyPanel
extends InfoPanel
## Panneau Société du pays joué : indicateurs nationaux (stabilité, soutien populaire, légitimité,
## corruption) et groupes sociaux (part de la population, poids politique, satisfaction).

const GROUP_COLUMNS := 4
const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const POSITIVE_COLOR := Color(0.55, 0.85, 0.55)
const NEGATIVE_COLOR := Color(0.95, 0.5, 0.45)
const NEUTRAL_COLOR := Color(0.85, 0.88, 0.92)
## Écart à la valeur de départ en dessous duquel la couleur reste neutre.
const CHANGE_THRESHOLD := 1.0
const GROUP_HEADERS := ["SOCIETY_GROUP", "SOCIETY_POPULATION", "SOCIETY_INFLUENCE", "SOCIETY_SATISFACTION"]

@onready var _indicators_grid: GridContainer = %IndicatorsGrid
@onready var _groups_grid: GridContainer = %GroupsGrid
@onready var _crises_box: VBoxContainer = %CrisesBox
@onready var _media_grid: GridContainer = %MediaGrid
@onready var _propaganda_option: OptionButton = %PropagandaOption
@onready var _propaganda_button: Button = %PropagandaButton
@onready var _target_option: OptionButton = %TargetOption
@onready var _disinformation_button: Button = %DisinformationButton
## Cibles de désinformation dans l'ordre de la liste ("" : l'opposition du pays).
var _targets: Array[String] = []
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_propaganda_button.pressed.connect(func() -> void:
		_submit(SetPropagandaCommand.new(GameState.sim.player_tag, maxi(_propaganda_option.selected, 0))))
	_disinformation_button.pressed.connect(_on_disinformation_pressed)
	_target_option.item_selected.connect(func(_index: int) -> void: _update_disinformation())
	_groups_grid.columns = GROUP_COLUMNS
	EventBus.locale_changed.connect(func(_locale: String) -> void: refresh())
	EventBus.month_passed.connect(func(_date: GameDate) -> void: refresh())
	EventBus.command_executed.connect(func(_command: Command) -> void: refresh())
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		visible = true
		refresh()


func refresh() -> void:
	if not visible:
		return
	_clear_rows(_indicators_grid)
	_clear_rows(_groups_grid)
	var country := GameState.sim.get_country(str(GameState.sim.player_tag))
	if country == null or country.society.group_shares.is_empty():
		return
	_fill_indicators(country.society)
	_fill_crises(country)
	_fill_media(country)
	_fill_groups(country.society)


func _fill_indicators(society: SocietyState) -> void:
	_add_score("SOCIETY_STABILITY", society.stability, society.start_stability, false)
	_add_score("SOCIETY_SUPPORT", society.support, society.start_support, false)
	_add_score("SOCIETY_LEGITIMACY", society.legitimacy, society.start_legitimacy, false)
	_add_score("SOCIETY_CORRUPTION", society.corruption, society.corruption, true)
	_add_row(_indicators_grid, "SOCIETY_DEMOCRACY", tr("SOCIETY_DEMOCRACY_VALUE")
		% NumberFormat.decimal(society.democracy_index, 1, Localization.get_locale()))


## « 54 / 100 (départ 56) », en couleur selon l'écart au départ. inverted : une hausse est mauvaise.
func _add_score(label_key: String, value: float, start: float, inverted: bool) -> void:
	var text := tr("SOCIETY_SCORE_VALUE") % roundi(value)
	if roundi(value) != roundi(start):
		text = tr("SOCIETY_SCORE_START_VALUE") % [roundi(value), roundi(start)]
	_add_row(_indicators_grid, label_key, text)
	var value_label := _indicators_grid.get_child(_indicators_grid.get_child_count() - 1) as Label
	value_label.add_theme_color_override("font_color", _change_color(value - start, inverted))


## Crises en cours, avec les réponses possibles quand le joueur n'a pas encore réagi.
func _fill_crises(country: CountryState) -> void:
	for child: Node in _crises_box.get_children():
		_crises_box.remove_child(child)
		child.queue_free()
	var definitions: Dictionary = GameState.sim.politics_definitions.get("crises", {})
	var groups := DataLoader.get_category("social_groups")
	if country.crises.is_empty():
		var calm := Label.new()
		calm.text = "CRISES_NONE"
		calm.add_theme_color_override("font_color", LABEL_COLOR)
		_crises_box.add_child(calm)
		return
	for crisis: Dictionary in country.crises:
		var definition: Dictionary = definitions.get(crisis["type"], {})
		var row := HBoxContainer.new()
		var label := Label.new()
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var text := tr(str(definition.get("name_key", crisis["type"])))
		var group_id := str(crisis.get("group", ""))
		if not group_id.is_empty():
			text += " (%s)" % tr(str((groups.get(group_id, {}) as Dictionary).get("name_key", group_id)))
		label.text = text
		label.add_theme_color_override("font_color", NEGATIVE_COLOR)
		row.add_child(label)
		if bool(definition.get("responses", false)) and not crisis.has("response"):
			for response: String in CrisisResponseCommand.RESPONSES:
				var button := Button.new()
				button.text = "CRISES_%s" % response.to_upper()
				button.tooltip_text = "CRISES_%s_TOOLTIP" % response.to_upper()
				button.focus_mode = Control.FOCUS_NONE
				var crisis_id := int(crisis["id"])
				button.pressed.connect(func() -> void:
					if GameState.submit_command(CrisisResponseCommand.new(GameState.sim.player_tag, crisis_id, response)) \
							and GameClock.is_paused:
						GameState.process_commands())
				row.add_child(button)
		elif crisis.has("response"):
			var done := Label.new()
			done.text = "CRISES_%s_DONE" % str(crisis["response"]).to_upper()
			done.add_theme_color_override("font_color", LABEL_COLOR)
			row.add_child(done)
		_crises_box.add_child(row)


## Presse et réseaux (lois), propagande et désinformation.
func _fill_media(country: CountryState) -> void:
	_clear_rows(_media_grid)
	var state := GameState.sim
	var laws: Dictionary = state.politics_definitions.get("laws", {})
	var settings := MediaSystem.settings_of(state)
	for law_key: String in ["press_law", "networks_law"]:
		var law_id := str(settings.get(law_key, ""))
		if laws.has(law_id):
			var option := LawModel.option_of(laws[law_id], str(country.laws.get(law_id, "")))
			_add_row(_media_grid, str(laws[law_id]["name_key"]), tr(str(option.get("name_key", ""))))
	var propaganda: Dictionary = settings.get("propaganda", {})
	var costs: Array = propaganda.get("cost_share", [])
	_propaganda_option.clear()
	for level: int in SetPropagandaCommand.MAX_LEVEL + 1:
		var cost := float(costs[level]) if level < costs.size() else 0.0
		_propaganda_option.add_item(tr("MEDIA_PROPAGANDA_%d" % level) + (" (%s)" % (tr("MEDIA_COST_VALUE") % NumberFormat.decimal(
			cost, 2, Localization.get_locale())) if cost > 0.0 else ""))
	_propaganda_option.select(country.propaganda_level)
	var previous := _targets[_target_option.selected] if _target_option.selected >= 0 \
		and _target_option.selected < _targets.size() else "@"
	_targets.clear()
	_target_option.clear()
	_targets.append("")
	_target_option.add_item(tr("MEDIA_TARGET_OPPOSITION"))
	var names: Array = []
	for tag: String in state.countries.keys():
		if tag != country.tag:
			names.append([tr(str(DataLoader.get_entry("countries", tag).get("name_key", tag))), tag])
	names.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]).naturalnocasecmp_to(str(b[0])) < 0)
	for entry: Array in names:
		_targets.append(str(entry[1]))
		_target_option.add_item(str(entry[0]))
	var index := _targets.find(previous)
	_target_option.select(index if index >= 0 else 0)
	_update_disinformation()


func _target_command() -> DisinformationCommand:
	var target := _targets[_target_option.selected] if _target_option.selected >= 0 \
		and _target_option.selected < _targets.size() else ""
	return DisinformationCommand.new(GameState.sim.player_tag, target,
		MediaSystem.KIND_SMEAR if target.is_empty() else MediaSystem.KIND_DESTABILIZE)


func _update_disinformation() -> void:
	var refusal := _target_command().refusal_reason(GameState.sim)
	_disinformation_button.disabled = not refusal.is_empty()
	_disinformation_button.tooltip_text = tr(refusal) if not refusal.is_empty() else ""


func _on_disinformation_pressed() -> void:
	_submit(_target_command())


func _submit(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


func _fill_groups(society: SocietyState) -> void:
	for key: String in GROUP_HEADERS:
		var header := Label.new()
		header.text = key
		header.add_theme_color_override("font_color", HEADER_COLOR)
		_groups_grid.add_child(header)
	var groups := DataLoader.get_category("social_groups")
	var locale := Localization.get_locale()
	# Groupes du plus influent au moins influent.
	var ids: Array = society.group_shares.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float(society.influence.get(a, 0.0)) > float(society.influence.get(b, 0.0)))
	for group_id: Variant in ids:
		var name_label := Label.new()
		name_label.text = str((groups.get(group_id, {}) as Dictionary).get("name_key", group_id))
		name_label.add_theme_color_override("font_color", LABEL_COLOR)
		_groups_grid.add_child(name_label)
		_groups_grid.add_child(_value(tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(
			float(society.group_shares[group_id]) * SocietyModel.PERCENT, 1, locale)))
		_groups_grid.add_child(_value(tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(
			float(society.influence.get(group_id, 0.0)) * SocietyModel.PERCENT, 1, locale)))
		var satisfaction := float(society.satisfaction.get(group_id, 0.0))
		var start := float(society.start_satisfaction.get(group_id, satisfaction))
		var satisfaction_label := _value(tr("SOCIETY_SCORE_VALUE") % roundi(satisfaction))
		satisfaction_label.add_theme_color_override("font_color", _change_color(satisfaction - start, false))
		satisfaction_label.tooltip_text = tr("SOCIETY_SATISFACTION_TOOLTIP") % roundi(start)
		satisfaction_label.mouse_filter = Control.MOUSE_FILTER_STOP
		_groups_grid.add_child(satisfaction_label)


func _change_color(change: float, inverted: bool) -> Color:
	if absf(change) < CHANGE_THRESHOLD:
		return NEUTRAL_COLOR
	return POSITIVE_COLOR if (change > 0.0) != inverted else NEGATIVE_COLOR


func _value(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

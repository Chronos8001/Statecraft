class_name MilitaryPanel
extends InfoPanel
## Panneau Armée du pays joué : puissance, effectifs, budget de défense, guerres en cours (paix blanche, appels
## aux armes), branches (symboles OTAN), groupes d'armées, capacités spéciales, arsenal nucléaire, priorités
## d'équipement et mobilisation.

## « Voir » sur un groupe d'armées : la carte se centre dessus.
signal group_focus_requested(group_id: int)
## « Voir » sur un front : la carte se centre sur une de ses provinces.
signal province_focus_requested(province_id: String)

const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const BRANCH_HEADERS := ["", "MILITARY_BRANCH", "MILITARY_PERSONNEL", "MILITARY_LEVEL", "MILITARY_TRAINING",
	"MILITARY_MORALE", "MILITARY_PRIORITY"]
const SPECIAL_KEYS := ["special_forces", "missiles", "cyber"]
const MOBILIZATION_KEYS := ["MILITARY_MOBILIZATION_0", "MILITARY_MOBILIZATION_1", "MILITARY_MOBILIZATION_2"]
const LEVEL_DECIMALS := 2
const PERCENT := 100.0
const PRIORITY_STEP := 1.0
const GROUP_HEADERS := ["", "MILITARY_GROUP", "MILITARY_LOCATION", "MILITARY_PERSONNEL", "MILITARY_STATUS", ""]
const THOUSAND := 1000.0
## Échelle d'affichage de la puissance d'un front (comme la puissance militaire).
const POWER_SCALE := 0.00001

var military_ui: MilitaryUI = MilitaryUI.new()
var _priority_spins: Dictionary = {}
var _wars_box: VBoxContainer

@onready var _summary_grid: GridContainer = %SummaryGrid
@onready var _branches_grid: GridContainer = %BranchesGrid
@onready var _special_grid: GridContainer = %SpecialGrid
@onready var _groups_grid: GridContainer = %GroupsGrid
@onready var _mobilization_option: OptionButton = %MobilizationOption
@onready var _mobilization_button: Button = %MobilizationButton
@onready var _priorities_button: Button = %PrioritiesButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_wars_box = VBoxContainer.new()
	_summary_grid.get_parent().add_child(_wars_box)
	_summary_grid.get_parent().move_child(_wars_box, _summary_grid.get_index() + 1)
	_branches_grid.columns = BRANCH_HEADERS.size()
	_mobilization_option.item_selected.connect(func(_index: int) -> void: _update_buttons())
	_mobilization_button.pressed.connect(func() -> void:
		_submit(MobilizeCommand.new(GameState.sim.player_tag, _mobilization_option.selected)))
	_priorities_button.pressed.connect(func() -> void: _submit(_priorities_command()))
	EventBus.locale_changed.connect(func(_locale: String) -> void: refresh())
	EventBus.month_passed.connect(func(_date: GameDate) -> void: refresh())
	EventBus.day_passed.connect(func(_date: GameDate) -> void: _refresh_moving())
	EventBus.week_passed.connect(func(_date: GameDate) -> void:
		if not GameState.sim.wars.is_empty():
			refresh())
	EventBus.command_executed.connect(func(_command: Command) -> void: refresh())
	EventBus.sim_event_raised.connect(func(event: Dictionary) -> void:
		if event.get("type") in [WarSystem.EVENT_DECLARED, WarSystem.EVENT_JOINED, WarSystem.EVENT_ENDED,
				WarSystem.EVENT_CALL, WarSystem.EVENT_CALL_REFUSED, WarResolver.EVENT_PROVINCE_TAKEN,
				WarSystem.EVENT_PEACE_OFFER]:
			refresh())
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
	_clear_rows(_summary_grid)
	_clear_rows(_branches_grid)
	_clear_rows(_special_grid)
	_clear_rows(_groups_grid)
	_priority_spins.clear()
	var state := GameState.sim
	var country := state.get_country(str(state.player_tag))
	if country == null or country.military == null:
		return
	var military := country.military
	var locale := Localization.get_locale()
	var reserve_share: Array = (state.military_settings.get("mobilization", {}) as Dictionary).get("reserve_share", [])
	var personnel := military.personnel(reserve_share)
	_add_row(_summary_grid, "MILITARY_POWER", NumberFormat.integer(roundi(military.power), locale))
	_add_row(_summary_grid, "MILITARY_ACTIVE", NumberFormat.integer(roundi(personnel), locale))
	_add_row(_summary_grid, "MILITARY_RESERVE", NumberFormat.integer(roundi(military.reserves()), locale))
	var spending := float(country.economy.budget.spending.get(MilitaryModel.DEFENSE_LINE, 0.0))
	_add_row(_summary_grid, "MILITARY_DEFENSE_BUDGET", tr("MILITARY_BUDGET_VALUE") % [
		NumberFormat.decimal(spending, 1, locale),
		NumberFormat.decimal(MilitaryModel.defense_spending(country, state), 1, locale)])
	_add_row(_summary_grid, "MILITARY_ARMS_RECEIVED", tr("MILITARY_ARMS_VALUE") % NumberFormat.decimal(
		military.arms_flow * MilitaryModel.MONTHS_PER_YEAR, 1, locale))
	_add_row(_summary_grid, "MILITARY_NUCLEAR", NumberFormat.integer(military.nuclear_warheads, locale)
		if military.nuclear_warheads > 0 else tr("MILITARY_NONE"))
	_fill_wars(state, country.tag)
	_fill_branches(military, personnel, locale)
	_fill_groups(country, locale)
	for key: String in SPECIAL_KEYS:
		_add_row(_special_grid, "MILITARY_SPECIAL_%s" % key.to_upper(),
			tr("SOCIETY_SCORE_VALUE") % roundi(float(military.special.get(key, 0.0))))
	_mobilization_option.clear()
	for key: String in MOBILIZATION_KEYS:
		_mobilization_option.add_item(tr(key))
	_mobilization_option.select(military.mobilization)
	_mobilization_option.tooltip_text = tr("MILITARY_MOBILIZATION_TOOLTIP")
	_update_buttons()


func _fill_branches(military: MilitaryState, personnel: float, locale: String) -> void:
	for key: String in BRANCH_HEADERS:
		var header := Label.new()
		header.text = key
		header.add_theme_color_override("font_color", HEADER_COLOR)
		_branches_grid.add_child(header)
	for branch: String in GameState.sim.military_settings.get("branches", []):
		if not military.has_branch(branch):
			continue
		var values: Dictionary = military.branches[branch]
		var start: Dictionary = military.start_branches[branch]
		var symbol := military_ui.branch_symbol(branch)
		symbol.tooltip_text = tr("MILITARY_SYMBOL_TOOLTIP")
		_branches_grid.add_child(symbol)
		var name_label := Label.new()
		name_label.text = "MILITARY_BRANCH_%s" % branch.to_upper()
		name_label.add_theme_color_override("font_color", LABEL_COLOR)
		_branches_grid.add_child(name_label)
		_branches_grid.add_child(_value(NumberFormat.integer(roundi(personnel * float(values["share"])), locale)))
		_branches_grid.add_child(_value(NumberFormat.decimal(float(values["level"]), LEVEL_DECIMALS, locale),
			float(values["level"]) - float(start["level"]), tr("MILITARY_START_TOOLTIP") % NumberFormat.decimal(
			float(start["level"]), LEVEL_DECIMALS, locale)))
		_branches_grid.add_child(_value(tr("SOCIETY_SCORE_VALUE") % roundi(float(values["training"])),
			float(values["training"]) - float(start["training"]), tr("MILITARY_START_TOOLTIP") % str(roundi(
			float(start["training"])))))
		_branches_grid.add_child(_value(tr("SOCIETY_SCORE_VALUE") % roundi(float(values["morale"])),
			float(values["morale"]) - float(start["morale"]), tr("MILITARY_START_TOOLTIP") % str(roundi(
			float(start["morale"])))))
		var spin := SpinBox.new()
		var bounds: Dictionary = GameState.sim.military_settings.get("priorities", {})
		spin.min_value = float(bounds.get("min", 0.0)) * PERCENT
		spin.max_value = float(bounds.get("max", 1.0)) * PERCENT
		spin.step = PRIORITY_STEP
		spin.suffix = "%"
		spin.value = roundf(float(military.priorities.get(branch, 0.0)) * PERCENT)
		spin.value_changed.connect(func(_value_now: float) -> void: _update_buttons())
		_priority_spins[branch] = spin
		_branches_grid.add_child(spin)


func _fill_groups(country: CountryState, locale: String) -> void:
	_groups_grid.columns = GROUP_HEADERS.size()
	for key: String in GROUP_HEADERS:
		var header := Label.new()
		header.text = key
		header.add_theme_color_override("font_color", HEADER_COLOR)
		_groups_grid.add_child(header)
	var state := GameState.sim
	for group: ArmyGroup in ArmyGroupModel.groups_of(state, country.tag):
		var symbol := NatoSymbol.new()
		symbol.echelon = NatoSymbol.ARMY_GROUP
		symbol.tooltip_text = tr("MILITARY_SYMBOL_TOOLTIP")
		_groups_grid.add_child(symbol)
		var name_label := Label.new()
		name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name_label.text = military_ui.group_name(group)
		name_label.add_theme_color_override("font_color", LABEL_COLOR)
		_groups_grid.add_child(name_label)
		_groups_grid.add_child(_value(_province_name(group.province)))
		_groups_grid.add_child(_value(NumberFormat.integer(roundi(group.personnel(country.military,
			ArmyGroupModel.reserve_share(state))), locale)))
		var days := group.days_left
		for index: int in range(1, group.path.size()):
			days += ArmyGroupModel.travel_days(state, group.path[index - 1], group.path[index])
		_groups_grid.add_child(_value(tr("MILITARY_MOVING") % [_province_name(group.destination), days]
			if group.is_moving() else tr("MILITARY_STATIONED")))
		var button := Button.new()
		button.text = "MILITARY_SHOW"
		button.focus_mode = Control.FOCUS_NONE
		var group_id := group.id
		button.pressed.connect(func() -> void: group_focus_requested.emit(group_id))
		_groups_grid.add_child(button)


## Guerres du pays (camp, but, durée, occupation, paix blanche) et appels aux armes en attente.
func _fill_wars(state: SimState, tag: String) -> void:
	for child: Node in _wars_box.get_children():
		_wars_box.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "MILITARY_WARS"
	title.add_theme_color_override("font_color", HEADER_COLOR)
	_wars_box.add_child(title)
	var wars := WarSystem.wars_of(state, tag)
	if wars.is_empty() and state.calls_to_arms.is_empty():
		_wars_box.add_child(_text(tr("MILITARY_NO_WAR"), LABEL_COLOR))
	for war: War in wars:
		var side := war.side_of(tag)
		_wars_box.add_child(_text(MilitaryUI.war_name(state, war), HEADER_COLOR))
		var lines: PackedStringArray = []
		lines.append(tr("MILITARY_WAR_SIDE") % tr("MILITARY_SIDE_%s" % side.to_upper()))
		if not war.goal.is_empty():
			lines.append(tr("MILITARY_WAR_GOAL") % tr(str((state.war_goal_definitions.get(war.goal, {}) as Dictionary).get(
				"name_key", war.goal))))
		lines.append(tr("MILITARY_WAR_DURATION") % floori(war.months()))
		lines.append(tr("MILITARY_WAR_ALLIES") % _names(state, war.members(side), tag))
		lines.append(tr("MILITARY_WAR_ENEMIES") % _names(state, war.enemies_of(tag), ""))
		lines.append(tr("MILITARY_WAR_OCCUPATION") % [roundi(WarSystem.occupied_percent(state, war, side)),
			roundi(WarSystem.occupied_percent(state, war, War.other_side(side)))])
		var enemy_losses := 0.0
		for enemy: String in war.enemies_of(tag):
			enemy_losses += float(war.casualties.get(enemy, 0.0))
		var locale := Localization.get_locale()
		lines.append(tr("MILITARY_WAR_CASUALTIES") % [NumberFormat.integer(roundi(float(war.casualties.get(tag, 0.0))), locale),
			NumberFormat.integer(roundi(enemy_losses), locale)])
		_wars_box.add_child(_text("
".join(lines), LABEL_COLOR))
		_fill_fronts(state, war, tag, locale)
		if war.civil:
			continue
		var offer := WarSystem.peace_offer(state, war.id)
		if not offer.is_empty():
			_wars_box.add_child(_text(tr("MILITARY_PEACE_OFFER") % [MilitaryUI.side_name(state, str(offer["from"])),
				int(offer["days_left"])], GovernmentPanel.GOOD_COLOR))
			var answers := HBoxContainer.new()
			for accept: bool in [true, false]:
				var answer := Button.new()
				answer.text = "MILITARY_PEACE_ACCEPT" if accept else "MILITARY_PEACE_REFUSE"
				answer.focus_mode = Control.FOCUS_NONE
				var offered_war := war.id
				answer.pressed.connect(func() -> void: _submit(AnswerPeaceCommand.new(state.player_tag, offered_war, accept)))
				answers.add_child(answer)
			_wars_box.add_child(answers)
		var refusal := WarSystem.white_peace_refusal(state, tag, war.id)
		if refusal == "WAR_NOT_LEADER":
			continue
		var button := Button.new()
		button.text = "MILITARY_WHITE_PEACE"
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.disabled = not refusal.is_empty()
		var score := WarSystem.white_peace_score(state, war, tag)
		button.tooltip_text = tr(refusal) if not refusal.is_empty() 			else tr("MILITARY_WHITE_PEACE_LIKELY_YES" if score > 0.0 else "MILITARY_WHITE_PEACE_LIKELY_NO") % roundi(score)
		var war_id := war.id
		button.pressed.connect(func() -> void: _submit(WhitePeaceCommand.new(state.player_tag, war_id)))
		_wars_box.add_child(button)
	if not FrontSystem.fronts_of(state, tag).is_empty():
		var deploy := Button.new()
		deploy.text = "MILITARY_AUTO_DEPLOY"
		deploy.focus_mode = Control.FOCUS_NONE
		deploy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var deploy_refusal := AutoDeployCommand.new(state.player_tag).refusal_reason(state)
		deploy.disabled = not deploy_refusal.is_empty()
		deploy.tooltip_text = tr(deploy_refusal) if not deploy_refusal.is_empty() else tr("MILITARY_AUTO_DEPLOY_TOOLTIP")
		deploy.pressed.connect(func() -> void: _submit(AutoDeployCommand.new(state.player_tag)))
		_wars_box.add_child(deploy)
	for call: Dictionary in state.calls_to_arms:
		if str(call["ally"]) != tag or not state.wars.has(int(call["war"])):
			continue
		var war: War = state.wars[int(call["war"])]
		_wars_box.add_child(_text(tr("MILITARY_CALL_TO_ARMS") % [MilitaryUI.side_name(state, war.members(str(call["side"]))[0]),
			MilitaryUI.war_name(state, war), int(call["days_left"])], GovernmentPanel.BAD_COLOR))
		var row := HBoxContainer.new()
		for accept: bool in [true, false]:
			var answer := Button.new()
			answer.text = "MILITARY_CALL_ACCEPT" if accept else "MILITARY_CALL_REFUSE"
			answer.tooltip_text = "MILITARY_CALL_ACCEPT_TOOLTIP" if accept else "MILITARY_CALL_REFUSE_TOOLTIP"
			answer.focus_mode = Control.FOCUS_NONE
			var war_id := war.id
			answer.pressed.connect(func() -> void: _submit(AnswerCallToArmsCommand.new(state.player_tag, war_id, accept)))
			row.add_child(answer)
		_wars_box.add_child(row)


## Fronts du pays dans une guerre : forces en présence, terrain gagné ou perdu par jour, posture, « Voir ».
func _fill_fronts(state: SimState, war: War, tag: String, locale: String) -> void:
	FrontSystem.refresh(state)
	var ours := FrontSystem.engaged_personnel(state, tag)
	for front: Front in FrontSystem.fronts_of_war(state, war.id):
		if front.a != tag and front.b != tag:
			continue
		var enemy := front.other(tag)
		var theirs := FrontSystem.engaged_personnel(state, enemy)
		var row := HBoxContainer.new()
		var gained := float(front.progress.get(tag, 0.0)) - float(front.progress.get(enemy, 0.0))
		var trend := tr("MILITARY_FRONT_STABLE") if absf(gained) < 0.00001 			else tr("MILITARY_FRONT_GAINING" if gained > 0.0 else "MILITARY_FRONT_LOSING") % NumberFormat.decimal(
				absf(gained) * PERCENT, 2, locale)
		var label := _text(tr("MILITARY_FRONT") % [MilitaryUI.side_name(state, enemy), front.provinces_of(tag).size(),
			NumberFormat.integer(roundi(float(ours.get(front.key, 0.0))), locale),
			NumberFormat.integer(roundi(float(theirs.get(front.key, 0.0))), locale), trend],
			GovernmentPanel.GOOD_COLOR if gained > 0.0 else GovernmentPanel.BAD_COLOR if gained < 0.0 else LABEL_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = tr("MILITARY_FRONT_TOOLTIP") % [
			NumberFormat.decimal(float(front.strength.get(tag, 0.0)) * POWER_SCALE, 1, locale),
			NumberFormat.decimal(float(front.strength.get(enemy, 0.0)) * POWER_SCALE, 1, locale),
			tr("MILITARY_POSTURE_%s" % front.posture_of(enemy).to_upper())]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(label)
		var option := OptionButton.new()
		option.focus_mode = Control.FOCUS_NONE
		option.tooltip_text = tr("MILITARY_POSTURE_TOOLTIP")
		for posture: String in FrontSystem.POSTURES:
			option.add_item(tr("MILITARY_POSTURE_%s" % posture.to_upper()))
		option.select(FrontSystem.POSTURES.find(front.posture_of(tag)))
		var key := front.key
		option.item_selected.connect(func(index: int) -> void:
			_submit(SetFrontPostureCommand.new(state.player_tag, key, FrontSystem.POSTURES[index])))
		row.add_child(option)
		var show := Button.new()
		show.text = "MILITARY_SHOW"
		show.focus_mode = Control.FOCUS_NONE
		var focus: String = str(front.contested[0]) if not front.contested.is_empty() else str(front.provinces_of(tag)[0])
		show.pressed.connect(func() -> void: province_focus_requested.emit(focus))
		row.add_child(show)
		_wars_box.add_child(row)


func _names(state: SimState, tags: Array[String], excluded: String) -> String:
	var names: PackedStringArray = []
	for tag: String in tags:
		if tag != excluded:
			names.append(MilitaryUI.side_name(state, tag))
	return ", ".join(names) if not names.is_empty() else tr("MILITARY_NONE")


func _text(text: String, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label


func _province_name(province_id: String) -> String:
	return tr(str(DataLoader.get_entry("provinces", province_id).get("name_key", "")))


## Chaque jour, seulement si un groupe du pays joué est en marche (la liste change).
func _refresh_moving() -> void:
	if not visible:
		return
	for group: ArmyGroup in ArmyGroupModel.groups_of(GameState.sim, str(GameState.sim.player_tag)):
		if group.is_moving() or group.days_left > 0:
			refresh()
			return


func _priorities_command() -> SetDefensePrioritiesCommand:
	var priorities: Dictionary = {}
	for branch: String in _priority_spins.keys():
		priorities[branch] = (_priority_spins[branch] as SpinBox).value / PERCENT
	return SetDefensePrioritiesCommand.new(GameState.sim.player_tag, priorities)


func _update_buttons() -> void:
	var state := GameState.sim
	var refusal := MobilizeCommand.new(state.player_tag, _mobilization_option.selected).refusal_reason(state)
	_mobilization_button.disabled = not refusal.is_empty()
	_mobilization_button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("MILITARY_MOBILIZE_TOOLTIP")
	var priority_refusal := _priorities_command().refusal_reason(state) if not _priority_spins.is_empty() \
		else "MILITARY_INVALID"
	_priorities_button.disabled = not priority_refusal.is_empty()
	_priorities_button.tooltip_text = tr(priority_refusal) if not priority_refusal.is_empty() \
		else tr("MILITARY_PRIORITIES_TOOLTIP")


func _submit(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


func _value(text: String, change: float = 0.0, tooltip: String = "") -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if absf(change) >= 0.01:
		label.add_theme_color_override("font_color", GovernmentPanel.GOOD_COLOR if change > 0.0 else GovernmentPanel.BAD_COLOR)
	if not tooltip.is_empty():
		label.tooltip_text = tooltip
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	return label

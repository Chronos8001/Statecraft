class_name MilitaryPanel
extends InfoPanel
## Panneau Armée du pays joué : puissance, effectifs, budget de défense, branches (symboles OTAN), capacités
## spéciales, arsenal nucléaire, priorités d'équipement et mobilisation.

const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const BRANCH_HEADERS := ["", "MILITARY_BRANCH", "MILITARY_PERSONNEL", "MILITARY_LEVEL", "MILITARY_TRAINING",
	"MILITARY_MORALE", "MILITARY_PRIORITY"]
const SPECIAL_KEYS := ["special_forces", "missiles", "cyber"]
const MOBILIZATION_KEYS := ["MILITARY_MOBILIZATION_0", "MILITARY_MOBILIZATION_1", "MILITARY_MOBILIZATION_2"]
const LEVEL_DECIMALS := 2
const PERCENT := 100.0
const PRIORITY_STEP := 1.0

var military_ui: MilitaryUI = MilitaryUI.new()
var _priority_spins: Dictionary = {}

@onready var _summary_grid: GridContainer = %SummaryGrid
@onready var _branches_grid: GridContainer = %BranchesGrid
@onready var _special_grid: GridContainer = %SpecialGrid
@onready var _mobilization_option: OptionButton = %MobilizationOption
@onready var _mobilization_button: Button = %MobilizationButton
@onready var _priorities_button: Button = %PrioritiesButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_branches_grid.columns = BRANCH_HEADERS.size()
	_mobilization_option.item_selected.connect(func(_index: int) -> void: _update_buttons())
	_mobilization_button.pressed.connect(func() -> void:
		_submit(MobilizeCommand.new(GameState.sim.player_tag, _mobilization_option.selected)))
	_priorities_button.pressed.connect(func() -> void: _submit(_priorities_command()))
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
	_clear_rows(_summary_grid)
	_clear_rows(_branches_grid)
	_clear_rows(_special_grid)
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
	_fill_branches(military, personnel, locale)
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

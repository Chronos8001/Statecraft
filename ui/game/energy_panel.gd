class_name EnergyPanel
extends InfoPanel
## Panneau Énergie du pays joué : mix électrique par source, demande, marge, coupures, et chantiers en cours
## (avec abandon possible). Les constructions se lancent depuis la fiche d'une province.

const COLUMNS := 4
const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const ALERT_COLOR := Color(0.95, 0.5, 0.45)
const LOW_MARGIN := 1.1
const HEADER_KEYS := ["ENERGY_SOURCE", "ENERGY_CAPACITY", "ENERGY_OUTPUT", "ENERGY_SHARE"]

@onready var _mix_grid: GridContainer = %MixGrid
@onready var _stats_grid: GridContainer = %EnergyStatsGrid
@onready var _projects_box: VBoxContainer = %ProjectsBox
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_mix_grid.columns = COLUMNS
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
	var state := GameState.sim
	var country := state.get_country(str(state.player_tag))
	_clear_rows(_mix_grid)
	_clear_rows(_stats_grid)
	for child: Node in _projects_box.get_children():
		_projects_box.remove_child(child)
		child.queue_free()
	if country == null:
		return
	_fill_mix(country.energy, state)
	_fill_stats(country)
	_fill_projects(state)


func _fill_mix(energy: EnergyState, state: SimState) -> void:
	for key: String in HEADER_KEYS:
		var header := Label.new()
		header.text = key
		header.add_theme_color_override("font_color", HEADER_COLOR)
		_mix_grid.add_child(header)
	var locale := Localization.get_locale()
	var sources: Dictionary = state.energy_definitions.get("sources", {})
	var total := energy.total_output()
	for source_id: String in sources.keys():
		var capacity := float(energy.capacity.get(source_id, 0.0))
		if capacity <= 0.0:
			continue
		var output := float(energy.output.get(source_id, 0.0))
		var name_label := Label.new()
		name_label.text = str((sources[source_id] as Dictionary).get("name_key", source_id))
		name_label.add_theme_color_override("font_color", Color.html(str((sources[source_id] as Dictionary).get("color", "#FFFFFF"))).lightened(0.2))
		_mix_grid.add_child(name_label)
		_mix_grid.add_child(_value(tr("ENERGY_GW_VALUE") % NumberFormat.decimal(capacity, 1, locale)))
		_mix_grid.add_child(_value(tr("ENERGY_TWH_VALUE") % NumberFormat.decimal(output, 1, locale)))
		_mix_grid.add_child(_value(tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(
			output / total * EconomyModel.PERCENT if total > 0.0 else 0.0, 1, locale)))


func _fill_stats(country: CountryState) -> void:
	var energy := country.energy
	var locale := Localization.get_locale()
	_add_row(_stats_grid, "ENERGY_DEMAND", tr("ENERGY_TWH_VALUE") % NumberFormat.decimal(energy.demand, 1, locale))
	_add_row(_stats_grid, "ENERGY_MAX_SUPPLY", tr("ENERGY_TWH_VALUE") % NumberFormat.decimal(energy.max_supply, 1, locale))
	_add_row(_stats_grid, "ENERGY_MARGIN", tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(
		(energy.margin() - 1.0) * EconomyModel.PERCENT, 0, locale))
	_add_row(_stats_grid, "ENERGY_BLACKOUT", tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(
		energy.blackout * EconomyModel.PERCENT, 1, locale))
	if energy.margin() < LOW_MARGIN:
		var warning := Label.new()
		warning.text = "ENERGY_LOW_MARGIN"
		warning.add_theme_color_override("font_color", ALERT_COLOR)
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_stats_grid.add_child(warning)
		_stats_grid.add_child(Control.new())
	_add_row(_stats_grid, "ENERGY_PROJECT_SPENDING", tr("ECONOMY_GDP_SHARE_VALUE") % NumberFormat.decimal(
		country.economy.project_spending, 2, locale))


func _fill_projects(state: SimState) -> void:
	var player := str(state.player_tag)
	var buildings: Dictionary = state.energy_definitions.get("buildings", {})
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var locale := Localization.get_locale()
	var count := 0
	for project: Dictionary in state.projects:
		if str(project["tag"]) != player:
			continue
		count += 1
		var row := HBoxContainer.new()
		var province: Dictionary = provinces.get(str(project["province"]), {})
		var label := _value(tr("ENERGY_PROJECT_VALUE") % [tr(str(buildings[project["building"]]["name_key"])),
			tr(str(province.get("name_key", ""))), int(project["months_left"]),
			NumberFormat.decimal(float(project["monthly_cost"]) * EconomyModel.MONTHS_PER_YEAR, 2, locale)])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var cancel := Button.new()
		cancel.text = "ENERGY_CANCEL"
		cancel.tooltip_text = "ENERGY_CANCEL_TOOLTIP"
		cancel.focus_mode = Control.FOCUS_NONE
		var project_id := int(project["id"])
		cancel.pressed.connect(func() -> void:
			if GameState.submit_command(CancelProjectCommand.new(state.player_tag, project_id)) and GameClock.is_paused:
				GameState.process_commands())
		row.add_child(cancel)
		_projects_box.add_child(row)
	if count == 0:
		_projects_box.add_child(_value(tr("ENERGY_NO_PROJECT")))


func _value(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	return label

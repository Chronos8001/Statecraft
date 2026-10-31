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
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
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

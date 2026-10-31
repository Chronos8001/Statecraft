class_name GovernmentPanel
extends InfoPanel
## Panneau Gouvernement du pays joué : ministres (parti, compétence, loyauté, corruption) et remaniement
## parmi les candidats proposés pour chaque portefeuille.

const MINISTER_COLUMNS := 6
const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const GOOD_COLOR := Color(0.55, 0.85, 0.55)
const BAD_COLOR := Color(0.95, 0.5, 0.45)
const MINISTER_HEADERS := ["GOVERNMENT_PORTFOLIO", "GOVERNMENT_MINISTER", "GOVERNMENT_PARTY",
	"GOVERNMENT_COMPETENCE", "GOVERNMENT_LOYALTY", "GOVERNMENT_CORRUPTION"]
## Seuils d'affichage en couleur (loyauté basse, corruption forte).
const LOW_LOYALTY := 35
const HIGH_CORRUPTION := 60

var _portfolio_ids: Array[String] = []

@onready var _summary_grid: GridContainer = %SummaryGrid
@onready var _ministers_grid: GridContainer = %MinistersGrid
@onready var _portfolio_option: OptionButton = %PortfolioOption
@onready var _candidates_box: VBoxContainer = %CandidatesBox
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_ministers_grid.columns = MINISTER_COLUMNS
	_portfolio_option.item_selected.connect(func(_index: int) -> void: _fill_candidates())
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
	_clear_rows(_ministers_grid)
	var state := GameState.sim
	var country := state.get_country(str(state.player_tag))
	if country == null or country.cabinet.is_empty():
		return
	var cultures := DataLoader.get_category("names/cultures")
	var locale := Localization.get_locale()
	_add_row(_summary_grid, "POLITICS_HEAD_OF_GOVERNMENT", NameGenerator.full_name(
		GovernmentSystem.character(state, country.politics.head_of_government), cultures))
	_add_row(_summary_grid, "SOCIETY_CORRUPTION", tr("SOCIETY_SCORE_VALUE") % roundi(country.society.corruption))
	for key: String in MINISTER_HEADERS:
		var header := Label.new()
		header.text = key
		header.add_theme_color_override("font_color", HEADER_COLOR)
		_ministers_grid.add_child(header)
	var portfolios: Dictionary = state.politics_definitions.get("portfolios", {})
	var settings := GovernmentModel.settings_of(state)
	var previous := _portfolio_ids[_portfolio_option.selected] if _portfolio_option.selected >= 0 \
		and _portfolio_option.selected < _portfolio_ids.size() else ""
	_portfolio_ids.clear()
	_portfolio_option.clear()
	for portfolio_id: String in portfolios.keys():
		if not country.cabinet.has(portfolio_id):
			continue
		var minister := GovernmentSystem.character(state, str(country.cabinet[portfolio_id]))
		var portfolio: Dictionary = portfolios[portfolio_id]
		var name_label := Label.new()
		name_label.text = str(portfolio["name_key"])
		name_label.add_theme_color_override("font_color", LABEL_COLOR)
		_ministers_grid.add_child(name_label)
		_ministers_grid.add_child(_value(NameGenerator.full_name(minister, cultures)))
		_ministers_grid.add_child(_value(_party_abbreviation(str(minister.get("party", "")))))
		_ministers_grid.add_child(_value(NumberFormat.decimal(GovernmentModel.competence(minister, portfolio, settings), 0,
			locale)))
		_ministers_grid.add_child(_score(int(minister.get("loyalty", 0)), int(minister.get("loyalty", 0)) < LOW_LOYALTY))
		_ministers_grid.add_child(_score(int(minister.get("corruption", 0)),
			int(minister.get("corruption", 0)) >= HIGH_CORRUPTION))
		_portfolio_ids.append(portfolio_id)
		_portfolio_option.add_item(tr(str(portfolio["name_key"])))
	var index := _portfolio_ids.find(previous)
	_portfolio_option.select(index if index >= 0 else 0)
	_fill_candidates()


## Candidats au portefeuille choisi, chacun avec son bouton « Nommer ».
func _fill_candidates() -> void:
	for child: Node in _candidates_box.get_children():
		_candidates_box.remove_child(child)
		child.queue_free()
	var state := GameState.sim
	var country := state.get_country(str(state.player_tag))
	if country == null or _portfolio_option.selected < 0 or _portfolio_ids.is_empty():
		return
	var portfolio_id := _portfolio_ids[_portfolio_option.selected]
	var portfolio: Dictionary = (state.politics_definitions.get("portfolios", {}) as Dictionary).get(portfolio_id, {})
	var cultures := DataLoader.get_category("names/cultures")
	var proposed := GovernmentSystem.candidates(country, state, portfolio_id)
	for index: int in proposed.size():
		var candidate: Dictionary = proposed[index]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = tr("GOVERNMENT_CANDIDATE_VALUE") % [NameGenerator.full_name(candidate, cultures),
			_party_abbreviation(str(candidate.get("party", ""))),
			roundi(GovernmentModel.competence(candidate, portfolio, GovernmentModel.settings_of(state))),
			int(candidate.get("loyalty", 0)), int(candidate.get("corruption", 0))]
		row.add_child(label)
		var button := Button.new()
		button.text = "GOVERNMENT_APPOINT"
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "GOVERNMENT_APPOINT_TOOLTIP"
		button.pressed.connect(func() -> void:
			if GameState.submit_command(AppointMinisterCommand.new(state.player_tag, portfolio_id, index)) \
					and GameClock.is_paused:
				GameState.process_commands())
		row.add_child(button)
		_candidates_box.add_child(row)


func _party_abbreviation(party_id: String) -> String:
	if party_id.is_empty():
		return tr("GOVERNMENT_NO_PARTY")
	return str(DataLoader.repository.resolve_ref("names#parties").get(party_id, {}).get("abbreviation", party_id))


func _score(value: int, bad: bool) -> Label:
	var label := _value(str(value))
	label.add_theme_color_override("font_color", BAD_COLOR if bad else Color(0.85, 0.88, 0.92))
	return label


func _value(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	return label

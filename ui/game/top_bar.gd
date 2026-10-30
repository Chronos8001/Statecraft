class_name TopBar
extends PanelContainer
## Barre supérieure : date, contrôle du temps, accès aux panneaux et ressources clés du pays joué.

signal economy_requested
signal budget_requested

const TREASURY_INDEX := 0
const STAT_KEYS := ["TOPBAR_TREASURY", "TOPBAR_STABILITY", "TOPBAR_SUPPORT", "TOPBAR_MILITARY", "TOPBAR_INFLUENCE"]
const PIP_ON := "■"
const PIP_OFF := "□"
const PAUSE_SYMBOL := "❚❚"
const PLAY_SYMBOL := "▶"

var _stat_values: Array[Label] = []

@onready var _date_label: Label = %DateLabel
@onready var _pause_button: Button = %PauseButton
@onready var _slower_button: Button = %SlowerButton
@onready var _faster_button: Button = %FasterButton
@onready var _speed_label: Label = %SpeedLabel
@onready var _country_label: Label = %CountryLabel
@onready var _flag_rect: TextureRect = %FlagRect
@onready var _stats_row: HBoxContainer = %StatsRow
@onready var _economy_button: Button = %EconomyButton
@onready var _budget_button: Button = %BudgetButton


func _ready() -> void:
	_pause_button.pressed.connect(GameClock.toggle_pause)
	_slower_button.pressed.connect(func() -> void: GameClock.set_speed(GameClock.speed - 1))
	_faster_button.pressed.connect(func() -> void: GameClock.set_speed(GameClock.speed + 1))
	_economy_button.pressed.connect(func() -> void: economy_requested.emit())
	_budget_button.pressed.connect(func() -> void: budget_requested.emit())
	EventBus.month_passed.connect(func(_date: GameDate) -> void: _update_country())
	EventBus.command_executed.connect(func(_command: Command) -> void: _update_country())
	EventBus.hour_passed.connect(func(_date: GameDate) -> void: _update_date())
	EventBus.game_speed_changed.connect(func(_speed: int) -> void: _update_speed())
	EventBus.game_pause_changed.connect(func(_paused: bool) -> void: _update_speed())
	EventBus.locale_changed.connect(func(_locale: String) -> void: refresh())
	_build_stats()
	refresh()


func refresh() -> void:
	_update_date()
	_update_speed()
	_update_country()


func _build_stats() -> void:
	for key: String in STAT_KEYS:
		var name_label := Label.new()
		name_label.text = key
		name_label.add_theme_color_override("font_color", InfoPanel.LABEL_COLOR)
		_stats_row.add_child(name_label)
		var value_label := Label.new()
		value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value_label.custom_minimum_size.x = 40.0
		_stats_row.add_child(value_label)
		_stat_values.append(value_label)


func _update_date() -> void:
	var date := GameClock.get_date()
	_date_label.text = DateFormat.long_date(date, tr(DateFormat.month_key(date.month)), Localization.get_locale())


func _update_speed() -> void:
	_pause_button.text = PLAY_SYMBOL if GameClock.is_paused else PAUSE_SYMBOL
	var pips := ""
	for level: int in range(1, GameClock.get_speed_count() + 1):
		pips += PIP_ON if level <= GameClock.speed else PIP_OFF
	var status := tr("TOPBAR_PAUSED") if GameClock.is_paused else tr("TOPBAR_SPEED") % GameClock.speed
	_speed_label.text = "%s  %s" % [pips, status]
	_slower_button.disabled = GameClock.speed <= 1
	_faster_button.disabled = GameClock.speed >= GameClock.get_speed_count()


## Pays joué et ses ressources. Trésorerie : solde budgétaire annuel ; les autres valeurs restent « — »
## tant que les systèmes qui les calculent n'existent pas.
func _update_country() -> void:
	var tag := str(GameState.sim.player_tag)
	var country := DataLoader.get_entry("countries", tag)
	_country_label.text = tr(str(country.get("name_key", ""))) if not country.is_empty() else tr("TOPBAR_NO_COUNTRY")
	_flag_rect.visible = not country.is_empty()
	if not country.is_empty():
		_flag_rect.texture = CountryFlags.texture_for(CountryFlags.path_for(tag, country),
			Color.html(str(country.get("color", "#808080"))))
	for value_label: Label in _stat_values:
		value_label.text = tr("TOPBAR_UNKNOWN")
	var state := GameState.sim.get_country(tag)
	var currency := GameState.sim.get_currency(state.economy.currency) if state != null else null
	if currency != null and not _stat_values.is_empty():
		var balance := state.economy.budget_balance(currency) / 100.0 * state.economy.gdp_usd(currency)
		var treasury := _stat_values[TREASURY_INDEX]
		treasury.text = tr("TOPBAR_BALANCE_VALUE") % [("+" if balance > 0.0 else ""),
			NumberFormat.integer(roundi(balance), Localization.get_locale())]
		treasury.tooltip_text = tr("TOPBAR_BALANCE_TOOLTIP")
		treasury.mouse_filter = Control.MOUSE_FILTER_STOP

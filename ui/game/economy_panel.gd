class_name EconomyPanel
extends InfoPanel
## Panneau Économie du pays joué : chiffres clés, banque centrale, dette, note souveraine, secteurs.
## Le joueur peut fixer le taux directeur (banque centrale sous contrôle) et demander l'aide du FMI.

const SECTOR_BAR_HEIGHT := 10.0
const SECTOR_BAR_WIDTH := 180.0
const RATE_STEP := 0.25
const RATE_DECIMALS := 2
const DECIMALS := 1

var _ratings: CreditRating

@onready var _flag: TextureRect = %FlagRect
@onready var _name_label: Label = %NameLabel
@onready var _stats_grid: GridContainer = %StatsGrid
@onready var _rate_row: HBoxContainer = %RateRow
@onready var _rate_spin: SpinBox = %RateSpin
@onready var _rate_button: Button = %RateButton
@onready var _imf_button: Button = %ImfButton
@onready var _sectors_box: VBoxContainer = %SectorsBox
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_rate_button.pressed.connect(_on_rate_pressed)
	_imf_button.pressed.connect(_on_imf_pressed)
	_rate_spin.step = RATE_STEP
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
	_clear_rows(_stats_grid)
	for child: Node in _sectors_box.get_children():
		_sectors_box.remove_child(child)
		child.queue_free()
	if country == null:
		_name_label.text = tr("TOPBAR_NO_COUNTRY")
		_flag.texture = null
		_rate_row.visible = false
		_imf_button.visible = false
		return
	_ratings = CreditRating.new(state.economy_settings)
	var data := DataLoader.get_entry("countries", country.tag)
	_flag.texture = CountryFlags.texture_for(CountryFlags.path_for(country.tag, data),
		Color.html(str(data.get("color", "#808080"))))
	_name_label.text = tr(str(data.get("name_key", country.tag)))
	var economy := country.economy
	var currency := state.get_currency(economy.currency)
	if currency == null:
		return
	_fill_stats(economy, currency)
	_fill_central_bank(state, currency)
	_fill_sectors(economy)
	_imf_button.visible = RequestImfCommand.new(state.player_tag).can_execute(state)
	_imf_button.disabled = false


func _fill_stats(economy: EconomyState, currency: CurrencyState) -> void:
	var locale := Localization.get_locale()
	_add_row(_stats_grid, "COUNTRY_INFO_GDP", tr("COUNTRY_INFO_GDP_VALUE") % NumberFormat.integer(
		roundi(economy.gdp_usd(currency)), locale))
	_add_row(_stats_grid, "COUNTRY_INFO_GDP_PER_CAPITA", tr("COUNTRY_INFO_USD_VALUE") % NumberFormat.integer(
		roundi(economy.gdp_per_capita_usd(currency)), locale))
	_add_row(_stats_grid, "ECONOMY_GROWTH", _percent(economy.growth))
	_add_row(_stats_grid, "ECONOMY_INFLATION", tr("ECONOMY_INFLATION_VALUE") % [_number(economy.inflation),
		_number(currency.inflation_target)])
	_add_row(_stats_grid, "ECONOMY_UNEMPLOYMENT", _percent(economy.unemployment))
	_add_row(_stats_grid, "ECONOMY_CURRENCY", _currency_text(currency))
	_add_row(_stats_grid, "ECONOMY_POLICY_RATE", _percent(currency.policy_rate, RATE_DECIMALS))
	_add_row(_stats_grid, "ECONOMY_CENTRAL_BANK", tr(_central_bank_key(currency)))
	_add_row(_stats_grid, "COUNTRY_INFO_DEBT", tr("ECONOMY_DEBT_VALUE") % [_number(economy.debt_ratio(currency) * 100.0, 0),
		_number(economy.foreign_debt_share(currency) * 100.0, 0)])
	_add_row(_stats_grid, "ECONOMY_BUDGET_BALANCE", tr("ECONOMY_GDP_SHARE_VALUE") % _number(economy.budget_balance(currency)))
	_add_row(_stats_grid, "ECONOMY_INTEREST", tr("ECONOMY_GDP_SHARE_VALUE") % _number(economy.interest_burden(currency)))
	_add_row(_stats_grid, "ECONOMY_BORROWING_RATE", _percent(currency.policy_rate + _ratings.spread(economy.rating)))
	var rating := _ratings.id_of(economy.rating)
	_add_row(_stats_grid, "ECONOMY_RATING", tr("ECONOMY_RATING_ESTIMATED") % rating if economy.rating_estimated else rating)
	if economy.in_crisis():
		_add_row(_stats_grid, "ECONOMY_STATUS", tr("ECONOMY_STATUS_CRISIS") % economy.crisis_months)
	elif economy.in_imf_program():
		_add_row(_stats_grid, "ECONOMY_STATUS", tr("ECONOMY_STATUS_IMF") % economy.imf_months)


func _fill_central_bank(state: SimState, currency: CurrencyState) -> void:
	var controllable := SetPolicyRateCommand.new(state.player_tag, currency.policy_rate).can_execute(state)
	_rate_row.visible = controllable
	if controllable and not _rate_spin.get_line_edit().has_focus():
		var settings := state.economy_settings
		_rate_spin.min_value = float(settings.get("min_policy_rate", 0.0))
		_rate_spin.max_value = float(settings.get("max_policy_rate", 100.0))
		_rate_spin.set_value_no_signal(currency.policy_rate)


func _fill_sectors(economy: EconomyState) -> void:
	var sectors := DataLoader.get_category("economy_sectors")
	var ids: Array = economy.sectors.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return float(economy.sectors[a]) > float(economy.sectors[b]))
	for sector_id: Variant in ids:
		var sector: Dictionary = sectors.get(str(sector_id), {})
		var share := float(economy.sectors[sector_id])
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(sector.get("name_key", sector_id))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", LABEL_COLOR)
		row.add_child(label)
		var bar := ColorRect.new()
		bar.color = Color.html(str(sector.get("color", "#808080")))
		bar.custom_minimum_size = Vector2(maxf(SECTOR_BAR_WIDTH * share, 1.0), SECTOR_BAR_HEIGHT)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var value := Label.new()
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value.text = _percent(share * 100.0)
		value.custom_minimum_size.x = 64.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		_sectors_box.add_child(row)


func _central_bank_key(currency: CurrencyState) -> String:
	if currency.is_pegged():
		return "ECONOMY_CENTRAL_BANK_PEGGED"
	if currency.issuer.is_empty():
		return "ECONOMY_CENTRAL_BANK_UNION"
	return "ECONOMY_CENTRAL_BANK_INDEPENDENT" if currency.independent else "ECONOMY_CENTRAL_BANK_GOVERNMENT"


func _currency_text(currency: CurrencyState) -> String:
	var rate := tr("ECONOMY_EXCHANGE_VALUE") % [_number(currency.usd_rate, 2), currency.code]
	if currency.is_pegged():
		var anchor := GameState.sim.get_currency(currency.peg)
		return tr("ECONOMY_PEGGED_VALUE") % [rate, anchor.code if anchor != null else currency.peg.to_upper()]
	return rate


func _on_rate_pressed() -> void:
	_submit(SetPolicyRateCommand.new(GameState.sim.player_tag, _rate_spin.value))


func _on_imf_pressed() -> void:
	_imf_button.disabled = true
	_submit(RequestImfCommand.new(GameState.sim.player_tag))


## En pause, la décision s'applique tout de suite ; sinon au prochain tick.
func _submit(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


func _number(value: float, decimals: int = DECIMALS) -> String:
	return NumberFormat.decimal(value, decimals, Localization.get_locale())


func _percent(value: float, decimals: int = DECIMALS) -> String:
	return tr("ECONOMY_PERCENT_VALUE") % _number(value, decimals)

class_name InvestmentPanel
extends InfoPanel
## Panneau Investissements du pays joué : part publique de chaque secteur (nationaliser, privatiser),
## investissements étrangers et politique d'ouverture, fonds souverain.

const OWNERSHIP_COLUMNS := 4
const SHARE_STEP := 1.0
const FUND_STEP := 10.0
const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const ALERT_COLOR := Color(0.95, 0.5, 0.45)
const OWNERSHIP_HEADERS := ["INVEST_SECTOR", "INVEST_PUBLIC_SHARE", "INVEST_NEW_SHARE", ""]

var _sector_spins: Dictionary = {}

@onready var _ownership_grid: GridContainer = %OwnershipGrid
@onready var _expropriate_check: CheckBox = %ExpropriateCheck
@onready var _fdi_grid: GridContainer = %FdiGrid
@onready var _policy_option: OptionButton = %PolicyOption
@onready var _policy_button: Button = %PolicyButton
@onready var _fund_grid: GridContainer = %FundGrid
@onready var _fund_spin: SpinBox = %FundSpin
@onready var _deposit_button: Button = %DepositButton
@onready var _withdraw_button: Button = %WithdrawButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_ownership_grid.columns = OWNERSHIP_COLUMNS
	_fund_spin.step = FUND_STEP
	_policy_button.pressed.connect(_on_policy_pressed)
	_deposit_button.pressed.connect(func() -> void: _submit(FundTransferCommand.new(GameState.sim.player_tag, _fund_spin.value)))
	_withdraw_button.pressed.connect(func() -> void: _submit(FundTransferCommand.new(GameState.sim.player_tag, -_fund_spin.value)))
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
	_clear_rows(_ownership_grid)
	_clear_rows(_fdi_grid)
	_clear_rows(_fund_grid)
	_sector_spins.clear()
	if country == null or state.investment_settings.is_empty():
		return
	_fill_ownership(country, state)
	_fill_fdi(country)
	_fill_fund(country, state)


func _fill_ownership(country: CountryState, state: SimState) -> void:
	for key: String in OWNERSHIP_HEADERS:
		var header := Label.new()
		header.text = key
		header.add_theme_color_override("font_color", HEADER_COLOR)
		_ownership_grid.add_child(header)
	var sectors := DataLoader.get_category("economy_sectors")
	var locale := Localization.get_locale()
	var ownership := country.economy.investment.public_ownership
	for sector_id: String in sectors.keys():
		if not ownership.has(sector_id):
			continue
		var share := float(ownership[sector_id]) * EconomyModel.PERCENT
		var name_label := Label.new()
		name_label.text = str((sectors[sector_id] as Dictionary).get("name_key", sector_id))
		_ownership_grid.add_child(name_label)
		_ownership_grid.add_child(_value(tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(share, 0, locale)))
		var spin := SpinBox.new()
		spin.min_value = 0.0
		spin.max_value = EconomyModel.PERCENT
		spin.step = SHARE_STEP
		spin.suffix = "%"
		spin.set_value_no_signal(snappedf(share, SHARE_STEP))
		spin.tooltip_text = "INVEST_SHARE_TOOLTIP"
		_ownership_grid.add_child(spin)
		_sector_spins[sector_id] = spin
		var apply := Button.new()
		apply.text = "ECONOMY_APPLY"
		apply.focus_mode = Control.FOCUS_NONE
		apply.pressed.connect(func() -> void: _on_ownership_pressed(sector_id))
		spin.value_changed.connect(func(value: float) -> void:
			apply.tooltip_text = _operation_text(country, state, sector_id, value / EconomyModel.PERCENT))
		apply.tooltip_text = _operation_text(country, state, sector_id, spin.value / EconomyModel.PERCENT)
		_ownership_grid.add_child(apply)


## « Rachat : 120 Md$ (dette) » ou « Vente : 96 Md$ (remboursement) ».
func _operation_text(country: CountryState, state: SimState, sector_id: String, share: float) -> String:
	var change := share - float(country.economy.investment.public_ownership.get(sector_id, 0.0))
	var value := InvestmentSystem.ownership_value(country, state, sector_id, change)
	var locale := Localization.get_locale()
	if change > 0.0:
		return tr("INVEST_BUYBACK_VALUE") % NumberFormat.integer(roundi(value), locale)
	if change < 0.0:
		return tr("INVEST_SALE_VALUE") % NumberFormat.integer(roundi(value
			* float(state.investment_settings.get("privatization_discount", 1.0))), locale)
	return ""


func _fill_fdi(country: CountryState) -> void:
	var investment := country.economy.investment
	var locale := Localization.get_locale()
	_add_row(_fdi_grid, "INVEST_FDI_INFLOW", tr("ECONOMY_GDP_SHARE_VALUE") % NumberFormat.decimal(investment.fdi_inflow, 2, locale))
	_add_row(_fdi_grid, "INVEST_FDI_START", tr("ECONOMY_GDP_SHARE_VALUE") % NumberFormat.decimal(investment.start_fdi_inflow, 2,
		locale))
	_add_row(_fdi_grid, "INVEST_FDI_POLICY", tr("INVEST_POLICY_%s" % investment.fdi_policy.to_upper()))
	if investment.expropriation_months > 0:
		_add_row(_fdi_grid, "INVEST_EXPROPRIATION", tr("INVEST_EXPROPRIATION_VALUE") % investment.expropriation_months)
	_policy_option.clear()
	for policy: String in InvestmentState.POLICIES:
		_policy_option.add_item(tr("INVEST_POLICY_%s" % policy.to_upper()))
	_policy_option.select(InvestmentState.POLICIES.find(investment.fdi_policy))


func _fill_fund(country: CountryState, state: SimState) -> void:
	var investment := country.economy.investment
	var locale := Localization.get_locale()
	_add_row(_fund_grid, "INVEST_FUND_ASSETS", tr("COUNTRY_INFO_GDP_VALUE") % NumberFormat.integer(roundi(investment.sovereign_fund),
		locale))
	_add_row(_fund_grid, "INVEST_FUND_RETURN", tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(
		float(state.investment_settings.get("fund_return", 0.0)), 1, locale))
	_fund_spin.max_value = maxf(investment.sovereign_fund, TradeSystem.current_gdp(state, country.tag))
	_withdraw_button.disabled = investment.sovereign_fund <= 0.0


func _on_ownership_pressed(sector_id: String) -> void:
	var spin: SpinBox = _sector_spins.get(sector_id)
	var current := float(GameState.sim.get_country(str(GameState.sim.player_tag)).economy.investment.public_ownership.get(
		sector_id, 0.0)) * EconomyModel.PERCENT
	# Un clic sans changement (valeur arrondie au point près) ne fait rien.
	if spin != null and not is_equal_approx(spin.value, snappedf(current, SHARE_STEP)):
		_submit(SetOwnershipCommand.new(GameState.sim.player_tag, sector_id, spin.value / EconomyModel.PERCENT,
			not _expropriate_check.button_pressed))


func _on_policy_pressed() -> void:
	var index := _policy_option.selected
	if index >= 0:
		_submit(SetFdiPolicyCommand.new(GameState.sim.player_tag, InvestmentState.POLICIES[index]))


func _submit(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


func _value(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	return label

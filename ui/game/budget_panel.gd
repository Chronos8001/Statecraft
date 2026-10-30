class_name BudgetPanel
extends InfoPanel
## Panneau Budget du pays joué : impôts (dont les tranches de l'impôt sur le revenu), dépenses par poste
## en % du PIB, création monétaire. Les réglages forment un brouillon : recettes, solde et effets attendus
## sont recalculés en direct, et rien ne change avant « Appliquer ».

const DECIMALS := 1
const SPIN_WIDTH := 84.0
const AMOUNT_WIDTH := 96.0
const BRACKET_STEP := 0.5
const RATE_STEP := 0.5
const SPENDING_STEP := 0.1
const CARBON_STEP := 5.0
const ECONOMIC_KEYS := ["growth", "unemployment", "inflation"]
const PENDING_KEYS := ["stability", "research", "military", "influence"]
const POSITIVE_COLOR := Color(0.55, 0.85, 0.55)
const NEGATIVE_COLOR := Color(0.95, 0.5, 0.45)

var _bracket_spins: Array[SpinBox] = []
var _tax_spins: Dictionary = {}
var _spending_spins: Dictionary = {}
var _revenue_labels: Dictionary = {}
var _spending_labels: Dictionary = {}
var _printing_spin: SpinBox
var _building: bool = false

@onready var _flag: TextureRect = %FlagRect
@onready var _name_label: Label = %NameLabel
@onready var _taxes_grid: GridContainer = %TaxesGrid
@onready var _spending_grid: GridContainer = %SpendingGrid
@onready var _totals_grid: GridContainer = %TotalsGrid
@onready var _effects_grid: GridContainer = %EffectsGrid
@onready var _apply_button: Button = %ApplyButton
@onready var _reset_button: Button = %ResetButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_apply_button.pressed.connect(_on_apply_pressed)
	_reset_button.pressed.connect(refresh)
	EventBus.locale_changed.connect(func(_locale: String) -> void: refresh())
	EventBus.month_passed.connect(func(_date: GameDate) -> void: _update_preview())
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		visible = true
		refresh()


## Recrée les lignes à partir du budget en vigueur (efface le brouillon).
func refresh() -> void:
	if not visible:
		return
	var country := _player_country()
	_building = true
	_clear_rows(_taxes_grid)
	_clear_rows(_spending_grid)
	_bracket_spins.clear()
	_tax_spins.clear()
	_spending_spins.clear()
	_revenue_labels.clear()
	_spending_labels.clear()
	_printing_spin = null
	if country == null:
		_name_label.text = tr("TOPBAR_NO_COUNTRY")
		_building = false
		return
	var data := DataLoader.get_entry("countries", country.tag)
	_flag.texture = CountryFlags.texture_for(CountryFlags.path_for(country.tag, data),
		Color.html(str(data.get("color", "#808080"))))
	_name_label.text = tr(str(data.get("name_key", country.tag)))
	_build_taxes(country.economy.budget)
	_build_spending(country.economy.budget)
	_building = false
	_update_preview()


func _build_taxes(budget: BudgetState) -> void:
	var taxes := DataLoader.get_category("budget_taxes")
	for tax_id: String in taxes.keys():
		var definition: Dictionary = taxes[tax_id]
		var name_label := _grid_label(str(definition.get("name_key", tax_id)))
		_taxes_grid.add_child(name_label)
		if tax_id == BudgetModel.INCOME_TAX:
			var row := HBoxContainer.new()
			for index: int in budget.income_brackets.size():
				var spin := _spin(budget.income_brackets[index], float(definition["min"]), float(definition["max"]),
					BRACKET_STEP, "%")
				spin.custom_minimum_size.x = SPIN_WIDTH * 0.8
				spin.tooltip_text = tr("BUDGET_BRACKET_TOOLTIP") % (index + 1)
				row.add_child(spin)
				_bracket_spins.append(spin)
			_taxes_grid.add_child(row)
		else:
			var unit := "$/t" if str(definition.get("unit", "")) == "dollars_per_ton" else "%"
			var step := CARBON_STEP if unit == "$/t" else RATE_STEP
			var spin := _spin(float(budget.tax_rates.get(tax_id, 0.0)), float(definition["min"]), float(definition["max"]),
				step, unit)
			_tax_spins[tax_id] = spin
			_taxes_grid.add_child(spin)
		var amount := _amount_label()
		_revenue_labels[tax_id] = amount
		_taxes_grid.add_child(amount)


func _build_spending(budget: BudgetState) -> void:
	var lines := DataLoader.get_category("budget_spending")
	for line_id: String in lines.keys():
		var definition: Dictionary = lines[line_id]
		_spending_grid.add_child(_grid_label(str(definition.get("name_key", line_id))))
		var spin := _spin(float(budget.spending.get(line_id, 0.0)), 0.0, float(definition["max"]), SPENDING_STEP, "%")
		spin.tooltip_text = "BUDGET_SPENDING_TOOLTIP"
		_spending_spins[line_id] = spin
		_spending_grid.add_child(spin)
		var amount := _amount_label()
		_spending_labels[line_id] = amount
		_spending_grid.add_child(amount)
	if BudgetSystem.can_print_money(GameState.sim, str(GameState.sim.player_tag)):
		_spending_grid.add_child(_grid_label("BUDGET_MONETARY_FINANCING"))
		var settings: Dictionary = GameState.sim.budget_definitions.get("settings", {})
		_printing_spin = _spin(budget.monetary_financing, 0.0, float(settings.get("max_monetary_financing", 0.0)),
			SPENDING_STEP, "%")
		_printing_spin.tooltip_text = "BUDGET_MONETARY_FINANCING_TOOLTIP"
		_spending_grid.add_child(_printing_spin)
		_spending_grid.add_child(_amount_label())


## Brouillon : copie du budget en vigueur avec les valeurs saisies.
func _draft(current: BudgetState) -> BudgetState:
	var draft := BudgetState.new()
	draft.start_income_brackets = current.start_income_brackets
	draft.start_tax_rates = current.start_tax_rates
	draft.start_spending = current.start_spending
	draft.revenue_per_point = current.revenue_per_point
	draft.income_brackets = current.income_brackets.duplicate()
	for index: int in mini(_bracket_spins.size(), draft.income_brackets.size()):
		draft.income_brackets[index] = _bracket_spins[index].value
	draft.tax_rates = current.tax_rates.duplicate()
	for tax_id: Variant in _tax_spins.keys():
		draft.tax_rates[tax_id] = (_tax_spins[tax_id] as SpinBox).value
	draft.spending = current.spending.duplicate()
	for line_id: Variant in _spending_spins.keys():
		draft.spending[line_id] = (_spending_spins[line_id] as SpinBox).value
	draft.monetary_financing = _printing_spin.value if _printing_spin != null else current.monetary_financing
	return draft


func _update_preview() -> void:
	if not visible or _building:
		return
	var country := _player_country()
	if country == null:
		return
	var economy := country.economy
	var currency := GameState.sim.get_currency(economy.currency)
	if currency == null:
		return
	var definitions := GameState.sim.budget_definitions
	var settings: Dictionary = definitions.get("settings", {})
	var draft := _draft(economy.budget)
	var revenues := BudgetModel.revenues(draft, definitions.get("taxes", {}), settings.get("income_bracket_weights", []))
	draft.revenues = revenues
	var gdp := economy.gdp_usd(currency)
	for tax_id: Variant in _revenue_labels.keys():
		(_revenue_labels[tax_id] as Label).text = _amount(float(revenues.get(tax_id, 0.0)), gdp)
	for line_id: Variant in _spending_labels.keys():
		(_spending_labels[line_id] as Label).text = _amount(float(draft.spending[line_id]), gdp)
	var interest := economy.interest_burden(currency)
	var balance := draft.total_revenue() - draft.total_spending() + economy.austerity - interest
	_clear_rows(_totals_grid)
	_add_row(_totals_grid, "BUDGET_TOTAL_REVENUE", _amount(draft.total_revenue(), gdp))
	_add_row(_totals_grid, "BUDGET_TOTAL_SPENDING", _amount(draft.total_spending(), gdp))
	_add_row(_totals_grid, "ECONOMY_INTEREST", _amount(interest, gdp))
	if economy.austerity > 0.0:
		_add_row(_totals_grid, "BUDGET_IMF_EFFORT", _amount(economy.austerity, gdp))
	_add_row(_totals_grid, "ECONOMY_BUDGET_BALANCE", _amount(balance, gdp))
	_add_row(_totals_grid, "COUNTRY_INFO_DEBT", tr("COUNTRY_INFO_DEBT_VALUE") % roundi(economy.debt_ratio(currency) * 100.0))
	_show_effects(BudgetModel.effects(draft, definitions.get("taxes", {}), definitions.get("spending", {}), settings))


## Effets attendus par rapport au budget de départ ; ceux qui ne jouent pas encore sont signalés.
func _show_effects(effects: Dictionary) -> void:
	_clear_rows(_effects_grid)
	for key: String in ECONOMIC_KEYS:
		_add_effect("BUDGET_EFFECT_%s" % key.to_upper(), float(effects.get(key, 0.0)), key != "growth")
	for key: String in PENDING_KEYS:
		_add_effect("BUDGET_EFFECT_%s" % key.to_upper(), float(effects.get(key, 0.0)), false, true)
	var groups: Dictionary = effects.get(BudgetModel.GROUPS, {})
	var names := DataLoader.get_category("social_groups")
	for group_id: String in names.keys():
		if groups.has(group_id):
			_add_effect(str((names[group_id] as Dictionary).get("name_key", group_id)), float(groups[group_id]), false, true)


## inverted : une hausse est mauvaise (chômage, inflation). pending : effet appliqué par une étape future.
func _add_effect(label_key: String, value: float, inverted: bool, pending: bool = false) -> void:
	if is_zero_approx(snappedf(value, 0.01)):
		return
	var label := _grid_label(label_key)
	_effects_grid.add_child(label)
	var value_label := Label.new()
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var text := ("+" if value > 0.0 else "") + NumberFormat.decimal(value, 2, Localization.get_locale())
	value_label.text = tr("BUDGET_EFFECT_PENDING") % text if pending else text
	var good := (value > 0.0) != inverted
	value_label.add_theme_color_override("font_color", POSITIVE_COLOR if good else NEGATIVE_COLOR)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_grid.add_child(value_label)


func _on_apply_pressed() -> void:
	var country := _player_country()
	if country == null:
		return
	var draft := _draft(country.economy.budget)
	var command := SetBudgetCommand.new(GameState.sim.player_tag, draft.income_brackets, draft.tax_rates,
		draft.spending, draft.monetary_financing)
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


func _player_country() -> CountryState:
	return GameState.sim.get_country(str(GameState.sim.player_tag))


func _spin(value: float, minimum: float, maximum: float, step: float, suffix: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.suffix = suffix
	spin.custom_minimum_size.x = SPIN_WIDTH
	spin.size_flags_horizontal = Control.SIZE_SHRINK_END
	spin.set_value_no_signal(value)
	spin.value_changed.connect(func(_value: float) -> void: _update_preview())
	return spin


func _grid_label(key: String) -> Label:
	var label := Label.new()
	label.text = key
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _amount_label() -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.custom_minimum_size.x = AMOUNT_WIDTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


## « 2,5 % · 76 Md$ » : part du PIB et montant annuel.
func _amount(share: float, gdp_usd: float) -> String:
	var locale := Localization.get_locale()
	return tr("BUDGET_AMOUNT_VALUE") % [NumberFormat.decimal(share, DECIMALS, locale),
		NumberFormat.integer(roundi(share / 100.0 * gdp_usd), locale)]

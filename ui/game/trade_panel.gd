class_name TradePanel
extends InfoPanel
## Panneau Commerce du pays joué : principaux partenaires, dépendances (fournisseurs de chaque ressource
## importée), accords commerciaux, et mesures : surtaxe, embargo, sortie d'un accord.

const TOP_PARTNERS := 12
const TOP_SUPPLIERS := 3
const PARTNER_COLUMNS := 5
const SURCHARGE_STEP := 5.0
const ALERT_COLOR := Color(0.95, 0.5, 0.45)
const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const PARTNER_HEADERS := ["TRADE_PARTNER", "TRADE_VOLUME", "TRADE_SHARE", "TRADE_OUR_TARIFF", "TRADE_THEIR_TARIFF"]

var _target_tags: Array[String] = []
var _goods_ids: Array[String] = []

@onready var _partners_grid: GridContainer = %PartnersGrid
@onready var _dependencies_grid: GridContainer = %DependenciesGrid
@onready var _agreements_box: VBoxContainer = %AgreementsBox
@onready var _measures_box: VBoxContainer = %MeasuresBox
@onready var _target_option: OptionButton = %TargetOption
@onready var _surcharge_spin: SpinBox = %SurchargeSpin
@onready var _surcharge_button: Button = %SurchargeButton
@onready var _goods_option: OptionButton = %GoodsOption
@onready var _embargo_button: Button = %EmbargoButton
@onready var _lift_button: Button = %LiftButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_partners_grid.columns = PARTNER_COLUMNS
	_surcharge_spin.step = SURCHARGE_STEP
	_surcharge_button.pressed.connect(_on_surcharge_pressed)
	_embargo_button.pressed.connect(func() -> void: _submit_embargo(true))
	_lift_button.pressed.connect(func() -> void: _submit_embargo(false))
	_target_option.item_selected.connect(func(_index: int) -> void: _sync_measure_controls())
	_goods_option.item_selected.connect(func(_index: int) -> void: _sync_measure_controls())
	EventBus.locale_changed.connect(func(_locale: String) -> void: refresh())
	EventBus.month_passed.connect(func(_date: GameDate) -> void: refresh())
	EventBus.command_executed.connect(func(_command: Command) -> void: refresh())
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		visible = true
		_fill_options()
		refresh()


func refresh() -> void:
	if not visible:
		return
	var state := GameState.sim
	var tag := str(state.player_tag)
	_clear_rows(_partners_grid)
	_clear_rows(_dependencies_grid)
	_clear_box(_agreements_box)
	_clear_box(_measures_box)
	if state.get_country(tag) == null or state.trade.start_flows.is_empty():
		return
	_fill_partners(state, tag)
	_fill_dependencies(state, tag)
	_fill_agreements(state, tag)
	_fill_measures(state, tag)
	_sync_measure_controls()


func _fill_partners(state: SimState, tag: String) -> void:
	for key: String in PARTNER_HEADERS:
		_partners_grid.add_child(_header(key))
	var locale := Localization.get_locale()
	var total := TradeSystem.total_trade(state, tag)
	for entry: Array in TradeSystem.top_partners(state, tag, TOP_PARTNERS):
		var partner := str(entry[0])
		var amount := float(entry[1])
		var name_label := _value(_country_name(partner))
		if state.trade.trade_blocked(tag, partner):
			name_label.add_theme_color_override("font_color", ALERT_COLOR)
		_partners_grid.add_child(name_label)
		_partners_grid.add_child(_value(tr("COUNTRY_INFO_GDP_VALUE") % NumberFormat.integer(roundi(amount), locale)))
		_partners_grid.add_child(_value(tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(
			amount / total * EconomyModel.PERCENT if total > 0.0 else 0.0, 1, locale)))
		_partners_grid.add_child(_value(_tariff_text(state, partner, tag)))
		_partners_grid.add_child(_value(_tariff_text(state, tag, partner)))


## Droit appliqué par l'importateur aux produits de l'exportateur.
func _tariff_text(state: SimState, exporter: String, importer: String) -> String:
	if state.trade.trade_blocked(exporter, importer):
		return tr("TRADE_EMBARGO")
	var rate := TradeModel.tariff(state.trade, exporter, importer, TradeSystem.base_tariff(state, importer),
		state.trade_settings)
	return tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(rate, 1, Localization.get_locale())


## Pour chaque ressource que le pays importe : part importée et principaux fournisseurs.
func _fill_dependencies(state: SimState, tag: String) -> void:
	var resources := state.get_country(tag).resources
	var definitions := DataLoader.get_category("resources")
	var locale := Localization.get_locale()
	for resource_id: String in definitions.keys():
		if not state.markets.has(resource_id):
			continue
		var used := float(resources.consumption.get(resource_id, 0.0))
		var imported := used - float(resources.production.get(resource_id, 0.0))
		if used <= 0.0 or imported <= 0.0:
			continue
		var label := _value(tr(str((definitions[resource_id] as Dictionary).get("name_key", resource_id))))
		_dependencies_grid.add_child(label)
		var shares := TradeModel.supplier_shares(state, tag, resource_id)
		var entries: Array = []
		for supplier: Variant in shares.keys():
			entries.append([str(supplier), float(shares[supplier])])
		entries.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
		var parts := PackedStringArray()
		for entry: Array in entries.slice(0, TOP_SUPPLIERS):
			parts.append(tr("MARKETS_PRODUCER_VALUE") % [str(entry[0]), NumberFormat.decimal(float(entry[1])
				* EconomyModel.PERCENT, 0, locale)])
		var dependency := imported / used * EconomyModel.PERCENT
		var text := tr("TRADE_DEPENDENCY_VALUE") % [NumberFormat.decimal(dependency, 0, locale), LIST_SEPARATOR.join(parts)]
		var value := _value(text)
		if not entries.is_empty() and float(entries[0][1]) >= 0.5:
			value.add_theme_color_override("font_color", ALERT_COLOR)
		_dependencies_grid.add_child(value)


func _fill_agreements(state: SimState, tag: String) -> void:
	var names := DataLoader.get_category("trade_agreements")
	var agreements := state.trade.agreements_of(tag)
	if agreements.is_empty():
		_agreements_box.add_child(_value(tr("TRADE_NO_AGREEMENT")))
	for agreement_id: String in agreements:
		var row := HBoxContainer.new()
		var definition: Dictionary = names.get(agreement_id, {})
		var members: Array = (state.trade.agreements[agreement_id] as Dictionary)["members"]
		var label := _value(tr("TRADE_AGREEMENT_VALUE") % [tr(str(definition.get("name_key", agreement_id))),
			members.size()])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var leave := Button.new()
		leave.text = "TRADE_LEAVE"
		leave.tooltip_text = "TRADE_LEAVE_TOOLTIP"
		leave.focus_mode = Control.FOCUS_NONE
		leave.pressed.connect(func() -> void: _submit(LeaveAgreementCommand.new(state.player_tag, agreement_id)))
		row.add_child(leave)
		_agreements_box.add_child(row)


## Surtaxes et embargos en vigueur, dans les deux sens.
func _fill_measures(state: SimState, tag: String) -> void:
	var trade := state.trade
	var locale := Localization.get_locale()
	var lines := PackedStringArray()
	var ours: Dictionary = trade.surcharges.get(tag, {})
	for target: Variant in ours.keys():
		if float(ours[target]) > 0.0:
			var who := tr("TRADE_EVERYONE") if str(target) == "default" else _country_name(str(target))
			lines.append(tr("TRADE_OUR_SURCHARGE") % [who, NumberFormat.decimal(float(ours[target]), 0, locale)])
	for other: String in trade.surcharges.keys():
		var table: Dictionary = trade.surcharges[other]
		var rate := float(table.get(tag, table.get("default", 0.0)))
		if other != tag and rate > 0.0:
			lines.append(tr("TRADE_THEIR_SURCHARGE") % [_country_name(other), NumberFormat.decimal(rate, 0, locale)])
	for source: String in trade.embargoes.keys():
		for target: String in (trade.embargoes[source] as Dictionary).keys():
			if source != tag and target != tag:
				continue
			var goods := _goods_text(trade.embargo_goods(source, target))
			var key := "TRADE_OUR_EMBARGO" if source == tag else "TRADE_THEIR_EMBARGO"
			lines.append(tr(key) % [_country_name(target if source == tag else source), goods])
	if lines.is_empty():
		lines.append(tr("TRADE_NO_MEASURE"))
	for line: String in lines:
		var label := _value(line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_measures_box.add_child(label)


func _goods_text(goods: Array) -> String:
	if goods.has(TradeState.ALL_GOODS):
		return tr("TRADE_ALL_GOODS")
	var names := PackedStringArray()
	var definitions := DataLoader.get_category("resources")
	for resource_id: Variant in goods:
		names.append(tr(str((definitions.get(resource_id, {}) as Dictionary).get("name_key", resource_id))))
	return LIST_SEPARATOR.join(names)


## Listes des pays (triés par nom) et des marchandises visables.
func _fill_options() -> void:
	var countries := DataLoader.get_category("countries")
	var player := str(GameState.sim.player_tag)
	var entries: Array = []
	for tag: String in countries.keys():
		if tag != player:
			var country_name := _country_name(tag)
			entries.append([CountrySelectionPanel.fold(country_name), tag, country_name])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	_target_option.clear()
	_target_tags.clear()
	for entry: Array in entries:
		_target_option.add_item(str(entry[2]))
		_target_tags.append(str(entry[1]))
	_goods_option.clear()
	_goods_ids.clear()
	_goods_option.add_item(tr("TRADE_ALL_GOODS"))
	_goods_ids.append(TradeState.ALL_GOODS)
	var resources := DataLoader.get_category("resources")
	for resource_id: String in resources.keys():
		if GameState.sim.markets.has(resource_id):
			_goods_option.add_item(tr(str((resources[resource_id] as Dictionary).get("name_key", resource_id))))
			_goods_ids.append(resource_id)


func _selected_target() -> String:
	var index := _target_option.selected
	return _target_tags[index] if index >= 0 and index < _target_tags.size() else ""


func _selected_goods() -> String:
	var index := _goods_option.selected
	return _goods_ids[index] if index >= 0 and index < _goods_ids.size() else TradeState.ALL_GOODS


## Valeurs et boutons qui correspondent au pays et à la marchandise choisis.
func _sync_measure_controls() -> void:
	var state := GameState.sim
	var player := str(state.player_tag)
	var target := _selected_target()
	if target.is_empty():
		return
	var table: Dictionary = state.trade.surcharges.get(player, {})
	_surcharge_spin.max_value = float(state.trade_settings.get("embargo_tariff", 100.0))
	_surcharge_spin.set_value_no_signal(float(table.get(target, table.get("default", 0.0))))
	var goods := _selected_goods()
	_embargo_button.disabled = not SetEmbargoCommand.new(state.player_tag, target, goods, true).can_execute(state)
	_lift_button.disabled = not SetEmbargoCommand.new(state.player_tag, target, goods, false).can_execute(state)


func _on_surcharge_pressed() -> void:
	_submit(SetTariffCommand.new(GameState.sim.player_tag, _selected_target(), _surcharge_spin.value))


func _submit_embargo(active: bool) -> void:
	_submit(SetEmbargoCommand.new(GameState.sim.player_tag, _selected_target(), _selected_goods(), active))


func _submit(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


func _country_name(tag: String) -> String:
	return tr(str(DataLoader.get_entry("countries", tag).get("name_key", tag)))


func _header(key: String) -> Label:
	var label := Label.new()
	label.text = key
	label.add_theme_color_override("font_color", HEADER_COLOR)
	return label


func _value(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	return label


func _clear_box(box: Container) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()

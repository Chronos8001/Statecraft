class_name MarketsPanel
extends InfoPanel
## Panneau Marchés : prix mondial de chaque ressource, variation depuis janvier 2026, grands producteurs,
## et situation du pays joué (production, consommation, autosuffisance, pénurie, stress hydrique).
## En version de développement, des cases permettent de fermer les détroits pour tester les chocs.

const COLUMNS := 7
const TOP_PRODUCERS := 3
const PRICE_DECIMALS := 2
const QUANTITY_DECIMALS := 1
const UP_COLOR := Color(0.95, 0.6, 0.45)
const DOWN_COLOR := Color(0.55, 0.85, 0.55)
const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const HEADER_KEYS := ["MARKETS_RESOURCE", "MARKETS_PRICE", "MARKETS_CHANGE", "MARKETS_WORLD_PRODUCTION",
	"MARKETS_TOP_PRODUCERS", "MARKETS_OWN_BALANCE", "MARKETS_SELF_SUFFICIENCY"]

@onready var _grid: GridContainer = %MarketsGrid
@onready var _water_label: Label = %WaterLabel
@onready var _debug_box: VBoxContainer = %DebugBox
@onready var _straits_box: HFlowContainer = %StraitsBox
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_grid.columns = COLUMNS
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
	_clear_rows(_grid)
	for key: String in HEADER_KEYS:
		var header := Label.new()
		header.text = key
		header.add_theme_color_override("font_color", HEADER_COLOR)
		_grid.add_child(header)
	var resources := DataLoader.get_category("resources")
	var country := state.get_country(str(state.player_tag))
	for resource_id: String in resources.keys():
		var market: MarketState = state.markets.get(resource_id)
		if market != null:
			_add_market_row(market, resources[resource_id], country, state)
	_update_water(country)
	_update_debug(state)


func _add_market_row(market: MarketState, resource: Dictionary, country: CountryState, state: SimState) -> void:
	var locale := Localization.get_locale()
	var definition: Dictionary = resource.get("market", {})
	var name_label := Label.new()
	name_label.text = str(resource.get("name_key", market.resource_id))
	name_label.add_theme_color_override("font_color", Color.html(str(resource.get("color", "#FFFFFF"))).lightened(0.3))
	_grid.add_child(name_label)
	_grid.add_child(_value(tr(str(definition.get("price_unit_key", ""))) % NumberFormat.decimal(market.price,
		PRICE_DECIMALS if market.price < 100.0 else 0, locale)))
	var change := (market.price_ratio() - 1.0) * EconomyModel.PERCENT
	var change_label := _value(("+" if change > 0.0 else "") + tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(change,
		QUANTITY_DECIMALS, locale))
	if absf(change) >= 1.0:
		change_label.add_theme_color_override("font_color", UP_COLOR if change > 0.0 else DOWN_COLOR)
	_grid.add_child(change_label)
	var unit := tr(str(definition.get("quantity_unit_key", "")))
	_grid.add_child(_value(unit % NumberFormat.decimal(market.supply, QUANTITY_DECIMALS, locale)))
	_grid.add_child(_value(_top_producers(market.resource_id, state)))
	if country == null:
		_grid.add_child(_value(tr("TOPBAR_UNKNOWN")))
		_grid.add_child(_value(tr("TOPBAR_UNKNOWN")))
		return
	var resources := country.resources
	var produced := float(resources.production.get(market.resource_id, 0.0))
	var used := float(resources.consumption.get(market.resource_id, 0.0))
	_grid.add_child(_value(tr("MARKETS_BALANCE_VALUE") % [NumberFormat.decimal(produced, QUANTITY_DECIMALS, locale),
		NumberFormat.decimal(used, QUANTITY_DECIMALS, locale)]))
	var sufficiency := resources.self_sufficiency(market.resource_id)
	var text := tr("TOPBAR_UNKNOWN") if sufficiency < 0.0 else tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(
		sufficiency * EconomyModel.PERCENT, 0, locale)
	var shortage := float(resources.shortage.get(market.resource_id, 0.0))
	if shortage >= 0.005:
		text += " " + tr("MARKETS_SHORTAGE_VALUE") % NumberFormat.decimal(shortage * EconomyModel.PERCENT, 0, locale)
	var sufficiency_label := _value(text)
	if sufficiency >= 0.0 and sufficiency < 1.0:
		sufficiency_label.add_theme_color_override("font_color", UP_COLOR)
	_grid.add_child(sufficiency_label)


## Les trois premiers producteurs du mois, avec leur part de l'offre mondiale.
func _top_producers(resource_id: String, state: SimState) -> String:
	var market: MarketState = state.markets[resource_id]
	var producers: Array = []
	for tag: String in state.countries.keys():
		var amount := float((state.countries[tag] as CountryState).resources.production.get(resource_id, 0.0))
		if amount > 0.0:
			producers.append([amount, tag])
	producers.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var parts := PackedStringArray()
	for entry: Array in producers.slice(0, TOP_PRODUCERS):
		var share := float(entry[0]) / market.supply * EconomyModel.PERCENT if market.supply > 0.0 else 0.0
		parts.append(tr("MARKETS_PRODUCER_VALUE") % [str(entry[1]), NumberFormat.decimal(share, 0,
			Localization.get_locale())])
	return LIST_SEPARATOR.join(parts)


func _update_water(country: CountryState) -> void:
	if country == null:
		_water_label.text = ""
		return
	var stress := country.resources.water_withdrawal_ratio * EconomyModel.PERCENT
	var threshold := float(DataLoader.get_define("resources.water_stress_threshold", 0.0)) * EconomyModel.PERCENT
	var key := "MARKETS_WATER_STRESSED" if stress >= threshold else "MARKETS_WATER_OK"
	_water_label.text = tr(key) % NumberFormat.decimal(stress, 0, Localization.get_locale())


## Fermeture des détroits, en version de développement seulement.
func _update_debug(state: SimState) -> void:
	_debug_box.visible = OS.is_debug_build()
	if not _debug_box.visible:
		return
	for child: Node in _straits_box.get_children():
		_straits_box.remove_child(child)
		child.queue_free()
	var straits := DataLoader.get_category("straits")
	for strait_id: String in state.resource_definitions.get("straits", {}).keys():
		if not ((straits.get(strait_id, {}) as Dictionary).has("trade")):
			continue
		var check := CheckBox.new()
		check.text = str((straits[strait_id] as Dictionary).get("name_key", strait_id))
		check.focus_mode = Control.FOCUS_NONE
		check.set_pressed_no_signal(state.closed_straits.has(strait_id))
		check.toggled.connect(func(pressed: bool) -> void:
			if GameState.submit_command(SetStraitClosedCommand.new(strait_id, pressed)) and GameClock.is_paused:
				GameState.process_commands())
		_straits_box.add_child(check)


func _value(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	return label

class_name TradeSystem
extends SimSystem
## Commerce, une fois par mois, après les ressources et avant le budget.
## Les droits de douane effectifs (accords, surtaxes, embargos) ne sont recalculés que lorsqu'ils peuvent
## avoir changé ; seules les paires de pays dont les droits diffèrent du départ ont des effets :
## inflation chez l'importateur, pertes de croissance des deux côtés, recettes douanières en plus ou en moins.

const PRIORITY := -15
const EVENT_AGREEMENT_LEFT := &"agreement_left"


func get_id() -> StringName:
	return &"trade"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.trade.start_flows.is_empty():
		return
	update_trade(state)


static func update_trade(state: SimState) -> void:
	var trade := state.trade
	for tag: String in state.countries.keys():
		if not is_equal_approx(base_tariff(state, tag), float(trade.base_tariffs.get(tag, -1.0))):
			trade.dirty = true
	if trade.dirty:
		refresh_tariff_changes(state)
	apply_effects(state)


## Écarts de droits de douane avec le départ, pour chaque paire de partenaires.
static func refresh_tariff_changes(state: SimState) -> void:
	var trade := state.trade
	var settings := state.trade_settings
	trade.tariff_changes.clear()
	for tag: String in state.countries.keys():
		trade.base_tariffs[tag] = base_tariff(state, tag)
	for exporter: String in trade.start_flows.keys():
		var start_row: Dictionary = trade.start_tariffs.get(exporter, {})
		var changes: Dictionary = {}
		for importer: String in (trade.start_flows[exporter] as Dictionary).keys():
			var change := TradeModel.tariff(trade, exporter, importer, float(trade.base_tariffs.get(importer, 0.0)),
				settings) - float(start_row.get(importer, 0.0))
			if not is_zero_approx(change):
				changes[importer] = change
		if not changes.is_empty():
			trade.tariff_changes[exporter] = changes
	trade.dirty = false


static func apply_effects(state: SimState) -> void:
	var trade := state.trade
	var settings := state.trade_settings
	var growth: Dictionary = {}
	var inflation: Dictionary = {}
	var customs: Dictionary = {}
	var passthrough := float(settings.get("import_passthrough", 0.0))
	var cost := float(settings.get("tariff_growth_cost", 0.0))
	var collection := float(settings.get("customs_collection", 0.0))
	var exporters: Array = trade.tariff_changes.keys()
	exporters.sort()
	for exporter: String in exporters:
		var changes: Dictionary = trade.tariff_changes[exporter]
		for importer: String in changes.keys():
			var change := float(changes[importer])
			var start := trade.start_flow(exporter, importer)
			var importer_share := start / float(trade.start_gdp[importer])
			var exporter_share := start / float(trade.start_gdp[exporter])
			inflation[importer] = float(inflation.get(importer, 0.0)) + passthrough * importer_share * change
			growth[importer] = float(growth.get(importer, 0.0)) - cost * importer_share * change
			growth[exporter] = float(growth.get(exporter, 0.0)) - cost * exporter_share * change
			var gdp := current_gdp(state, importer)
			if gdp > 0.0:
				customs[importer] = float(customs.get(importer, 0.0)) \
					+ collection * current_flow(state, exporter, importer) / gdp * change
	var limit := float(settings.get("max_economic_effect", INF))
	for tag: String in state.countries.keys():
		var economy := (state.countries[tag] as CountryState).economy
		economy.trade_growth = clampf(float(growth.get(tag, 0.0)), -limit, limit)
		economy.trade_inflation = clampf(float(inflation.get(tag, 0.0)), -limit, limit)
		economy.trade_customs = float(customs.get(tag, 0.0))


## Flux du moment (milliards de dollars par an) : flux de départ, taille des économies, droits de douane.
static func current_flow(state: SimState, exporter: String, importer: String) -> float:
	var trade := state.trade
	var start := trade.start_flow(exporter, importer)
	if start <= 0.0:
		return 0.0
	var size := sqrt(maxf(current_gdp(state, exporter) / float(trade.start_gdp[exporter]), 0.0)
		* maxf(current_gdp(state, importer) / float(trade.start_gdp[importer]), 0.0))
	return TradeModel.adjusted_flow(start, trade.tariff_change(exporter, importer), size, state.trade_settings)


static func current_gdp(state: SimState, tag: String) -> float:
	var economy := state.get_country(tag).economy
	var currency := state.get_currency(economy.currency)
	return economy.gdp_usd(currency) if currency != null else economy.real_gdp


## Droit de douane habituel du pays (taux du budget), appliqué hors accords.
static func base_tariff(state: SimState, tag: String) -> float:
	var country := state.get_country(tag)
	return float(country.economy.budget.tax_rates.get("customs", 0.0)) if country != null else 0.0


## Principaux partenaires (échanges dans les deux sens, en milliards de dollars par an), triés :
## [[partenaire, montant], …].
static func top_partners(state: SimState, tag: String, count: int) -> Array:
	var totals := partner_totals(state, tag)
	var entries: Array = []
	for partner: Variant in totals.keys():
		entries.append([str(partner), float(totals[partner])])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return entries.slice(0, count)


## Échanges du pays avec chaque partenaire (exportations + importations).
static func partner_totals(state: SimState, tag: String) -> Dictionary:
	var trade := state.trade
	var totals: Dictionary = {}
	for partner: Variant in (trade.start_flows.get(tag, {}) as Dictionary).keys():
		totals[partner] = float(totals.get(partner, 0.0)) + current_flow(state, tag, str(partner))
	for exporter: String in trade.start_flows.keys():
		if (trade.start_flows[exporter] as Dictionary).has(tag):
			totals[exporter] = float(totals.get(exporter, 0.0)) + current_flow(state, exporter, tag)
	return totals


static func total_trade(state: SimState, tag: String) -> float:
	var total := 0.0
	for amount: Variant in partner_totals(state, tag).values():
		total += float(amount)
	return total

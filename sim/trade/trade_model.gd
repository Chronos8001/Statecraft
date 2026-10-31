class_name TradeModel
extends RefCounted
## Formules du commerce. Les flux de départ viennent des données (modèle gravitaire calculé par
## tools/country_gen/generate_trade.py) ; le jeu n'en fait varier que la taille et les droits de douane.

const KIND_ORDER := ["customs_union", "free_trade", "partial"]
const PARTIAL_DISCOUNT := 0.5
const PERCENT := 100.0


## Droit de douane appliqué par l'importateur au produit de l'exportateur (points de %).
## Un accord de libre-échange ou une union douanière supprime le droit habituel ; un accord partiel le divise.
static func tariff(trade: TradeState, exporter: String, importer: String, base_rate: float,
		settings: Dictionary) -> float:
	if trade.trade_blocked(exporter, importer):
		return float(settings.get("embargo_tariff", 0.0))
	var kind := trade.agreement_kind(exporter, importer)
	var base := base_rate
	if kind == "customs_union" or kind == "free_trade":
		base = 0.0
	elif kind == "partial":
		base *= PARTIAL_DISCOUNT
	return base + trade.surcharge(importer, exporter)


## Flux après un changement de droits de douane (élasticité du commerce, hausse plafonnée), en suivant la
## taille des deux économies.
static func adjusted_flow(start_flow: float, tariff_change: float, size_factor: float, settings: Dictionary) -> float:
	var factor := exp(-float(settings.get("trade_elasticity", 0.0)) * tariff_change / PERCENT)
	return start_flow * size_factor * minf(factor, float(settings.get("max_trade_gain", INF)))


## Fournisseurs d'une ressource pour un importateur : exportateurs nets pondérés par leurs liens
## commerciaux avec lui. respect_embargoes = false : parts « normales », sans tenir compte des embargos.
## Parts qui somment à 1.
static func supplier_shares(state: SimState, importer: String, resource_id: String,
		respect_embargoes: bool = true) -> Dictionary:
	var trade := state.trade
	var weights: Dictionary = {}
	var total := 0.0
	for tag: String in state.countries.keys():
		if tag == importer:
			continue
		var resources: CountryResources = (state.countries[tag] as CountryState).resources
		var surplus := resources.net_exports(resource_id)
		if surplus <= 0.0:
			continue
		if respect_embargoes and (trade.is_embargoed(importer, tag, resource_id)
				or trade.is_embargoed(tag, importer, resource_id)):
			continue
		var link := trade.start_flow(tag, importer) + trade.start_flow(importer, tag) + 0.001
		weights[tag] = surplus * link
		total += surplus * link
	if total > 0.0:
		for tag: Variant in weights.keys():
			weights[tag] = float(weights[tag]) / total
	return weights

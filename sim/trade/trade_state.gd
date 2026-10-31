class_name TradeState
extends RefCounted
## Commerce mondial pendant la partie. Les flux sont directionnels : start_flows[exportateur][importateur],
## en milliards de dollars par an, limités aux principaux partenaires de chaque pays. Les droits de douane
## sont ceux que l'importateur applique.

const ALL_GOODS := "*"

## Flux de départ (données) et droits de douane de départ : [exportateur][importateur].
var start_flows: Dictionary = {}
var start_tariffs: Dictionary = {}
## Écarts de droits de douane avec le départ, seulement pour les paires qui ont changé : [exportateur][importateur].
var tariff_changes: Dictionary = {}
## Droit habituel de chaque pays au dernier calcul (taux « douanes » du budget).
var base_tariffs: Dictionary = {}
## Vrai quand les droits doivent être recalculés (commande, accord quitté, droit habituel modifié).
var dirty: bool = true
## Accords en vigueur : identifiant → {kind, members: Array}.
var agreements: Dictionary = {}
## Surtaxes : surcharges[importateur][exportateur] (points de %) ; clé "default" = tous les autres pays.
var surcharges: Dictionary = {}
## Embargos : embargoes[pays qui l'impose][pays visé] = ressources visées (ALL_GOODS = tout le commerce).
var embargoes: Dictionary = {}
## PIB de départ en dollars.
var start_gdp: Dictionary = {}
var _pair_kinds: Dictionary = {}


func start_flow(exporter: String, importer: String) -> float:
	return float((start_flows.get(exporter, {}) as Dictionary).get(importer, 0.0))


func tariff_change(exporter: String, importer: String) -> float:
	return float((tariff_changes.get(exporter, {}) as Dictionary).get(importer, 0.0))


func surcharge(importer: String, exporter: String) -> float:
	var table: Dictionary = surcharges.get(importer, {})
	return float(table.get(exporter, table.get("default", 0.0)))


## Ressources visées par l'embargo de « source » contre « target » (vide si aucun).
func embargo_goods(source: String, target: String) -> Array:
	return (embargoes.get(source, {}) as Dictionary).get(target, [])


func is_embargoed(source: String, target: String, resource_id: String = ALL_GOODS) -> bool:
	var goods := embargo_goods(source, target)
	return goods.has(ALL_GOODS) or (resource_id != ALL_GOODS and goods.has(resource_id))


## Commerce bloqué dans un sens ou dans l'autre (embargo total).
func trade_blocked(country_a: String, country_b: String) -> bool:
	return is_embargoed(country_a, country_b) or is_embargoed(country_b, country_a)


## Accord le plus intégré entre deux pays ("" si aucun), lu dans le cache des paires.
func agreement_kind(country_a: String, country_b: String) -> String:
	return str((_pair_kinds.get(country_a, {}) as Dictionary).get(country_b, ""))


## Recalcule le cache des paires (au départ et quand un pays quitte un accord). order : du plus intégré au moins.
func refresh_pair_kinds(order: Array) -> void:
	_pair_kinds.clear()
	for agreement: Dictionary in agreements.values():
		var kind := str(agreement["kind"])
		var members: Array = agreement["members"]
		for a: Variant in members:
			if not _pair_kinds.has(a):
				_pair_kinds[a] = {}
			var row: Dictionary = _pair_kinds[a]
			for b: Variant in members:
				if a == b:
					continue
				var current := str(row.get(b, ""))
				if current.is_empty() or order.find(kind) < order.find(current):
					row[b] = kind


func agreements_of(tag: String) -> Array[String]:
	var result: Array[String] = []
	for agreement_id: String in agreements.keys():
		if ((agreements[agreement_id] as Dictionary)["members"] as Array).has(tag):
			result.append(agreement_id)
	result.sort()
	return result

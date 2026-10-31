class_name DiplomacyState
extends RefCounted
## Relations entre pays. Seuls les écarts avec la situation de départ sont gardés et mis à jour chaque mois :
## les 19 701 paires restent légères.
##   relations (-100 à +100, symétriques), confiance (0 à 100, symétrique),
##   opinion publique d'un pays envers un autre (-100 à +100, « A>B » : ce que pense la population de A de B).

const LIMIT := 100.0
const TRUST_MAX := 100.0

## Relations de départ : « A|B » (A < B) → valeur. Paires absentes : 0.
var start_relations: Dictionary = {}
## Écarts avec le départ (relations, confiance, opinion).
var relation_changes: Dictionary = {}
var trust_changes: Dictionary = {}
var opinion_changes: Dictionary = {}
## Réglages : confiance de base et par point de relation, bruit de l'opinion de départ.
var trust_base: float = 50.0
var trust_per_relation: float = 0.0
var opinion_noise: float = 0.0


static func pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func opinion_key(holder: String, about: String) -> String:
	return "%s>%s" % [holder, about]


func start_relation(a: String, b: String) -> float:
	return float(start_relations.get(pair_key(a, b), 0.0))


func relation(a: String, b: String) -> float:
	if a == b:
		return LIMIT
	var key := pair_key(a, b)
	return clampf(float(start_relations.get(key, 0.0)) + float(relation_changes.get(key, 0.0)), -LIMIT, LIMIT)


func trust(a: String, b: String) -> float:
	var key := pair_key(a, b)
	var start := trust_base + trust_per_relation * float(start_relations.get(key, 0.0))
	return clampf(start + float(trust_changes.get(key, 0.0)), 0.0, TRUST_MAX)


## Opinion de la population de holder envers about : relation de départ, nuance propre au pays, écart du moment.
func opinion(holder: String, about: String) -> float:
	var key := opinion_key(holder, about)
	var start := start_relation(holder, about) + opinion_noise * ElectionModel.stable_noise(key)
	return clampf(start + float(opinion_changes.get(key, 0.0)), -LIMIT, LIMIT)


func change_relation(a: String, b: String, amount: float) -> void:
	if a == b or is_zero_approx(amount):
		return
	var key := pair_key(a, b)
	var current := relation(a, b)
	var allowed := clampf(current + amount, -LIMIT, LIMIT) - current
	relation_changes[key] = float(relation_changes.get(key, 0.0)) + allowed


func change_trust(a: String, b: String, amount: float) -> void:
	if a == b or is_zero_approx(amount):
		return
	var key := pair_key(a, b)
	trust_changes[key] = float(trust_changes.get(key, 0.0)) + amount


func change_opinion(holder: String, about: String, amount: float) -> void:
	if holder == about or is_zero_approx(amount):
		return
	var key := opinion_key(holder, about)
	opinion_changes[key] = float(opinion_changes.get(key, 0.0)) + amount

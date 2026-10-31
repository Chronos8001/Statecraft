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
## Traités : identifiant → {type, a, b, initial, year, month} ; prochain identifiant.
var treaties: Dictionary = {}
var next_treaty_id: int = 0
## Bonus de relations des traités signés pendant la partie : « A|B » → points (les traités de 2026 sont déjà
## compris dans les relations de départ).
var treaty_bonus: Dictionary = {}
## Paires sans ambassade : « A|B » → true.
var closed_embassies: Dictionary = {}
## Reconnaissance des États contestés : « A>S » → true quand A reconnaît S.
var recognitions: Dictionary = {}
## Garanties d'indépendance : « G>T » → true quand G garantit T.
var guarantees: Dictionary = {}
## Organisations : identifiant → {kind, name, abbreviation, color, members, custom} ; prochain identifiant
## d'organisation créée en jeu ; Conseil de sécurité : pays → dernière année du mandat (0 : membre permanent).
var organizations: Dictionary = {}
var next_organization_id: int = 0
var security_council: Dictionary = {}
## Sanctions : « S>T » → {measures: [...]} ; effets de référence de 2026 par pays ({growth, inflation}).
var sanctions: Dictionary = {}
var start_sanction_effects: Dictionary = {}
## Programmes d'aide : [{donor, recipient, kind, amount, months_left, total_months, initial, …}] ; armes
## reçues par pays (milliards de dollars, pour l'armée de l'étape 7).
var aid_programs: Array[Dictionary] = []
var arms_received: Dictionary = {}
## Influence : points de chaque pays, influence de départ « H>T » (0 à 100), écarts du moment, bases
## militaires « H>T » (et celles de 2026, déjà comprises dans l'influence de départ).
var influence_points: Dictionary = {}
var start_influence: Dictionary = {}
var influence_changes: Dictionary = {}
var bases: Dictionary = {}
var start_bases: Dictionary = {}
## Revendications territoriales : identifiant → {claimant, target, provinces} ; tension mondiale (0 à 100).
var claims: Dictionary = {}
var next_claim_id: int = 0
var world_tension: float = 0.0
## Délais avant de refaire une action : « action|A|B » → mois.
var cooldowns: Dictionary = {}
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
	return clampf(float(start_relations.get(key, 0.0)) + float(treaty_bonus.get(key, 0.0))
		+ float(relation_changes.get(key, 0.0)), -LIMIT, LIMIT)


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


func has_embassy(a: String, b: String) -> bool:
	return a == b or not closed_embassies.has(pair_key(a, b))


func recognizes(holder: String, state_tag: String) -> bool:
	return recognitions.has(opinion_key(holder, state_tag))


func guarantees_independence(guarantor: String, target: String) -> bool:
	return guarantees.has(opinion_key(guarantor, target))


## Traités entre deux pays : [identifiants].
func treaties_between(a: String, b: String) -> Array[int]:
	var result: Array[int] = []
	for treaty_id: Variant in treaties.keys():
		var treaty: Dictionary = treaties[treaty_id]
		if (treaty["a"] == a and treaty["b"] == b) or (treaty["a"] == b and treaty["b"] == a):
			result.append(int(treaty_id))
	return result


func has_treaty(a: String, b: String, treaty_type: String) -> bool:
	return treaties_between(a, b).any(func(treaty_id: int) -> bool:
		return str((treaties[treaty_id] as Dictionary)["type"]) == treaty_type)


## Traités d'un pays : [identifiants].
func treaties_of(tag: String) -> Array[int]:
	var result: Array[int] = []
	for treaty_id: Variant in treaties.keys():
		var treaty: Dictionary = treaties[treaty_id]
		if treaty["a"] == tag or treaty["b"] == tag:
			result.append(int(treaty_id))
	return result


func cooldown(action: String, a: String, b: String) -> int:
	return int(cooldowns.get("%s|%s" % [action, pair_key(a, b)], 0))


func set_cooldown(action: String, a: String, b: String, months: int) -> void:
	if months > 0:
		cooldowns["%s|%s" % [action, pair_key(a, b)]] = months


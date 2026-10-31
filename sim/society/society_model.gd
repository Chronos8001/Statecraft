class_name SocietyModel
extends RefCounted
## Formules de la société, sans état.
##
## Satisfaction d'un groupe : celle de départ (popularité du gouvernement + affinité avec son idéologie),
## plus les effets du budget sur ce groupe, plus ses réactions aux écarts par rapport au départ
## (chômage, inflation, croissance, coupures d'électricité, part publique de l'économie).
## Elle se rapproche chaque mois de cette cible. Le soutien populaire est la moyenne pondérée par la
## population ; la stabilité suit la satisfaction des groupes influents et les effets du budget.

const PERCENT := 100.0
const REACTIONS := ["unemployment", "inflation", "growth", "blackout", "public_ownership"]


static func weighted(values: Dictionary, weights: Dictionary) -> float:
	var total := 0.0
	var weight_sum := 0.0
	for key: Variant in weights.keys():
		if values.has(key):
			total += float(values[key]) * float(weights[key])
			weight_sum += float(weights[key])
	return total / weight_sum if weight_sum > 0.0 else 0.0


## Poids politique de chaque groupe : part de la population × influence propre × influence dans le régime.
static func influence_weights(shares: Dictionary, groups: Dictionary, regime_influence: Dictionary) -> Dictionary:
	var raw: Dictionary = {}
	var total := 0.0
	for group_id: Variant in shares.keys():
		var definition: Dictionary = groups.get(group_id, {})
		var weight := float(shares[group_id]) * float(definition.get("influence", 1.0)) \
			* float(regime_influence.get(group_id, 1.0))
		raw[group_id] = weight
		total += weight
	for group_id: Variant in raw.keys():
		raw[group_id] = float(raw[group_id]) / total if total > 0.0 else 0.0
	return raw


## Satisfaction de départ : popularité + affinité de chaque groupe avec la famille politique au pouvoir,
## recentrée pour que la moyenne pondérée par la population retombe sur la popularité.
static func start_satisfaction(approval: float, shares: Dictionary, groups: Dictionary, party_group: String,
		bounds: Array) -> Dictionary:
	var result: Dictionary = {}
	for group_id: Variant in shares.keys():
		var affinity: Dictionary = (groups.get(group_id, {}) as Dictionary).get("affinity", {})
		result[group_id] = approval + float(affinity.get(party_group, 0.0))
	var offset := approval - weighted(result, shares)
	for group_id: Variant in result.keys():
		result[group_id] = clampf(float(result[group_id]) + offset, float(bounds[0]), float(bounds[1]))
	return result


## Réaction d'un groupe aux écarts par rapport au départ (changes : {unemployment, inflation, …}).
## Les améliorations comptent moins que les dégradations (gain_factor) et sont plafonnées plus bas.
static func reaction(reactions: Dictionary, changes: Dictionary, max_loss: float, max_gain: float,
		gain_factor: float) -> float:
	var total := 0.0
	for key: String in REACTIONS:
		total += float(reactions.get(key, 0.0)) * float(changes.get(key, 0.0))
	if total > 0.0:
		return minf(total * gain_factor, max_gain)
	return maxf(total, -max_loss)


static func satisfaction_target(start: float, budget_effect: float, reaction_value: float, bounds: Array) -> float:
	return clampf(start + budget_effect + reaction_value, float(bounds[0]), float(bounds[1]))


## Rapproche une valeur de sa cible d'une fraction de l'écart.
static func approach(current: float, target: float, rate: float) -> float:
	return current + (target - current) * rate


static func stability_target(society: SocietyState, budget_effect: float, settings: Dictionary) -> float:
	var change := society.influential_satisfaction() - SocietyModel.weighted(society.start_satisfaction,
		society.influence)
	return clampf(society.start_stability + float(settings.get("per_satisfaction_point", 0.0)) * change
		+ float(settings.get("budget_effect", 0.0)) * budget_effect, 0.0, PERCENT)


## Légitimité de départ : indice de démocratie dans les démocraties, valeur du régime ailleurs.
static func start_legitimacy(democratic: bool, democracy_index: float, regime_legitimacy: float,
		settings: Dictionary) -> float:
	if democratic:
		return clampf(democracy_index * float(settings.get("democracy_factor", 0.0)), 0.0, PERCENT)
	return clampf(regime_legitimacy, 0.0, PERCENT)


static func legitimacy_target(society: SocietyState, settings: Dictionary) -> float:
	return clampf(society.start_legitimacy
		+ float(settings.get("per_support_point", 0.0)) * (society.support - society.start_support)
		+ float(settings.get("per_stability_point", 0.0)) * (society.stability - society.start_stability), 0.0, PERCENT)


## Croissance perdue quand la stabilité tombe sous son niveau de départ (points de % par an, ≤ 0).
static func growth_penalty(society: SocietyState, settings: Dictionary) -> float:
	var lost := maxf(society.start_stability - society.stability, 0.0)
	return -minf(lost * float(settings.get("growth_per_lost_point", 0.0)), float(settings.get("max_growth_penalty", 0.0)))

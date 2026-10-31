class_name PoliticsModel
extends RefCounted
## Formules des sondages, sans état.
##
## Chaque parti puise des voix dans les groupes sociaux : poids d'un groupe pour un parti =
## exp(échelle × affinité du groupe avec la famille du parti). Les partis au gouvernement gagnent ou
## perdent selon l'écart de satisfaction de chaque groupe avec le départ. L'attrait propre de chaque parti
## est calé pour retrouver le sondage de départ ; un écart aléatoire persistant anime les sondages.

const PERCENT := 100.0


## Voix potentielles d'un parti (sans unité) : somme des groupes pondérés par leur affinité.
static func raw_support(party_group: String, in_government: bool, society: SocietyState, groups: Dictionary,
		settings: Dictionary) -> float:
	var affinity_scale := float(settings.get("affinity_scale", 0.0))
	var government_scale := float(settings.get("government_scale", 0.0))
	var total := 0.0
	for group_id: Variant in society.group_shares.keys():
		var affinity: Dictionary = (groups.get(group_id, {}) as Dictionary).get("affinity", {})
		var exponent := affinity_scale * float(affinity.get(party_group, 0.0))
		if in_government:
			exponent += government_scale * (float(society.satisfaction.get(group_id, 0.0))
				- float(society.start_satisfaction.get(group_id, 0.0)))
		total += float(society.group_shares[group_id]) * exp(exponent)
	return total


## Attrait de départ : sondage de départ / voix potentielles de départ.
static func calibrate(politics: PoliticsState, society: SocietyState, groups: Dictionary, settings: Dictionary) -> void:
	for party: PartyState in politics.parties.values():
		var raw := raw_support(party.party_group, politics.is_in_government(party.id), society, groups, settings)
		party.appeal = party.start_poll / raw if raw > 0.0 else 0.0


## Intentions de vote (%) des partis, les petits partis gardant leur part de départ.
static func polls(politics: PoliticsState, society: SocietyState, groups: Dictionary, settings: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var total := 0.0
	for party: PartyState in politics.parties.values():
		var bonus := politics.campaign_bonus if party.id == politics.ruling_party() else 0.0
		var value := party.appeal * exp(party.drift + bonus) * raw_support(party.party_group,
			politics.is_in_government(party.id), society, groups, settings)
		values[party.id] = value
		total += value
	var available := PERCENT - politics.other_poll
	for party_id: Variant in values.keys():
		values[party_id] = float(values[party_id]) / total * available if total > 0.0 else 0.0
	return values


## Écart aléatoire suivant : il revient lentement vers zéro.
static func next_drift(drift: float, noise: float, settings: Dictionary) -> float:
	return drift * float(settings.get("drift_persistence", 0.0)) + noise * float(settings.get("drift_sigma", 0.0))

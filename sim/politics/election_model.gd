class_name ElectionModel
extends RefCounted
## Formules des élections, sans état.
##
## Votes par province : sondage national × penchant urbain ou rural de la famille du parti (selon la densité
## de la province par rapport à la moyenne du pays) × penchant local stable ; puis recalés pour que la
## moyenne nationale retombe sur le résultat national. Sièges : D'Hondt avec seuil (proportionnelle),
## loi du cube par province (majoritaire), ou les deux (mixte).

const PERCENT := 100.0
const RECALIBRATION_PASSES := 3
const HASH_RANGE := 10000


## Nombre stable entre -1 et 1 tiré d'une clé (même valeur à chaque partie).
static func stable_noise(key: String) -> float:
	return float(absi(key.hash()) % HASH_RANGE) / HASH_RANGE * 2.0 - 1.0


## Écart de densité de chaque province à la moyenne du pays (pondérée par la population), en écarts-types bornés.
## provinces : [[id, population, superficie], …].
static func density_scores(provinces: Array, cap: float) -> Dictionary:
	var logs: Dictionary = {}
	var total := 0.0
	var weighted := 0.0
	for entry: Array in provinces:
		var density := maxf(float(entry[1]), 1.0) / maxf(float(entry[2]), 1.0)
		logs[entry[0]] = log(density)
		weighted += log(density) * maxf(float(entry[1]), 1.0)
		total += maxf(float(entry[1]), 1.0)
	var mean := weighted / total if total > 0.0 else 0.0
	var variance := 0.0
	for entry: Array in provinces:
		variance += pow(float(logs[entry[0]]) - mean, 2.0) * maxf(float(entry[1]), 1.0)
	var deviation := maxf(sqrt(variance / total) if total > 0.0 else 1.0, 0.5)
	var result: Dictionary = {}
	for entry: Array in provinces:
		result[entry[0]] = clampf((float(logs[entry[0]]) - mean) / deviation, -cap, cap)
	return result


## Votes (%) de chaque parti dans chaque province, recalés sur le résultat national (national : {parti: %}).
## extra : penchants ajoutés {province: {parti: penchant}} (meetings de campagne).
static func regional_votes(national: Dictionary, groups_of: Dictionary, provinces: Array, other_share: float,
		settings: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var urban: Dictionary = settings.get("urban_lean", {})
	var local := float(settings.get("local_sigma", 0.0))
	var scores := density_scores(provinces, float(settings.get("density_score_cap", 1.0)))
	var regional: Dictionary = {}
	for entry: Array in provinces:
		var votes: Dictionary = {}
		for party_id: Variant in national.keys():
			var lean := float(urban.get(groups_of.get(party_id, ""), 0.0)) * float(scores[entry[0]]) \
				+ local * stable_noise("%s|%s" % [entry[0], party_id]) \
				+ float((extra.get(entry[0], {}) as Dictionary).get(party_id, 0.0))
			votes[party_id] = float(national[party_id]) * exp(lean)
		regional[entry[0]] = _normalized(votes, PERCENT - other_share)
	for _pass: int in RECALIBRATION_PASSES:
		var current := national_votes(regional, provinces)
		for entry: Array in provinces:
			var votes: Dictionary = regional[entry[0]]
			for party_id: Variant in votes.keys():
				var reached := float(current.get(party_id, 0.0))
				votes[party_id] = float(votes[party_id]) * (float(national[party_id]) / reached if reached > 0.0 else 1.0)
			regional[entry[0]] = _normalized(votes, PERCENT - other_share)
	return regional


## Moyenne nationale des votes régionaux, pondérée par la population.
static func national_votes(regional: Dictionary, provinces: Array) -> Dictionary:
	var result: Dictionary = {}
	var total := 0.0
	for entry: Array in provinces:
		var weight := maxf(float(entry[1]), 1.0)
		total += weight
		var votes: Dictionary = regional[entry[0]]
		for party_id: Variant in votes.keys():
			result[party_id] = float(result.get(party_id, 0.0)) + float(votes[party_id]) * weight
	for party_id: Variant in result.keys():
		result[party_id] = float(result[party_id]) / total
	return result


## Répartition au plus fort reste de seats sièges selon des poids.
static func largest_remainder(weights: Dictionary, seats: int) -> Dictionary:
	var result: Dictionary = {}
	var total := 0.0
	for key: Variant in weights.keys():
		total += maxf(float(weights[key]), 0.0)
		result[key] = 0
	if total <= 0.0 or seats <= 0:
		return result
	var remainders: Array = []
	var given := 0
	for key: Variant in weights.keys():
		var exact := maxf(float(weights[key]), 0.0) / total * seats
		result[key] = floori(exact)
		given += floori(exact)
		remainders.append([exact - floori(exact), str(key)])
	remainders.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and str(a[1]) < str(b[1])))
	for i: int in seats - given:
		var key: Variant = remainders[i % remainders.size()][1]
		result[key] = int(result[key]) + 1
	return result


## Méthode D'Hondt entre les partis au-dessus du seuil (tous si aucun ne l'atteint).
static func dhondt(votes: Dictionary, seats: int, threshold: float) -> Dictionary:
	var eligible: Array = votes.keys().filter(func(key: Variant) -> bool: return float(votes[key]) >= threshold)
	if eligible.is_empty():
		eligible = votes.keys()
	eligible.sort()
	var result: Dictionary = {}
	for key: Variant in votes.keys():
		result[key] = 0
	for _seat: int in seats:
		var best: Variant = null
		var best_quotient := -1.0
		for key: Variant in eligible:
			var quotient := float(votes[key]) / (int(result[key]) + 1)
			if quotient > best_quotient:
				best_quotient = quotient
				best = key
		if best == null:
			break
		result[best] = int(result[best]) + 1
	return result


## Scrutin majoritaire : sièges répartis entre provinces selon leur population, puis dans chaque province selon
## la loi du cube (part des voix à la puissance exponent), ce qui avantage nettement le parti en tête.
static func majoritarian(regional: Dictionary, provinces: Array, seats: int, exponent: float) -> Dictionary:
	var populations: Dictionary = {}
	for entry: Array in provinces:
		populations[entry[0]] = maxf(float(entry[1]), 1.0)
	var per_province := largest_remainder(populations, seats)
	var result: Dictionary = {}
	for entry: Array in provinces:
		var votes: Dictionary = regional[entry[0]]
		var powered: Dictionary = {}
		for party_id: Variant in votes.keys():
			powered[party_id] = pow(float(votes[party_id]), exponent)
			if not result.has(party_id):
				result[party_id] = 0
		var won := largest_remainder(powered, int(per_province[entry[0]]))
		for party_id: Variant in won.keys():
			result[party_id] = int(result[party_id]) + int(won[party_id])
	return result


## Sièges des partis selon le système du pays ; seats : sièges à pourvoir hors petits partis.
static func allocate(system_type: String, threshold: float, list_share: float, national: Dictionary,
		regional: Dictionary, provinces: Array, seats: int, exponent: float) -> Dictionary:
	if provinces.is_empty() or system_type == PoliticsState.SYSTEM_PROPORTIONAL:
		return dhondt(national, seats, threshold)
	if system_type == PoliticsState.SYSTEM_MAJORITARIAN:
		return majoritarian(regional, provinces, seats, exponent)
	var list_seats := roundi(seats * list_share)
	var result := dhondt(national, list_seats, threshold)
	var districts := majoritarian(regional, provinces, seats - list_seats, exponent)
	for party_id: Variant in districts.keys():
		result[party_id] = int(result.get(party_id, 0)) + int(districts[party_id])
	return result


## Parti en tête de chaque province.
static func regional_winners(regional: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for province_id: Variant in regional.keys():
		var votes: Dictionary = regional[province_id]
		var best := ""
		for party_id: Variant in votes.keys():
			if best.is_empty() or float(votes[party_id]) > float(votes[best]):
				best = str(party_id)
		result[province_id] = best
	return result


## Gouvernement issu de la chambre : le sortant s'il garde la majorité, sinon le premier parti s'allie aux
## partis les plus proches sur l'axe gauche-droite jusqu'à la majorité (gouvernement minoritaire sinon).
## parties : {parti: [sièges, position, exclu]} ; un parti exclu ne gouverne que s'il a seul la majorité.
static func form_government(parties: Dictionary, total_seats: int, incumbent: Array, settings: Dictionary) -> Array[String]:
	var incumbent_seats := 0
	var incumbent_present := not incumbent.is_empty()
	for party_id: Variant in incumbent:
		var seats := int((parties.get(party_id, [0, 0.0]) as Array)[0])
		incumbent_seats += seats
		if seats <= 0:
			incumbent_present = false
	if incumbent_present and incumbent_seats * 2 > total_seats:
		var kept: Array[String] = []
		for party_id: Variant in incumbent:
			kept.append(str(party_id))
		return kept
	var ids: Array = parties.keys().filter(func(key: Variant) -> bool: return int(parties[key][0]) > 0)
	if ids.is_empty():
		return []
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(parties[a][0]) > int(parties[b][0]) or (int(parties[a][0]) == int(parties[b][0]) and str(a) < str(b)))
	if _excluded(parties, ids[0]) and int(parties[ids[0]][0]) * 2 <= total_seats:
		ids = ids.filter(func(key: Variant) -> bool: return not _excluded(parties, key))
		if ids.is_empty():
			return []
	var formateur: String = ids[0]
	var position := float(parties[formateur][1])
	var candidates: Array = ids.slice(1).filter(func(key: Variant) -> bool: return not _excluded(parties, key))
	candidates.sort_custom(func(a: Variant, b: Variant) -> bool:
		var distance_a := absf(float(parties[a][1]) - position)
		var distance_b := absf(float(parties[b][1]) - position)
		return distance_a < distance_b if distance_a != distance_b else int(parties[a][0]) > int(parties[b][0]))
	var coalition: Array[String] = [formateur]
	var seats := int(parties[formateur][0])
	var max_partners := int(settings.get("max_partners", 0))
	var max_distance := float(settings.get("max_coalition_distance", 0.0))
	for candidate: Variant in candidates:
		if seats * 2 > total_seats or coalition.size() > max_partners:
			break
		if absf(float(parties[candidate][1]) - position) > max_distance:
			break
		coalition.append(str(candidate))
		seats += int(parties[candidate][0])
	return coalition


## Présidentielle : les candidats des premiers partis ; les voix des autres partis se reportent sur les
## candidats proches. Deux tours si personne n'a la majorité et que le pays en prévoit deux.
## scores : {parti: intentions de vote}, positions : {parti: position gauche-droite}.
## Renvoie {winner, rounds: [{parti: %}, …]}.
static func presidential(scores: Dictionary, positions: Dictionary, two_rounds: bool, settings: Dictionary) -> Dictionary:
	var ids: Array = scores.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float(scores[a]) > float(scores[b]) or (float(scores[a]) == float(scores[b]) and str(a) < str(b)))
	if ids.is_empty():
		return {"winner": "", "rounds": []}
	var candidates: Array = ids.slice(0, maxi(int(settings.get("presidential_candidates", 2)), 2))
	var first := transfer(scores, candidates, positions, float(settings.get("transfer_decay", 1.0)))
	var rounds: Array = [first]
	var ranked := _ranked(first)
	if not two_rounds or float(first[ranked[0]]) > PERCENT / 2.0 or ranked.size() < 2:
		return {"winner": ranked[0], "rounds": rounds}
	var second := transfer(scores, ranked.slice(0, 2), positions, float(settings.get("transfer_decay", 1.0)))
	rounds.append(second)
	return {"winner": _ranked(second)[0], "rounds": rounds}


## Part des voix (%) de chaque candidat : ses propres électeurs plus ceux des autres partis, répartis selon
## la proximité (poids exp(-decay × distance)).
static func transfer(scores: Dictionary, candidates: Array, positions: Dictionary, decay: float) -> Dictionary:
	var result: Dictionary = {}
	for candidate: Variant in candidates:
		result[candidate] = 0.0
	for party_id: Variant in scores.keys():
		var weights: Dictionary = {}
		var weight_sum := 0.0
		for candidate: Variant in candidates:
			var weight := 1.0 if candidate == party_id else \
				exp(-decay * absf(float(positions.get(party_id, 0.0)) - float(positions.get(candidate, 0.0))))
			if candidates.has(party_id) and candidate != party_id:
				weight = 0.0
			weights[candidate] = weight
			weight_sum += weight
		for candidate: Variant in candidates:
			result[candidate] = float(result[candidate]) + float(scores[party_id]) * float(weights[candidate]) / weight_sum
	return _normalized(result, PERCENT)


static func _excluded(parties: Dictionary, party_id: Variant) -> bool:
	var entry: Array = parties[party_id]
	return entry.size() > 2 and bool(entry[2])


static func _ranked(votes: Dictionary) -> Array:
	var ids: Array = votes.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float(votes[a]) > float(votes[b]) or (float(votes[a]) == float(votes[b]) and str(a) < str(b)))
	return ids


static func _normalized(values: Dictionary, total_target: float) -> Dictionary:
	var total := 0.0
	for value: Variant in values.values():
		total += float(value)
	var result: Dictionary = {}
	for key: Variant in values.keys():
		result[key] = float(values[key]) / total * total_target if total > 0.0 else 0.0
	return result

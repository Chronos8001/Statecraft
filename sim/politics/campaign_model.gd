class_name CampaignModel
extends RefCounted
## Formules de la campagne électorale et de la fraude, sans état.
##
## Pendant les mois qui précèdent un scrutin, le parti qui dirige le gouvernement peut :
## - financer sa campagne : bonus de sondage à rendement décroissant selon la dépense (en % du PIB) ;
## - tenir des meetings : bonus local dans la province et un petit bonus national ;
## - faire des promesses à un groupe social : satisfaction immédiate, sanction si elle n'est pas tenue ;
## - truquer le scrutin : quelques points de plus, au risque d'un scandale s'il est découvert.

const PERCENT := 100.0
const MONTHS_PER_YEAR := 12


## Bonus de sondage (logarithme d'un facteur) pour une dépense donnée, en % du PIB.
static func spending_bonus(spent_share: float, settings: Dictionary) -> float:
	var scale := float(settings.get("spending_scale", 1.0))
	return float(settings.get("max_spending_bonus", 0.0)) * (1.0 - exp(-maxf(spent_share, 0.0) / scale))


## Bonus total du parti au pouvoir : dépense + meetings, plafonné.
static func campaign_bonus(politics: PoliticsState, gdp_billion: float, settings: Dictionary) -> float:
	var share := politics.campaign_spent / gdp_billion * PERCENT if gdp_billion > 0.0 else 0.0
	var rallies := politics.rallies.size() * float(settings.get("rally_national_bonus", 0.0))
	return minf(spending_bonus(share, settings) + rallies, float(settings.get("max_campaign_bonus", INF)))


## Prochain scrutin (législatif ou présidentiel) dans la fenêtre de campagne : [année, mois] ou [] sinon.
static func campaign_election(politics: PoliticsState, year: int, month: int, settings: Dictionary) -> Array:
	if politics.suspended or politics.seats <= 0:
		return []
	var window := int(settings.get("campaign_months", 0))
	var now := year * MONTHS_PER_YEAR + month
	var best: Array = []
	var dates: Array = [[politics.next_election_year, politics.next_election_month]]
	if politics.has_presidency:
		dates.append([politics.next_presidential_year, politics.next_presidential_month])
	for date: Array in dates:
		var months := int(date[0]) * MONTHS_PER_YEAR + int(date[1]) - now
		if months >= 0 and months <= window and (best.is_empty() \
				or int(date[0]) * MONTHS_PER_YEAR + int(date[1]) < int(best[0]) * MONTHS_PER_YEAR + int(best[1])):
			best = date
	return best


## Voix du parti au pouvoir augmentées de points de fraude, prises aux autres partis au prorata.
static func rigged_votes(votes: Dictionary, party_id: String, points: float) -> Dictionary:
	if not votes.has(party_id) or points <= 0.0:
		return votes
	var others := 0.0
	for key: Variant in votes.keys():
		if str(key) != party_id:
			others += float(votes[key])
	var taken := minf(points, others)
	var result: Dictionary = {}
	for key: Variant in votes.keys():
		if str(key) == party_id:
			result[key] = float(votes[key]) + taken
		else:
			result[key] = float(votes[key]) * (1.0 - taken / others) if others > 0.0 else 0.0
	return result


## Probabilité qu'une fraude soit découverte : forte dans les démocraties solides et quand la presse est libre.
static func detection_chance(level: int, democracy_index: float, media_factor: float, settings: Dictionary) -> float:
	var per_level: Array = settings.get("fraud_detection", [])
	if level <= 0 or per_level.is_empty():
		return 0.0
	var base := float(per_level[mini(level, per_level.size()) - 1])
	return clampf(base * (0.3 + 0.7 * democracy_index / 10.0) * media_factor, 0.0, 1.0)

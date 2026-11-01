class_name DiplomacyModel
extends RefCounted
## Formules de la diplomatie, sans état : intérêt d'un pays de l'IA pour un traité ou une exigence.
##
## Score = base du traité + relations × poids + (confiance - 50) × poids + régimes semblables + puissance
## relative + intérêt commercial + écart de richesse. Le pays accepte si le score est positif et que les
## relations atteignent le minimum du traité. Le joueur voit ce score avant de proposer.

const PERCENT := 100.0
const NEUTRAL_TRUST := 50.0


## Puissance d'un pays : son PIB (milliards de dollars) + sa puissance militaire × poids des données.
static func power(state: SimState, tag: String) -> float:
	return maxf(TradeSystem.current_gdp(state, tag) + float(state.military_settings.get("diplomatic_weight", 0.0))
		* MilitarySystem.power(state, tag), 0.001)


## Score d'acceptation d'un traité proposé par proposer à target (positif : accepté).
static func treaty_score(state: SimState, proposer: String, target: String, definition: Dictionary) -> float:
	var rules: Dictionary = definition.get("acceptance", {})
	var diplomacy := state.diplomacy
	var relation := diplomacy.relation(proposer, target)
	var score := float(rules.get("base", 0.0)) + float(rules.get("relation", 0.0)) * relation \
		+ float(rules.get("trust", 0.0)) * (diplomacy.trust(proposer, target) - NEUTRAL_TRUST)
	var a := state.get_country(proposer)
	var b := state.get_country(target)
	if a != null and b != null:
		if rules.has("same_regime"):
			score += float(rules["same_regime"]) * (1.0 if a.politics.democratic == b.politics.democratic else -1.0)
		if rules.has("power"):
			# Un pays plus faible cherche la protection d'un plus fort, et inversement.
			score += float(rules["power"]) * clampf(log(power(state, proposer) / power(state, target)) / log(10.0), -1.5, 1.5)
		if rules.has("trade"):
			score += float(rules["trade"]) * trade_share(state, target, proposer)
		if rules.has("wealth_gap"):
			var ratio := gdp_per_capita(state, a) / maxf(gdp_per_capita(state, b), 1.0)
			score += float(rules["wealth_gap"]) * clampf(absf(log(ratio)) / log(3.0), 0.0, 2.0)
	score += InfluenceSystem.weight(state, "treaty") * InfluenceSystem.influence(state, proposer, target)
	if relation < float(rules.get("min_relation", -DiplomacyState.LIMIT)):
		score = minf(score, -1.0)
	return score


## Part du commerce de tag réalisée avec partner (0 à 1).
static func trade_share(state: SimState, tag: String, partner: String) -> float:
	var totals := TradeSystem.partner_totals(state, tag)
	var total := 0.0
	for value: Variant in totals.values():
		total += float(value)
	return float(totals.get(partner, 0.0)) / total if total > 0.0 else 0.0


static func gdp_per_capita(state: SimState, country: CountryState) -> float:
	var currency := state.get_currency(country.economy.currency)
	return country.economy.gdp_per_capita_usd(currency) if currency != null else 0.0


## Ultimatum (tribut) : le pays cède si l'exigeant est bien plus puissant et que la relation n'est pas
## déjà rompue. Score positif : il cède.
static func ultimatum_score(state: SimState, proposer: String, target: String, settings: Dictionary) -> float:
	var ratio := power(state, proposer) / power(state, target)
	return float(settings.get("power_weight", 0.0)) * log(ratio) / log(10.0) - float(settings.get("threshold", 0.0)) \
		+ float(settings.get("relation_weight", 0.0)) * state.diplomacy.relation(proposer, target)

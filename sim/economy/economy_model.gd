class_name EconomyModel
extends RefCounted
## Formules macroéconomiques, sans état : chaque fonction calcule une valeur à partir de ses
## arguments et des réglages (defines.economy). Les taux sont en points de pourcentage annuels.

const MONTHS_PER_YEAR := 12.0
const PERCENT := 100.0
const DOLLARS_PER_THOUSAND := 1000.0


## Croissance de long terme vers laquelle tend la croissance potentielle : plus forte pour les pays pauvres.
static func long_run_growth(gdp_per_capita: float, settings: Dictionary) -> float:
	var cfg: Dictionary = settings["long_run_growth"]
	var income := maxf(gdp_per_capita / DOLLARS_PER_THOUSAND, 0.001)
	return clampf(float(cfg["base"]) - float(cfg["slope"]) * log(income), float(cfg["min"]), float(cfg["max"]))


## Effet de la politique monétaire sur la croissance : un taux réel au-dessus du neutre freine l'activité.
## L'écart est plafonné : en hyperinflation, le taux réel n'a plus de sens économique.
static func demand_effect(policy_rate: float, inflation: float, neutral_real_rate: float, settings: Dictionary) -> float:
	var limit := float(settings["max_real_rate_gap"])
	return -float(settings["rate_sensitivity"]) * clampf((policy_rate - inflation) - neutral_real_rate, -limit, limit)


## Écart de production après un mois : accumule l'écart de croissance et se résorbe peu à peu.
static func next_output_gap(gap: float, growth: float, potential: float, settings: Dictionary) -> float:
	return gap * (1.0 - float(settings["output_gap_decay"])) + (growth - potential) / MONTHS_PER_YEAR


## Inflation anticipée : ancrée sur la cible d'autant plus que la banque centrale est crédible.
static func expected_inflation(inflation: float, target: float, independent: bool, settings: Dictionary) -> float:
	var credibility := float(settings["credibility_independent" if independent else "credibility_dependent"])
	return credibility * target + (1.0 - credibility) * inflation


## Inflation après un mois : se rapproche de l'inflation anticipée, poussée par l'écart de production
## (courbe de Phillips) et par la baisse de la monnaie (prix des importations).
static func next_inflation(inflation: float, expected: float, output_gap: float, depreciation: float,
		settings: Dictionary) -> float:
	var goal := expected + float(settings["phillips_slope"]) * output_gap
	return inflation + float(settings["inflation_adjustment"]) * (goal - inflation) \
		+ float(settings["depreciation_passthrough"]) * depreciation


## Chômage après un mois (loi d'Okun) : baisse quand l'économie tourne au-dessus de son potentiel.
static func next_unemployment(unemployment: float, natural: float, output_gap: float, settings: Dictionary) -> float:
	var goal := natural - float(settings["okun_coefficient"]) * output_gap
	return unemployment + float(settings["unemployment_adjustment"]) * (goal - unemployment)


## Taux directeur visé (règle de Taylor). Une banque centrale sous contrôle réagit peu à l'inflation.
static func taylor_rate(inflation: float, output_gap: float, target: float, neutral_real_rate: float,
		independent: bool, settings: Dictionary) -> float:
	var inflation_weight := float(settings["taylor_inflation_weight" if independent else "dependent_inflation_weight"])
	return neutral_real_rate + inflation + inflation_weight * (inflation - target) \
		+ float(settings["taylor_gap_weight"]) * output_gap


## Le taux directeur se rapproche progressivement de sa cible, avec un pas maximal par mois.
static func next_policy_rate(rate: float, goal: float, settings: Dictionary) -> float:
	var step := clampf((goal - rate) * float(settings["rate_smoothing"]), -float(settings["max_rate_step"]),
		float(settings["max_rate_step"]))
	return clampf(rate + step, float(settings["min_policy_rate"]), float(settings["max_policy_rate"]))


## Dépréciation mensuelle (%) d'une monnaie flottante face à la monnaie de référence :
## écart d'inflation (parité de pouvoir d'achat), atténué si ses taux réels sont plus attractifs.
static func monthly_depreciation(inflation: float, real_rate_gap: float, reference_inflation: float,
		settings: Dictionary) -> float:
	var limit := float(settings["max_real_rate_gap"])
	return ((inflation - reference_inflation) - float(settings["fx_rate_sensitivity"]) * clampf(real_rate_gap, -limit, limit)) 		/ MONTHS_PER_YEAR


## Score de solvabilité, en crans de l'échelle des notes (avant l'écart propre au pays).
static func rating_score(gdp_per_capita: float, debt_ratio: float, inflation: float, target: float, growth: float,
		real_interest_burden: float, imf_program: bool, settings: Dictionary) -> float:
	var model: Dictionary = settings["rating_model"]
	var income := maxf(gdp_per_capita / DOLLARS_PER_THOUSAND, 0.001)
	return float(model["base"]) + float(model["gdp_per_capita_log"]) * log(income) \
		+ float(model["debt"]) * debt_ratio \
		+ float(model["inflation_excess"]) * clampf(inflation - target, 0.0, float(settings["max_inflation_excess"])) \
		+ float(model["growth"]) * growth \
		+ float(model["real_interest_burden"]) * maxf(real_interest_burden, 0.0) \
		+ (float(model["imf_bonus"]) if imf_program else 0.0)


## Nouvelle note après une revue : un cran au plus, seulement si le score s'en écarte assez.
static func reviewed_rating(current: int, score: float, best: int, hysteresis: float) -> int:
	if score >= current + hysteresis:
		return mini(current + 1, best)
	if score <= current - hysteresis:
		return maxi(current - 1, 0)
	return current


## Probabilité mensuelle d'une crise de la dette : nulle au-dessus du seuil, croissante à chaque cran en dessous.
static func crisis_probability(rating: int, max_rating: int, per_notch: float) -> float:
	if rating > max_rating:
		return 0.0
	return clampf(per_notch * float(max_rating - rating + 1), 0.0, 1.0)


## Parts des secteurs après un mois : chaque secteur suit sa tendance par rapport à la moyenne.
static func next_sector_shares(shares: Dictionary, trends: Dictionary) -> Dictionary:
	var mean_trend := 0.0
	for sector: Variant in shares.keys():
		mean_trend += float(shares[sector]) * float(trends.get(sector, 0.0))
	var result: Dictionary = {}
	var total := 0.0
	for sector: Variant in shares.keys():
		var share := float(shares[sector]) * (1.0 + (float(trends.get(sector, 0.0)) - mean_trend) / PERCENT / MONTHS_PER_YEAR)
		result[sector] = maxf(share, 0.0)
		total += float(result[sector])
	if total > 0.0:
		for sector: Variant in result.keys():
			result[sector] = float(result[sector]) / total
	return result

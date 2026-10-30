class_name BudgetModel
extends RefCounted
## Formules du budget, sans état.
##
## Recettes d'un impôt (% du PIB) = taux × recettes par point × (1 − élasticité × hausse du taux / 100) :
## plus le taux dépasse celui de départ, plus la base fiscale se dérobe (courbe de Laffer).
## Effets : chaque poste ou impôt déclare ses effets par point de PIB (dépenses) ou de taux (impôts),
## mesurés par rapport au budget de départ, qui est donc neutre.

const INCOME_TAX := "income_tax"
const GROUPS := "groups"
const PERCENT := 100.0
## Effets économiques appliqués tout de suite par l'économie ; les autres attendent leurs systèmes.
const ECONOMIC_EFFECTS := ["growth", "unemployment", "inflation"]


## Taux moyen de l'impôt sur le revenu : tranches pondérées par la part des revenus qui y tombe.
static func average_income_rate(brackets: Array[float], weights: Array) -> float:
	var total := 0.0
	var weight_sum := 0.0
	for index: int in mini(brackets.size(), weights.size()):
		total += brackets[index] * float(weights[index])
		weight_sum += float(weights[index])
	return total / weight_sum if weight_sum > 0.0 else 0.0


static func tax_revenue(rate: float, start_rate: float, revenue_per_point: float, elasticity: float) -> float:
	var base := maxf(1.0 - elasticity * (rate - start_rate) / PERCENT, 0.0)
	return maxf(rate * revenue_per_point * base, 0.0)


## Recettes de chaque impôt (% du PIB).
static func revenues(budget: BudgetState, taxes: Dictionary, bracket_weights: Array) -> Dictionary:
	var result: Dictionary = {}
	for tax_id: Variant in taxes.keys():
		var definition: Dictionary = taxes[tax_id]
		var rate := current_rate(budget, str(tax_id), bracket_weights)
		var start := start_rate(budget, str(tax_id), bracket_weights)
		result[tax_id] = tax_revenue(rate, start, float(budget.revenue_per_point.get(tax_id, 0.0)),
			float(definition.get("elasticity", 0.0)))
	return result


static func current_rate(budget: BudgetState, tax_id: String, bracket_weights: Array) -> float:
	if tax_id == INCOME_TAX:
		return average_income_rate(budget.income_brackets, bracket_weights)
	return float(budget.tax_rates.get(tax_id, 0.0))


static func start_rate(budget: BudgetState, tax_id: String, bracket_weights: Array) -> float:
	if tax_id == INCOME_TAX:
		return average_income_rate(budget.start_income_brackets, bracket_weights)
	return float(budget.start_tax_rates.get(tax_id, 0.0))


## Effets du budget par rapport au départ : {croissance, chômage, inflation, stabilité, recherche, armée,
## influence, groups: {groupe: satisfaction}}. Les effets économiques sont plafonnés.
static func effects(budget: BudgetState, taxes: Dictionary, spending_lines: Dictionary, settings: Dictionary) -> Dictionary:
	var result: Dictionary = {GROUPS: {}}
	var weights: Array = settings.get("income_bracket_weights", [])
	for line_id: Variant in spending_lines.keys():
		var change := float(budget.spending.get(line_id, 0.0)) - float(budget.start_spending.get(line_id, 0.0))
		_add_effects(result, (spending_lines[line_id] as Dictionary).get("effects", {}), change)
	for tax_id: Variant in taxes.keys():
		var definition: Dictionary = taxes[tax_id]
		var change := current_rate(budget, str(tax_id), weights) - start_rate(budget, str(tax_id), weights)
		_add_effects(result, definition.get("effects", {}), change)
		if str(tax_id) == INCOME_TAX:
			var bracket_groups: Array = definition.get("bracket_groups", [])
			for index: int in mini(bracket_groups.size(), budget.income_brackets.size()):
				var bracket_change := budget.income_brackets[index] - budget.start_income_brackets[index]
				_add_effects(result, {GROUPS: bracket_groups[index]}, bracket_change)
	result["inflation"] = float(result.get("inflation", 0.0)) \
		+ float(settings.get("monetary_financing_inflation", 0.0)) * budget.monetary_financing
	var limit := float(settings.get("max_economic_effect", INF))
	for key: String in ECONOMIC_EFFECTS:
		result[key] = clampf(float(result.get(key, 0.0)), -limit, limit)
	return result


static func _add_effects(result: Dictionary, effects_definition: Dictionary, change: float) -> void:
	if is_zero_approx(change):
		return
	for key: Variant in effects_definition.keys():
		if str(key) == GROUPS:
			var groups: Dictionary = result[GROUPS]
			var definition: Dictionary = effects_definition[key]
			for group_id: Variant in definition.keys():
				groups[group_id] = float(groups.get(group_id, 0.0)) + float(definition[group_id]) * change
		else:
			result[key] = float(result.get(key, 0.0)) + float(effects_definition[key]) * change

class_name SetBudgetCommand
extends Command
## Le joueur vote son budget : taux des impôts, tranches de l'impôt sur le revenu, dépenses par poste
## (en % du PIB) et création monétaire. Les valeurs sont ramenées dans les bornes de chaque ligne.

var income_brackets: Array[float] = []
var tax_rates: Dictionary = {}
var spending: Dictionary = {}
var monetary_financing: float = 0.0


func _init(p_issuer: StringName = &"", p_brackets: Array[float] = [], p_tax_rates: Dictionary = {},
		p_spending: Dictionary = {}, p_monetary_financing: float = 0.0) -> void:
	issuer = p_issuer
	income_brackets = p_brackets
	tax_rates = p_tax_rates
	spending = p_spending
	monetary_financing = p_monetary_financing


func get_type() -> StringName:
	return &"set_budget"


func can_execute(state: SimState) -> bool:
	var country := state.get_country(str(issuer))
	if country == null or state.budget_definitions.is_empty():
		return false
	if monetary_financing > 0.0 and not BudgetSystem.can_print_money(state, str(issuer)):
		return false
	var taxes: Dictionary = state.budget_definitions["taxes"]
	var lines: Dictionary = state.budget_definitions["spending"]
	for tax_id: Variant in tax_rates.keys():
		if not taxes.has(tax_id) or str(tax_id) == BudgetModel.INCOME_TAX:
			return false
	for line_id: Variant in spending.keys():
		if not lines.has(line_id):
			return false
	return income_brackets.is_empty() or income_brackets.size() == country.economy.budget.income_brackets.size()


func execute(state: SimState) -> void:
	var budget := state.get_country(str(issuer)).economy.budget
	var taxes: Dictionary = state.budget_definitions["taxes"]
	var lines: Dictionary = state.budget_definitions["spending"]
	var settings: Dictionary = state.budget_definitions["settings"]
	var income: Dictionary = taxes.get(BudgetModel.INCOME_TAX, {})
	for index: int in income_brackets.size():
		budget.income_brackets[index] = clampf(income_brackets[index], float(income.get("min", 0.0)),
			float(income.get("max", income_brackets[index])))
	for tax_id: Variant in tax_rates.keys():
		var definition: Dictionary = taxes[tax_id]
		budget.tax_rates[tax_id] = clampf(float(tax_rates[tax_id]), float(definition.get("min", 0.0)),
			float(definition.get("max", tax_rates[tax_id])))
	for line_id: Variant in spending.keys():
		budget.spending[line_id] = clampf(float(spending[line_id]), 0.0,
			float((lines[line_id] as Dictionary).get("max", spending[line_id])))
	budget.monetary_financing = clampf(monetary_financing, 0.0, float(settings.get("max_monetary_financing", 0.0)))
	BudgetSystem.update_budget(state.get_country(str(issuer)), state)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["income_brackets"] = income_brackets
	data["tax_rates"] = tax_rates
	data["spending"] = spending
	data["monetary_financing"] = monetary_financing
	return data

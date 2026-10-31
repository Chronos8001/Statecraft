class_name BudgetState
extends RefCounted
## Budget de l'État d'un pays : taux des impôts, dépenses par poste (en % du PIB), création monétaire.
## Les valeurs de départ sont gardées : les recettes et les effets se calculent par rapport à elles.

## Taux des tranches de l'impôt sur le revenu (%).
var income_brackets: Array[float] = []
var start_income_brackets: Array[float] = []
## Taux des autres impôts (impôt → % ou $/t), et taux de départ.
var tax_rates: Dictionary = {}
var start_tax_rates: Dictionary = {}
## Recettes par point de taux au départ (% du PIB) ; pour l'impôt sur le revenu, par point de taux moyen.
var revenue_per_point: Dictionary = {}
## Dépenses par poste (% du PIB) et dépenses de départ.
var spending: Dictionary = {}
var start_spending: Dictionary = {}
## Création monétaire (% du PIB par an) : finance le déficit sans emprunter, au prix de l'inflation.
var monetary_financing: float = 0.0

## Calculés chaque mois : recettes par impôt (% du PIB) et effets du budget (croissance, groupes…).
var revenues: Dictionary = {}
var effects: Dictionary = {}


func total_revenue() -> float:
	var total := 0.0
	for value: Variant in revenues.values():
		total += float(value)
	return total


func total_spending() -> float:
	var total := 0.0
	for value: Variant in spending.values():
		total += float(value)
	return total

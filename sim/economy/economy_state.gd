class_name EconomyState
extends RefCounted
## Économie d'un pays pendant la partie.
##
## Unités : les montants en monnaie locale sont exprimés en « milliards d'unités de départ »,
## c'est-à-dire en milliards de dollars au taux de change du 1er janvier 2026. Le PIB réel est
## en dollars constants de 2026. Les taux et pourcentages sont en points (2.5 = 2,5 %).

var currency: String = ""
var population: int = 0
## PIB réel (milliards de dollars de 2026).
var real_gdp: float = 0.0
## Niveau des prix en monnaie locale (1 au départ).
var price_level: float = 1.0
## Part de chaque secteur dans le PIB (somme = 1).
var sectors: Dictionary = {}

## Croissance réelle annualisée du dernier mois, croissance potentielle et écart de production (%).
var growth: float = 0.0
var potential_growth: float = 0.0
var output_gap: float = 0.0
var inflation: float = 0.0
var unemployment: float = 0.0
var natural_unemployment: float = 0.0
## Taux réel neutre du pays (calé au départ pour que l'économie parte à l'équilibre).
var neutral_real_rate: float = 0.0

## Dette en monnaie locale (unités de départ) et en devises (milliards de dollars).
var local_debt: float = 0.0
var foreign_debt: float = 0.0
## Taux effectifs moyens payés sur la dette existante (%).
var local_debt_rate: float = 0.0
var foreign_debt_rate: float = 0.0
## Rapport entre le taux payé sur la dette et le taux du marché (inférieur à 1 pour les pays dont la dette
## a été émise à de meilleures conditions que les taux actuels ; calé au départ).
var debt_rate_factor: float = 1.0
## Solde primaire (hors intérêts) en % du PIB, calculé chaque mois à partir du budget.
var primary_balance: float = 0.0
## Solde primaire et dette (rapport au PIB) au départ : références de l'impulsion budgétaire et de l'IA.
var start_primary_balance: float = 0.0
var start_debt_ratio: float = 0.0
var budget: BudgetState = BudgetState.new()
## Effets économiques du budget (points de croissance, de chômage, d'inflation), recopiés par BudgetSystem.
var budget_growth: float = 0.0
var budget_unemployment: float = 0.0
var budget_inflation: float = 0.0
## Effets des prix des ressources (points de croissance et d'inflation), recopiés par ResourceSystem.
var resource_growth: float = 0.0
var resource_inflation: float = 0.0
## Valeur de la production de ressources par rapport à la normale (1 au départ) : indexe les taxes
## sur les ressources.
var resource_price_index: float = 1.0
## Effets du commerce (surtaxes, embargos, accords quittés) : points de croissance et d'inflation,
## recettes douanières supplémentaires en % du PIB. Recopiés par TradeSystem.
var trade_growth: float = 0.0
var trade_inflation: float = 0.0
var trade_customs: float = 0.0
## Effet des coupures d'électricité sur la croissance (points) et dépenses des chantiers (% du PIB).
var energy_growth: float = 0.0
var project_spending: float = 0.0
## Propriété publique, IDE et fonds souverain ; effets sur la croissance (points) et les recettes (% du PIB).
var investment: InvestmentState = InvestmentState.new()
var investment_growth: float = 0.0
var public_revenue: float = 0.0
## Part du fonds souverain déduite de la dette pour la note (dette nette).
var fund_rating_weight: float = 0.0

## Note souveraine (indice dans CreditRating) et écart propre au pays, calé au départ.
var rating: int = 0
var rating_estimated: bool = false
var rating_offset: float = 0.0
## Mois de l'année (0 à rating_review_months - 1) où la note est revue.
var review_phase: int = 0

## Mois restants de crise de la dette, de programme du FMI et d'attente avant un nouveau programme.
var crisis_months: int = 0
var imf_months: int = 0
var imf_cooldown: int = 0
## Effort budgétaire cumulé exigé par le FMI (points de PIB ajoutés au solde primaire).
var austerity: float = 0.0


## PIB nominal en monnaie locale (unités de départ).
func nominal_gdp() -> float:
	return real_gdp * price_level


func gdp_usd(currency_state: CurrencyState) -> float:
	return nominal_gdp() / currency_state.fx_factor()


func gdp_per_capita_usd(currency_state: CurrencyState) -> float:
	return gdp_usd(currency_state) * 1.0e9 / population if population > 0 else 0.0


## Dette totale en monnaie locale (la dette en devises suit le taux de change).
func total_debt(currency_state: CurrencyState) -> float:
	return local_debt + foreign_debt * currency_state.fx_factor()


func debt_ratio(currency_state: CurrencyState) -> float:
	var gdp := nominal_gdp()
	return total_debt(currency_state) / gdp if gdp > 0.0 else 0.0


func foreign_debt_share(currency_state: CurrencyState) -> float:
	var total := total_debt(currency_state)
	return foreign_debt * currency_state.fx_factor() / total if total > 0.0 else 0.0


## Intérêts annuels en % du PIB.
func interest_burden(currency_state: CurrencyState) -> float:
	var gdp := nominal_gdp()
	if gdp <= 0.0:
		return 0.0
	var interest := local_debt * local_debt_rate + foreign_debt * currency_state.fx_factor() * foreign_debt_rate
	return interest / gdp


## Charge réelle de la dette : intérêts moins l'érosion par l'inflation (% du PIB).
func real_interest_burden(currency_state: CurrencyState) -> float:
	return interest_burden(currency_state) - inflation * debt_ratio(currency_state)


## Solde budgétaire total (primaire moins intérêts) en % du PIB.
func budget_balance(currency_state: CurrencyState) -> float:
	return primary_balance - interest_burden(currency_state)


func in_crisis() -> bool:
	return crisis_months > 0


func in_imf_program() -> bool:
	return imf_months > 0


## Dette nette du fonds souverain (en partie), rapportée au PIB : utilisée pour la note.
func rating_debt_ratio(currency_state: CurrencyState) -> float:
	var gdp := nominal_gdp()
	if gdp <= 0.0:
		return 0.0
	var fund := investment.sovereign_fund * currency_state.fx_factor() * fund_rating_weight
	return maxf(total_debt(currency_state) - fund, 0.0) / gdp

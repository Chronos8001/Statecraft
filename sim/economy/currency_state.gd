class_name CurrencyState
extends RefCounted
## Monnaie pendant la partie : taux de change, taux directeur de sa banque centrale, ancrage éventuel.
## Une union monétaire (euro, franc CFA) n'a qu'une monnaie et qu'une banque centrale.

var id: String = ""
var code: String = ""
## Unités de cette monnaie pour un dollar.
var usd_rate: float = 1.0
var start_usd_rate: float = 1.0
var policy_rate: float = 0.0
var inflation_target: float = 2.0
var independent: bool = true
## Monnaie d'ancrage ("" = change flottant).
var peg: String = ""
## Écart de taux directeur avec la monnaie d'ancrage, conservé tant que l'ancrage tient.
var peg_spread: float = 0.0
## Taux réel neutre de la banque centrale (calé au départ, puis rapproché du neutre commun).
var neutral_real_rate: float = 0.0
## Écart de taux réel avec la monnaie de référence au départ (sert au calcul du change).
var start_real_rate_gap: float = 0.0
## Dépréciation du dernier mois, en % (négative si la monnaie s'apprécie).
var last_depreciation: float = 0.0
## Pays qui utilisent cette monnaie, triés.
var members: Array[String] = []
## Pays dont le gouvernement contrôle la banque centrale ("" pour une union monétaire).
var issuer: String = ""
## Inflation et écart de production moyens des membres (pondérés par le PIB), mis à jour chaque mois.
var inflation: float = 0.0
var output_gap: float = 0.0


func is_pegged() -> bool:
	return not peg.is_empty()


## Valeur d'un dollar en « unités de départ » de cette monnaie : 1 au départ, plus si la monnaie baisse.
func fx_factor() -> float:
	return usd_rate / start_usd_rate if start_usd_rate > 0.0 else 1.0

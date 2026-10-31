class_name CreditRating
extends RefCounted
## Échelle des notes souveraines (defines.economy.ratings), de la plus mauvaise (indice 0, défaut)
## à la meilleure. Chaque cran a sa prime de risque sur le taux d'emprunt.

const UNKNOWN := -1

var _ids: Array[String] = []
var _spreads: Array[float] = []


func _init(settings: Dictionary) -> void:
	for id: Variant in settings.get("ratings", []):
		_ids.append(str(id))
	for spread: Variant in settings.get("rating_spreads", []):
		_spreads.append(float(spread))


func index_of(id: String) -> int:
	return _ids.find(id)


func id_of(index: int) -> String:
	return _ids[clampi(index, 0, _ids.size() - 1)] if not _ids.is_empty() else ""


func best() -> int:
	return _ids.size() - 1


func clamp_index(value: float) -> int:
	return clampi(roundi(value), 0, best())


## Prime de risque (points de pourcentage) ajoutée au taux sans risque.
func spread(index: int) -> float:
	if _spreads.is_empty():
		return 0.0
	return _spreads[clampi(index, 0, _spreads.size() - 1)]


func is_default(index: int) -> bool:
	return index == 0

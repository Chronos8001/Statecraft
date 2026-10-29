class_name DateFormat
extends RefCounted
## Mise en forme des dates selon la langue : « 1 janvier 2026 · 08:00 » / « January 1, 2026 · 08:00 ».

const MONTH_KEY := "MONTH_%d"


static func month_key(month: int) -> String:
	return MONTH_KEY % month


## month_name : nom du mois déjà traduit.
static func long_date(date: GameDate, month_name: String, locale: String) -> String:
	if locale.begins_with("fr"):
		var day := "1er" if date.day == 1 else str(date.day)
		return "%s %s %d · %02d:00" % [day, month_name, date.year, date.hour]
	return "%s %d, %d · %02d:00" % [month_name, date.day, date.year, date.hour]

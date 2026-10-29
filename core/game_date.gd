class_name GameDate
extends RefCounted
## Date de jeu (calendrier grégorien, résolution d'une heure).

const HOURS_PER_DAY := 24
const DAYS_PER_WEEK := 7
const MONTHS_PER_YEAR := 12
const MONTH_DAYS: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

## Drapeaux renvoyés par advance_hour() quand une période se termine.
const CHANGED_DAY := 1
const CHANGED_WEEK := 2
const CHANGED_MONTH := 4
const CHANGED_YEAR := 8

var year: int
var month: int
var day: int
var hour: int


func _init(p_year: int = 1, p_month: int = 1, p_day: int = 1, p_hour: int = 0) -> void:
	year = p_year
	month = p_month
	day = p_day
	hour = p_hour


static func from_dict(data: Dictionary) -> GameDate:
	return GameDate.new(int(data.get("year", 1)), int(data.get("month", 1)), int(data.get("day", 1)), int(data.get("hour", 0)))


static func is_leap_year(p_year: int) -> bool:
	return (p_year % 4 == 0 and p_year % 100 != 0) or p_year % 400 == 0


static func days_in_month(p_year: int, p_month: int) -> int:
	if p_month == 2 and is_leap_year(p_year):
		return 29
	return MONTH_DAYS[p_month - 1]


func to_dict() -> Dictionary:
	return {"year": year, "month": month, "day": day, "hour": hour}


func copy() -> GameDate:
	return GameDate.new(year, month, day, hour)


func is_valid() -> bool:
	return month >= 1 and month <= MONTHS_PER_YEAR \
		and day >= 1 and day <= days_in_month(year, month) \
		and hour >= 0 and hour < HOURS_PER_DAY


## Avance d'une heure. Renvoie une combinaison de drapeaux CHANGED_* (0 si même jour).
func advance_hour() -> int:
	hour += 1
	if hour < HOURS_PER_DAY:
		return 0
	hour = 0
	day += 1
	var flags := CHANGED_DAY
	if day > days_in_month(year, month):
		day = 1
		month += 1
		flags |= CHANGED_MONTH
		if month > MONTHS_PER_YEAR:
			month = 1
			year += 1
			flags |= CHANGED_YEAR
	if day_of_week() == 0:
		flags |= CHANGED_WEEK
	return flags


## Nombre de jours écoulés depuis le 1er janvier de l'an 1.
@warning_ignore("integer_division")
func to_day_number() -> int:
	var past_years := year - 1
	var days := past_years * 365 + past_years / 4 - past_years / 100 + past_years / 400
	for past_month: int in range(1, month):
		days += days_in_month(year, past_month)
	return days + day - 1


## 0 = lundi … 6 = dimanche (le 1er janvier de l'an 1 était un lundi).
func day_of_week() -> int:
	return to_day_number() % DAYS_PER_WEEK


## -1 si cette date est avant other, 0 si égale, 1 si après.
func compare(other: GameDate) -> int:
	var a := to_day_number() * HOURS_PER_DAY + hour
	var b := other.to_day_number() * HOURS_PER_DAY + other.hour
	return signi(a - b)


func format_iso() -> String:
	return "%04d-%02d-%02d %02d:00" % [year, month, day, hour]

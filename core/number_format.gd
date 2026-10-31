class_name NumberFormat
extends RefCounted
## Mise en forme des nombres selon la langue : « 1 234 567 » en français, « 1,234,567 » en anglais.

const GROUP_SIZE := 3
const NO_BREAK_SPACE := " "
const GROUP_SEPARATORS := {"fr": NO_BREAK_SPACE, "en": ","}
const DEFAULT_SEPARATOR := ","
const DECIMAL_SEPARATORS := {"fr": ",", "en": "."}
const DEFAULT_DECIMAL_SEPARATOR := "."


static func integer(value: int, locale: String) -> String:
	var digits := str(absi(value))
	var separator: String = GROUP_SEPARATORS.get(locale.left(2), DEFAULT_SEPARATOR)
	var parts := PackedStringArray()
	var end := digits.length()
	while end > GROUP_SIZE:
		parts.insert(0, digits.substr(end - GROUP_SIZE, GROUP_SIZE))
		end -= GROUP_SIZE
	parts.insert(0, digits.substr(0, end))
	return ("-" if value < 0 else "") + separator.join(parts)


## Nombre à virgule : « 1 234,5 » en français, « 1,234.5 » en anglais.
static func decimal(value: float, decimals: int, locale: String) -> String:
	var factor := pow(10.0, decimals)
	var scaled := roundi(absf(value) * factor)
	var whole := scaled / roundi(factor)
	var text := integer(whole, locale)
	if decimals > 0:
		var fraction := str(scaled % roundi(factor)).pad_zeros(decimals)
		text += str(DECIMAL_SEPARATORS.get(locale.left(2), DEFAULT_DECIMAL_SEPARATOR)) + fraction
	return ("-" if value < 0.0 and scaled > 0 else "") + text

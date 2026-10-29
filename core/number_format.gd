class_name NumberFormat
extends RefCounted
## Mise en forme des nombres selon la langue : « 1 234 567 » en français, « 1,234,567 » en anglais.

const GROUP_SIZE := 3
const NO_BREAK_SPACE := " "
const GROUP_SEPARATORS := {"fr": NO_BREAK_SPACE, "en": ","}
const DEFAULT_SEPARATOR := ","


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

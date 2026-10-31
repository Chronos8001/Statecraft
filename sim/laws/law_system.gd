class_name LawSystem
extends SimSystem
## Lois, une fois par mois : délais avant de remettre une loi en jeu. Les effets des lois sont recalculés à
## chaque changement (ChangeLawCommand) et lus par la société, l'économie et le budget.

const PRIORITY := -40


func get_id() -> StringName:
	return &"laws"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	for country: CountryState in state.countries.values():
		for law_id: Variant in country.law_cooldowns.keys():
			country.law_cooldowns[law_id] = maxi(int(country.law_cooldowns[law_id]) - 1, 0)


static func settings_of(state: SimState) -> Dictionary:
	return (state.politics_definitions.get("settings", {}) as Dictionary).get("laws", {})


## Effets des lois par rapport au départ, recopiés dans l'économie, le budget et la société.
static func apply_effects(country: CountryState, state: SimState) -> void:
	var effects := LawModel.aggregate(state.politics_definitions.get("laws", {}), country.laws, country.start_laws)
	country.law_effects = effects
	country.economy.law_growth = float(effects.get("growth", 0.0))
	country.economy.law_spending = float(effects.get("budget", 0.0))
	var society := country.society
	society.corruption = clampf(society.start_corruption + float(effects.get("corruption", 0.0)), 0.0,
		SocietyModel.PERCENT)

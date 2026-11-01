class_name SocietySystem
extends SimSystem
## Société, une fois par mois, après l'économie : satisfaction des groupes sociaux, soutien populaire,
## stabilité et légitimité. Une stabilité en baisse freine la croissance du mois suivant.

const PRIORITY := 10


func get_id() -> StringName:
	return &"society"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.society_definitions.is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		update_country(state.countries[tag], state)


## Écarts par rapport au départ auxquels réagissent les groupes.
## L'inflation est plafonnée avant comparaison : au-delà, une baisse ne se ressent pas encore.
static func changes(country: CountryState, settings: Dictionary) -> Dictionary:
	var economy := country.economy
	var society := country.society
	var investment := economy.investment
	var cap := float(settings.get("inflation_cap", INF))
	return {
		"unemployment": economy.unemployment - society.start_unemployment,
		"inflation": minf(economy.inflation, cap) - minf(society.start_inflation, cap),
		"growth": economy.growth - society.start_growth,
		"blackout": country.energy.blackout,
		"public_ownership": InvestmentModel.public_shift(economy.sectors, investment.public_ownership,
			investment.start_public_ownership),
	}


static func update_country(country: CountryState, state: SimState) -> void:
	var society := country.society
	if society.group_shares.is_empty():
		return
	var groups: Dictionary = state.society_definitions.get("groups", {})
	var settings: Dictionary = state.society_definitions.get("settings", {})
	var bounds: Array = settings.get("satisfaction_bounds", [0.0, SocietyModel.PERCENT])
	var rate := float(settings.get("satisfaction_adjustment", 1.0))
	var max_loss := float(settings.get("max_loss", INF))
	var max_gain := float(settings.get("max_gain", INF))
	var gain_factor := float(settings.get("gain_factor", 1.0))
	var budget_effects: Dictionary = country.economy.budget.effects
	var budget_groups: Dictionary = budget_effects.get(BudgetModel.GROUPS, {})
	var current := changes(country, settings)
	var law_groups: Dictionary = country.law_effects.get(LawModel.GROUPS, {})
	var cabinet_groups: Dictionary = country.cabinet_effects.get(GovernmentModel.GROUPS, {})
	var military_effects := MilitarySystem.effects(country)
	var military_groups: Dictionary = military_effects.get(MilitaryModel.GROUPS, {})
	for group_id: Variant in society.satisfaction.keys():
		var reactions: Dictionary = (groups.get(group_id, {}) as Dictionary).get("reactions", {})
		var target := SocietyModel.satisfaction_target(float(society.start_satisfaction[group_id]),
			float(budget_groups.get(group_id, 0.0)) + float(society.bonuses.get(group_id, 0.0))
			+ float(law_groups.get(group_id, 0.0)) + float(cabinet_groups.get(group_id, 0.0))
			+ float(country.media_effects.get("groups", 0.0)) + float(military_groups.get(group_id, 0.0)),
			SocietyModel.reaction(reactions, current, max_loss, max_gain,
			gain_factor), bounds)
		society.satisfaction[group_id] = SocietyModel.approach(float(society.satisfaction[group_id]), target, rate)
	society.support = SocietyModel.weighted(society.satisfaction, society.group_shares)
	var stability_settings: Dictionary = settings.get("stability", {})
	var stability_target := SocietyModel.stability_target(society, float(budget_effects.get("stability", 0.0))
		+ float(country.law_effects.get("stability", 0.0)) + emergency_stability(country, state)
		+ float(country.cabinet_effects.get("stability", 0.0)) + float(country.crisis_effects.get("stability", 0.0))
		+ country.aid_stability + country.ai_stability + float(military_effects.get("stability", 0.0)),
		stability_settings)
	society.stability = SocietyModel.approach(society.stability, stability_target,
		float(stability_settings.get("adjustment", 1.0)))
	var legitimacy_settings: Dictionary = settings.get("legitimacy", {})
	society.legitimacy = SocietyModel.approach(society.legitimacy, SocietyModel.legitimacy_target(society,
		legitimacy_settings, float(country.law_effects.get("legitimacy", 0.0))
		+ float(country.cabinet_effects.get("legitimacy", 0.0)) + float(country.crisis_effects.get("legitimacy", 0.0))),
		float(legitimacy_settings.get("adjustment", 1.0)))
	country.economy.society_growth = SocietyModel.growth_penalty(society, stability_settings)


## Stabilité gagnée tant que l'état d'urgence dure.
static func emergency_stability(country: CountryState, state: SimState) -> float:
	if country.politics.emergency_months <= 0:
		return 0.0
	return float(ConstitutionSystem.settings_of(state).get("emergency_stability", 0.0))


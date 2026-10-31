class_name MilitaryModel
extends RefCounted
## Modèle des forces armées (module remplaçable par un mod ou un DLC via MilitaryRegistry).
## Modèle de base, agrégé par branche :
## - équipement : le budget d'équipement (part de la défense + armes reçues) entretient un niveau ; plus de
##   budget qu'au départ fait monter le niveau, moins le fait baisser, lentement. Coût croissant :
##   niveau soutenable = niveau de départ + ln(budget / (budget de départ × indice des coûts)) / escalade ;
## - entraînement : suit la dépense par soldat, baisse quand on rappelle les réservistes ;
## - moral : suit la stabilité, monte un peu avec la mobilisation ;
## - mobilisation : rappelle des réservistes, freine la croissance, coûte la solde, mécontente la jeunesse
##   et les travailleurs ;
## - service militaire (loi) : une armée de conscription a plus de soldats et de réservistes, moins entraînés.
## Tout est neutre au départ (mobilisations réelles de 2026 et lois en vigueur comprises).

const BILLION := 1.0e9
const PERCENT := 100.0
const MONTHS_PER_YEAR := 12.0
const DEFENSE_LINE := "defense"
const GROUPS := "groups"


## Crée les forces de départ d'un pays à partir de ses données (« military » et « armed_forces »).
func setup_country(country: CountryState, data: Dictionary, state: SimState) -> void:
	var settings := state.military_settings
	var military := MilitaryState.new()
	var personnel: Dictionary = data.get("military", {})
	var forces: Dictionary = data.get("armed_forces", {})
	military.active_personnel = float(personnel.get("active_personnel", 0.0))
	military.reserve_personnel = float(personnel.get("reserve_personnel", 0.0))
	var source: Dictionary = forces.get("branches", {})
	for branch: Variant in settings.get("branches", []):
		if source.has(branch):
			military.branches[branch] = (source[branch] as Dictionary).duplicate()
			military.priorities[branch] = float((source[branch] as Dictionary).get("share", 0.0))
	normalize(military.priorities)
	military.start_branches = military.branches.duplicate(true)
	military.start_priorities = military.priorities.duplicate()
	military.special = (forces.get("special", {}) as Dictionary).duplicate()
	military.start_special = military.special.duplicate()
	military.nuclear_warheads = int(forces.get("nuclear_warheads", 0))
	var start_levels: Dictionary = (settings.get("mobilization", {}) as Dictionary).get("start", {})
	military.mobilization = int(start_levels.get(country.tag, 0))
	military.start_mobilization = military.mobilization
	military.start_conscription = str(country.laws.get(str(settings.get("conscription_law", "")), ""))
	military.start_stability = country.society.stability
	military.start_spend_per_soldier = spend_per_soldier(country, military, state)
	military.arms_flow = start_arms_flow(state, country.tag)
	military.arms_counted = float(state.diplomacy.arms_received.get(country.tag, 0.0))
	military.start_equipment = equipment_budget(country, military, state)
	country.military = military
	military.power = power(military, settings)


## Un mois : équipement, entraînement, moral, effets de la mobilisation et puissance.
func update_country(country: CountryState, state: SimState) -> void:
	var military := country.military
	if military == null or military.branches.is_empty():
		return
	var settings := state.military_settings
	var mobilization: Dictionary = settings.get("mobilization", {})
	if military.mobilization_cooldown > 0:
		military.mobilization_cooldown -= 1
	var received := float(state.diplomacy.arms_received.get(country.tag, 0.0))
	military.arms_flow = maxf(received - military.arms_counted, 0.0)
	military.arms_counted = received
	var equipment: Dictionary = settings.get("equipment", {})
	military.cost_index *= pow(1.0 + float(equipment.get("cost_growth", 0.0)) / PERCENT, 1.0 / MONTHS_PER_YEAR)
	var ratio := equipment_budget(country, military, state) / (military.start_equipment * military.cost_index) \
		if military.start_equipment > 0.0 else 1.0
	var training: Dictionary = settings.get("training", {})
	var morale: Dictionary = settings.get("morale", {})
	var soldier_ratio := spend_per_soldier(country, military, state) \
		/ (military.start_spend_per_soldier * military.cost_index) \
		if military.start_spend_per_soldier > 0.0 else 1.0
	var service := conscription_change(country, military, settings)
	var training_shift := float(training.get("per_log_ratio", 0.0)) * log(maxf(soldier_ratio, 0.01)) \
		- _change(training.get("mobilization_penalty", []), military) + float(service["training"])
	var morale_shift := float(morale.get("per_stability", 0.0)) * (country.society.stability - military.start_stability) \
		+ _change(morale.get("mobilization_bonus", []), military)
	for branch: String in military.branches.keys():
		var current: Dictionary = military.branches[branch]
		var start: Dictionary = military.start_branches[branch]
		var start_priority := float(military.start_priorities.get(branch, 0.0))
		var branch_ratio := ratio * float(military.priorities.get(branch, 0.0)) / start_priority \
			if start_priority > 0.0 else ratio
		var level_target := clampf(float(start["level"]) + log(maxf(branch_ratio, 0.01))
			/ float(equipment.get("escalation", 1.0)), float(equipment.get("min_level", 1.0)),
			float(equipment.get("max_level", 5.0)))
		current["level"] = _approach(float(current["level"]), level_target, float(equipment.get("adjustment", 1.0)))
		current["training"] = _approach(float(current["training"]), clampf(float(start["training"]) + training_shift,
			float(training.get("min", 0.0)), float(training.get("max", PERCENT))), float(training.get("adjustment", 1.0)))
		current["morale"] = _approach(float(current["morale"]), clampf(float(start["morale"]) + morale_shift,
			float(morale.get("min", 0.0)), float(morale.get("max", PERCENT))), float(morale.get("adjustment", 1.0)))
	update_special(country, military, settings.get("special", {}))
	military.effects = mobilization_effects(military, mobilization)
	country.economy.military_growth = float(military.effects.get("growth", 0.0))
	var pay := mobilization_cost(military, state)
	if pay != 0.0:
		InvestmentSystem.add_debt_usd(country, state, pay)
	military.power = power(military, settings)


## Service militaire : les effectifs rejoignent peu à peu ceux de l'option en vigueur (rapportés à l'option
## de départ). Renvoie l'écart d'entraînement par rapport au départ : {training}.
func conscription_change(country: CountryState, military: MilitaryState, settings: Dictionary) -> Dictionary:
	var rules: Dictionary = settings.get("conscription", {})
	var options: Dictionary = rules.get("options", {})
	var now: Dictionary = options.get(str(country.laws.get(str(settings.get("conscription_law", "")), "")), {})
	var start: Dictionary = options.get(military.start_conscription, {})
	if now.is_empty() or start.is_empty():
		return {"training": 0.0}
	var rate := float(rules.get("adjustment", 1.0))
	military.active_factor = _approach(military.active_factor, float(now.get("active", 1.0)) / float(start.get("active", 1.0)),
		rate)
	military.reserve_factor = _approach(military.reserve_factor, float(now.get("reserve", 1.0))
		/ float(start.get("reserve", 1.0)), rate)
	return {"training": float(now.get("training", 0.0)) - float(start.get("training", 0.0))}


## Capacités spéciales : suivent l'effort budgétaire de défense et de renseignement (effet « military » du budget).
func update_special(country: CountryState, military: MilitaryState, settings: Dictionary) -> void:
	var points := float(country.economy.budget.effects.get("military", 0.0))
	for key: Variant in military.special.keys():
		var target := clampf(float(military.start_special[key]) + points * float(settings.get("per_point", 0.0)), 0.0, PERCENT)
		military.special[key] = _approach(float(military.special[key]), target, float(settings.get("adjustment", 1.0)))


## Budget d'équipement du mois (milliards de dollars) : part équipement de la défense + armes reçues.
func equipment_budget(country: CountryState, military: MilitaryState, state: SimState) -> float:
	return defense_spending(country, state) / MONTHS_PER_YEAR * float(state.military_settings.get("equipment_share", 0.0)) \
		+ military.arms_flow


## Dépense de défense annuelle (milliards de dollars).
static func defense_spending(country: CountryState, state: SimState) -> float:
	return float(country.economy.budget.spending.get(DEFENSE_LINE, 0.0)) / PERCENT * TradeSystem.current_gdp(state, country.tag)


func spend_per_soldier(country: CountryState, military: MilitaryState, state: SimState) -> float:
	var personnel := military.personnel((state.military_settings.get("mobilization", {}) as Dictionary).get(
		"reserve_share", []))
	return defense_spending(country, state) * BILLION / personnel if personnel > 0.0 else 0.0


## Flux mensuel d'armes des programmes d'aide de 2026 (milliards de dollars).
static func start_arms_flow(state: SimState, tag: String) -> float:
	var flow := 0.0
	for program: Dictionary in state.diplomacy.aid_programs:
		var definition: Dictionary = state.aid_definitions.get(program["kind"], {})
		if str(program["recipient"]) == tag and bool(program.get("initial", false)) and bool(definition.get("military", false)):
			flow += float(program["amount"]) / MONTHS_PER_YEAR if int(program["total_months"]) > 1 else 0.0
	return flow


## Effets de la mobilisation par rapport au départ : {growth, stability, groups}.
static func mobilization_effects(military: MilitaryState, settings: Dictionary) -> Dictionary:
	var result := {"growth": _change(settings.get("growth", []), military),
		"stability": _change(settings.get("stability", []), military), GROUPS: {}}
	var groups: Array = settings.get(GROUPS, [])
	if groups.is_empty():
		return result
	var now: Dictionary = groups[clampi(military.mobilization, 0, groups.size() - 1)]
	var before: Dictionary = groups[clampi(military.start_mobilization, 0, groups.size() - 1)]
	var changes: Dictionary = result[GROUPS]
	for group_id: Variant in now.keys():
		changes[group_id] = float(now[group_id])
	for group_id: Variant in before.keys():
		changes[group_id] = float(changes.get(group_id, 0.0)) - float(before[group_id])
	return result


## Solde mensuelle des réservistes rappelés au-delà du départ (négative si on démobilise).
func mobilization_cost(military: MilitaryState, state: SimState) -> float:
	var settings: Dictionary = state.military_settings.get("mobilization", {})
	var reserve_share: Array = settings.get("reserve_share", [])
	var extra := military.reserves() * MilitaryState.level_value(reserve_share, military.mobilization) \
		- military.reserve_personnel * MilitaryState.level_value(reserve_share, military.start_mobilization)
	return extra * military.start_spend_per_soldier * float(settings.get("pay_share", 0.0)) / BILLION / MONTHS_PER_YEAR


## Puissance militaire : Σ effectifs de la branche × poids × niveau^exposant × entraînement × moral,
## majorée par les capacités spéciales.
func power(military: MilitaryState, settings: Dictionary) -> float:
	var rules: Dictionary = settings.get("power", {})
	if rules.is_empty():
		return 0.0
	var weights: Dictionary = rules.get("branch_weights", {})
	var personnel := military.personnel((settings.get("mobilization", {}) as Dictionary).get("reserve_share", []))
	var total := 0.0
	for branch: String in military.branches.keys():
		var values: Dictionary = military.branches[branch]
		total += personnel * float(values["share"]) * float(weights.get(branch, 1.0)) \
			* pow(float(values["level"]), float(rules.get("level_exponent", 1.0))) \
			* float(values["training"]) / float(rules.get("training_reference", 1.0)) \
			* float(values["morale"]) / float(rules.get("morale_reference", 1.0))
	var special_total := 0.0
	for value: Variant in military.special.values():
		special_total += float(value)
	var special_average := special_total / military.special.size() / PERCENT if not military.special.is_empty() else 0.0
	return total * (1.0 + float(rules.get("special_weight", 0.0)) * special_average) * float(rules.get("scale", 1.0))


## Niveau moyen d'équipement (pondéré par les effectifs des branches).
static func average_level(military: MilitaryState) -> float:
	var total := 0.0
	var shares := 0.0
	for values: Dictionary in military.branches.values():
		total += float(values["level"]) * float(values["share"])
		shares += float(values["share"])
	return total / shares if shares > 0.0 else 0.0


static func _change(values: Array, military: MilitaryState) -> float:
	return MilitaryState.level_value(values, military.mobilization) - MilitaryState.level_value(values, military.start_mobilization)


static func _approach(value: float, target: float, rate: float) -> float:
	return value + (target - value) * clampf(rate, 0.0, 1.0)


static func normalize(values: Dictionary) -> void:
	var total := 0.0
	for value: Variant in values.values():
		total += float(value)
	if total <= 0.0:
		return
	for key: Variant in values.keys():
		values[key] = float(values[key]) / total

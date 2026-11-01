class_name AiRaceSystem
extends SimSystem
## Course à l'IA, une fois par mois après la recherche :
## - niveau d'IA de chaque pays (0–100) : il tend vers une cible tirée des technologies de l'arbre IA et des
##   points de recherche, à une vitesse d'adoption réglée par la loi de régulation et le plan national d'IA ;
## - gains : croissance selon le niveau ; le pays en tête reçoit en plus croissance, recherche et cyber ;
## - risques : l'automatisation crée du chômage (résorbé peu à peu) ; la désinformation par IA pèse sur la
##   stabilité et agite les sondages, d'autant plus que les réseaux sociaux sont libres ;
## - le premier pays à atteindre l'IA générale fait un grand bond, la tension mondiale monte et ses rivaux
##   s'inquiètent.

const PRIORITY := -19
const PERCENT := 100.0
const EVENT_LEADER := &"ai_race_leader"
const EVENT_AGI := &"ai_general_reached"
const EVENT_PLAN := &"ai_plan_launched"
const RANKING_SIZE := 10


func get_id() -> StringName:
	return &"ai_race"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


static func rules_of(state: SimState) -> Dictionary:
	return ResearchSystem.settings_of(state).get("ai_race", {})


func on_month(state: SimState) -> void:
	if rules_of(state).is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		if country.research == null:
			continue
		if StringName(tag) != state.player_tag:
			_ai_plan(state, country)
		update_country(state, country)
	refresh_ranking(state)
	check_general_ai(state)
	for tag: String in tags:
		apply_effects(state, state.countries[tag])


## Niveau de départ : directement à sa cible.
static func setup_start(state: SimState) -> void:
	if rules_of(state).is_empty():
		return
	for country: CountryState in state.countries.values():
		if country.research != null:
			country.research.ai_level = target_level(state, country)
	refresh_ranking(state)
	for country: CountryState in state.countries.values():
		apply_effects(state, country)


# --- Niveau ------------------------------------------------------------------------------------------------------

## Cible : part des technologies de l'arbre IA connues et points de recherche (relatifs à une référence),
## plus le bonus du plan national.
static func target_level(state: SimState, country: CountryState) -> float:
	var rules := rules_of(state)
	var tree := str(rules.get("tree", ""))
	var total := 0
	var known := 0
	for tech_id: String in state.technology_definitions.keys():
		if str((state.technology_definitions[tech_id] as Dictionary).get("tree", "")) == tree:
			total += 1
			if country.research.is_known(tech_id):
				known += 1
	var tech_share := float(known) / float(total) if total > 0 else 0.0
	var points_share := minf(country.research.points / maxf(float(rules.get("points_reference", 1.0)), 1.0), 1.0)
	var target := PERCENT * (float(rules.get("tech_weight", 0.0)) * tech_share
		+ float(rules.get("points_weight", 0.0)) * points_share)
	if country.research.ai_plan_months > 0:
		target += float((rules.get("plan", {}) as Dictionary).get("target", 0.0))
	return clampf(target, 0.0, PERCENT)


static func regulation(state: SimState, country: CountryState) -> Dictionary:
	var rules := rules_of(state)
	var option := str(country.laws.get(str(rules.get("law", "")), ""))
	return (rules.get("regulation", {}) as Dictionary).get(option, {})


static func adoption_speed(state: SimState, country: CountryState) -> float:
	var rules := rules_of(state)
	var speed := float(rules.get("adoption", 0.0)) * float(regulation(state, country).get("adoption", 1.0))
	if country.research.ai_plan_months > 0:
		speed *= 1.0 + float((rules.get("plan", {}) as Dictionary).get("adoption", 0.0))
	return speed


## Un mois : plan (coût), niveau vers sa cible, chômage d'automatisation créé puis résorbé.
static func update_country(state: SimState, country: CountryState) -> void:
	var rules := rules_of(state)
	var research := country.research
	if research.ai_plan_months > 0:
		var plan: Dictionary = rules.get("plan", {})
		InvestmentSystem.add_debt_usd(country, state, float(plan.get("cost_share", 0.0)) / PERCENT
			* TradeSystem.current_gdp(state, country.tag))
	var before := research.ai_level
	research.ai_level += (target_level(state, country) - research.ai_level) * minf(adoption_speed(state, country), 1.0)
	if research.ai_plan_months > 0:
		research.ai_plan_months -= 1
	var risk := float(regulation(state, country).get("risk", 1.0))
	var gained := maxf(research.ai_level - before, 0.0)
	research.ai_displaced = minf(research.ai_displaced * (1.0 - float(rules.get("reabsorb", 0.0)))
		+ gained * float(rules.get("displacement", 0.0)) * risk, float(rules.get("max_displaced", 0.0)))


# --- Classement, IA générale ---------------------------------------------------------------------------------

static func refresh_ranking(state: SimState) -> void:
	var levels: Array = []
	for country: CountryState in state.countries.values():
		if country.research != null:
			levels.append([country.research.ai_level, country.tag])
	levels.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0]) if not is_equal_approx(float(a[0]), float(b[0])) else str(a[1]) < str(b[1]))
	var previous := leader(state)
	state.ai_ranking.clear()
	for entry: Array in levels.slice(0, RANKING_SIZE):
		state.ai_ranking.append(str(entry[1]))
	if not previous.is_empty() and leader(state) != previous:
		state.add_event(EVENT_LEADER, leader(state), {"previous": previous})


static func leader(state: SimState) -> String:
	return state.ai_ranking[0] if not state.ai_ranking.is_empty() else ""


## Rang d'un pays (1 = en tête), 0 s'il est hors du classement affiché.
static func rank(state: SimState, tag: String) -> int:
	return state.ai_ranking.find(tag) + 1


## Le premier pays à connaître l'IA générale (le plus avancé si plusieurs le même mois) fait un grand bond.
static func check_general_ai(state: SimState) -> void:
	if not state.agi_first.is_empty():
		return
	var agi: Dictionary = rules_of(state).get("agi", {})
	var tech := str(agi.get("tech", ""))
	var first: CountryState = null
	for country: CountryState in state.countries.values():
		if country.research != null and country.research.is_known(tech) \
				and (first == null or country.research.ai_level > first.research.ai_level):
			first = country
	if first == null:
		return
	state.agi_first = first.tag
	ResearchSystem.apply_effects(state, first, agi.get("effects", {}))
	TensionSystem.add(state, float(agi.get("tension", 0.0)))
	for tag: String in state.countries.keys():
		if tag != first.tag and state.diplomacy.relation(tag, first.tag) < 0.0:
			state.diplomacy.change_relation(tag, first.tag, float(agi.get("rival_relation", 0.0)))
	state.add_event(EVENT_AGI, first.tag, {})


# --- Effets --------------------------------------------------------------------------------------------------

## Croissance, chômage, stabilité, volatilité des sondages ; bonus de recherche et de cyber du pays en tête.
static func apply_effects(state: SimState, country: CountryState) -> void:
	var research := country.research
	if research == null or country.economy == null:
		return
	var rules := rules_of(state)
	var share := research.ai_level / PERCENT
	var policy := regulation(state, country)
	var risk := float(policy.get("risk", 1.0))
	country.economy.ai_growth = share * float(rules.get("growth_max", 0.0)) * float(policy.get("growth", 1.0))
	country.economy.ai_unemployment = research.ai_displaced
	var disinformation: Dictionary = rules.get("disinformation", {})
	var networks := str(country.laws.get(str(disinformation.get("networks_law", "")), ""))
	var exposure := share * risk * float((disinformation.get("networks", {}) as Dictionary).get(networks, 1.0))
	country.ai_stability = -exposure * float(disinformation.get("stability", 0.0))
	country.ai_volatility = exposure * float(disinformation.get("volatility", 0.0))
	var bonus: Dictionary = rules.get("leader", {}) if leader(state) == country.tag else {}
	country.economy.ai_growth += float(bonus.get("growth", 0.0))
	research.ai_research = float(bonus.get("research", 0.0))
	research.ai_cyber = float(bonus.get("cyber", 0.0))
	if country.military != null:
		country.military.tech_special["cyber"] = research.effect(ResearchSystem.SPECIAL_PREFIX + "cyber") + research.ai_cyber


# --- Plan national d'IA --------------------------------------------------------------------------------------

static func plan_refusal(state: SimState, tag: String) -> String:
	var country := state.get_country(tag)
	if country == null or country.research == null or rules_of(state).is_empty():
		return "RESEARCH_INVALID"
	if country.research.ai_plan_months > 0:
		return "AI_PLAN_ACTIVE"
	return ""


static func launch_plan(state: SimState, tag: String) -> void:
	var country := state.get_country(tag)
	country.research.ai_plan_months = int((rules_of(state).get("plan", {}) as Dictionary).get("months", 0))
	state.add_event(EVENT_PLAN, tag, {})


## Coût mensuel du plan, en milliards de dollars.
static func plan_cost(state: SimState, tag: String) -> float:
	return float((rules_of(state).get("plan", {}) as Dictionary).get("cost_share", 0.0)) / PERCENT \
		* TradeSystem.current_gdp(state, tag)


static func _ai_plan(state: SimState, country: CountryState) -> void:
	var plan: Dictionary = rules_of(state).get("plan", {})
	if country.research.ai_plan_months <= 0 and country.research.points >= float(plan.get("ai_min_points", INF)) \
			and state.rng.randf() < float(plan.get("ai_chance", 0.0)):
		launch_plan(state, country.tag)

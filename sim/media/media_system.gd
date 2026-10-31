class_name MediaSystem
extends SimSystem
## Médias et opinion, une fois par mois, avant la société :
## - la liberté de la presse (loi) règle la découverte des fraudes et scandales ;
## - la liberté des réseaux sociaux (loi) règle la volatilité des sondages ;
## - la propagande coûte chaque mois, satisfait les groupes et soutient le parti au pouvoir, plus efficace quand
##   la presse est muselée, mais elle use la légitimité d'une démocratie à la presse libre.

const PRIORITY := 6
const EVENT_DISINFORMATION := &"disinformation"
const KIND_DESTABILIZE := "destabilize"
const KIND_SMEAR := "smear_opposition"


func get_id() -> StringName:
	return &"media"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	if state.politics_definitions.is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		update_country(state.countries[tag], state)


static func settings_of(state: SimState) -> Dictionary:
	return (state.politics_definitions.get("settings", {}) as Dictionary).get("media", {})


static func update_country(country: CountryState, state: SimState) -> void:
	var settings := settings_of(state)
	refresh_media(country, settings)
	if country.disinformation_cooldown > 0:
		country.disinformation_cooldown -= 1
	var level := country.propaganda_level
	var propaganda: Dictionary = settings.get("propaganda", {})
	country.media_effects = {}
	country.politics.propaganda_bonus = 0.0
	if level <= 0:
		return
	var cost := float(_level_value(propaganda, "cost_share", level)) / SocietyModel.PERCENT \
		* TradeSystem.current_gdp(state, country.tag)
	InvestmentSystem.add_debt_usd(country, state, cost)
	var control := 1.0 + float(propaganda.get("control_effect", 0.0)) * (1.0 - country.politics.media_factor)
	country.media_effects["groups"] = _level_value(propaganda, "group_bonus", level) * control
	country.politics.propaganda_bonus = _level_value(propaganda, "poll_bonus", level) * control
	if country.politics.democratic:
		country.society.start_legitimacy -= _level_value(propaganda, "backfire_legitimacy", level) \
			* country.politics.media_factor


static func _level_value(settings: Dictionary, key: String, level: int) -> float:
	var values: Array = settings.get(key, [])
	return float(values[clampi(level, 0, values.size() - 1)]) if not values.is_empty() else 0.0


## Facteurs tirés des lois : découverte des scandales (presse) et volatilité des sondages (réseaux).
static func refresh_media(country: CountryState, settings: Dictionary) -> void:
	var press := str(country.laws.get(str(settings.get("press_law", "")), ""))
	var networks := str(country.laws.get(str(settings.get("networks_law", "")), ""))
	country.politics.media_factor = float((settings.get("press_factor", {}) as Dictionary).get(press, 1.0))
	country.politics.volatility = float((settings.get("network_volatility", {}) as Dictionary).get(networks, 1.0))


## Opération de désinformation. Renvoie true si elle a été démasquée.
static func disinformation(country: CountryState, state: SimState, target_tag: String, kind: String) -> bool:
	var settings: Dictionary = settings_of(state).get("disinformation", {})
	var target := state.get_country(target_tag)
	InvestmentSystem.add_debt_usd(country, state, float(settings.get("cost_share", 0.0)) / SocietyModel.PERCENT
		* TradeSystem.current_gdp(state, country.tag))
	country.disinformation_cooldown = int(settings.get("cooldown_months", 0))
	if kind == KIND_SMEAR:
		var opposition := _main_opposition(country.politics)
		if opposition != null:
			opposition.drift -= float(settings.get("smear_drift", 0.0))
	elif target != null:
		target.society.stability = maxf(target.society.stability - float(settings.get("target_stability", 0.0)), 0.0)
		for group_id: Variant in target.society.satisfaction.keys():
			var points := float(settings.get("target_bonus", 0.0))
			target.society.bonuses[group_id] = float(target.society.bonuses.get(group_id, 0.0)) + points
			target.crisis_bonuses.append({"group": str(group_id), "points": points,
				"months_left": int(settings.get("target_months", 1))})
	var watcher := target if kind == KIND_DESTABILIZE and target != null else country
	var exposed := state.rng.randf() < float(settings.get("exposure", 0.0)) * watcher.politics.media_factor
	if exposed:
		country.society.start_legitimacy -= float(settings.get("own_legitimacy", 0.0))
	state.add_event(EVENT_DISINFORMATION, country.tag, {"target": target_tag, "kind": kind, "exposed": exposed})
	return exposed


static func _main_opposition(politics: PoliticsState) -> PartyState:
	var best: PartyState = null
	for party: PartyState in politics.parties.values():
		if not politics.is_in_government(party.id) and (best == null or party.poll > best.poll):
			best = party
	return best

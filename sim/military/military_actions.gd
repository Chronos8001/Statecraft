class_name MilitaryActions
extends RefCounted
## Actions ponctuelles : frappes de missiles, opérations spéciales, cyberattaques. Chacune a un coût, une chance
## de réussite et des effets ; les frappes et opérations spéciales demandent d'être en guerre, les cyberattaques
## sont possibles en paix (déniables, mais elles peuvent être découvertes).
##
## Frappe (une salve du stock de missiles) : chance = base + poids × (jauge missiles - défense aérienne de la
## cible) / 100 ; cibles : un bâtiment (détruit), les infrastructures d'une province (ravitaillement), un front
## (camp ennemi affaibli quelques jours). Une province très peuplée frappée : victimes civiles, opinion du monde.
## Opération spéciale : chance selon les forces spéciales des deux pays ; sabotage d'un bâtiment ou raid sur un
## front ; un échec use les forces spéciales.
## Cyberattaque : chance selon les jauges cyber ; économie (croissance), réseau électrique (croissance, coupure)
## ou armée (moral) ; découverte possible (plus probable en cas d'échec) : relations, confiance, tension.
## Stock de missiles = jauge × salves par point, reconstitué chaque mois.

const STRIKE := "missile_strike"
const SPECIAL := "special_operation"
const CYBER := "cyberattack"
const BUILDING := "building"
const INFRASTRUCTURE := "infrastructure"
const FRONT := "front"
const ECONOMY := "economy"
const GRID := "grid"
const ARMY := "military"
const KINDS := {STRIKE: [BUILDING, INFRASTRUCTURE, FRONT], SPECIAL: [BUILDING, FRONT], CYBER: [ECONOMY, GRID, ARMY]}
const EVENT_ACTION := &"military_action"
const PERCENT := 100.0
const MAX_FRONT_PENALTY := 0.9


static func settings_of(state: SimState) -> Dictionary:
	return state.military_settings.get("actions", {})


static func gauge(state: SimState, tag: String, key: String) -> float:
	var country := state.get_country(tag)
	if country == null or country.military == null:
		return 0.0
	return float(country.military.special.get(key, 0.0))


static func max_missiles(state: SimState, tag: String) -> float:
	return gauge(state, tag, "missiles") * float((settings_of(state).get("missiles", {}) as Dictionary).get(
		"stock_per_point", 0.0))


## Défense aérienne d'un pays (0 à 100) : niveau de son aviation et jauge de missiles.
static func air_defense(state: SimState, tag: String) -> float:
	var country := state.get_country(tag)
	if country == null or country.military == null:
		return 0.0
	var rules: Dictionary = settings_of(state).get("air_defense", {})
	var air: Dictionary = country.military.branches.get("air", {})
	return clampf(float(air.get("level", 0.0)) * float(rules.get("air_level_weight", 0.0))
		+ gauge(state, tag, "missiles") * float(rules.get("missiles_weight", 0.0)), 0.0, PERCENT)


static func setup_start(state: SimState) -> void:
	state.front_penalties.clear()
	state.infrastructure_damage.clear()
	state.attack_effects.clear()
	for tag: String in state.countries.keys():
		var country: CountryState = state.countries[tag]
		if country.military != null:
			country.military.missile_stock = max_missiles(state, tag)
			country.military.action_cooldowns.clear()


# --- Cibles et chances ----------------------------------------------------------------------------------------

## Pays visé par une action (contrôleur de la province, camp adverse d'un front, ou le pays lui-même).
static func defender(state: SimState, tag: String, kind: String, target: String) -> String:
	match kind:
		BUILDING, INFRASTRUCTURE:
			return ControlSystem.controller(state, target)
		FRONT:
			var front: Front = state.fronts.get(target)
			return front.other(tag) if front != null else ""
	return target


static func chance(state: SimState, tag: String, action: String, kind: String, target: String) -> float:
	var enemy := defender(state, tag, kind, target)
	var rules: Dictionary = settings_of(state).get(_section(action), {})
	var edge := 0.0
	match action:
		STRIKE:
			edge = gauge(state, tag, "missiles") - air_defense(state, enemy)
		SPECIAL:
			edge = gauge(state, tag, "special_forces") - gauge(state, enemy, "special_forces")
		CYBER:
			edge = gauge(state, tag, "cyber") - gauge(state, enemy, "cyber")
	return clampf(float(rules.get("base", 0.0)) + float(rules.get("weight", 0.0)) * edge / PERCENT,
		float(rules.get("min", 0.0)), float(rules.get("max", 1.0)))


## Chance qu'une cyberattaque soit découverte (plus forte en cas d'échec).
static func discovery_chance(state: SimState, target: String, success: bool) -> float:
	var rules: Dictionary = settings_of(state).get("cyber", {})
	return clampf(float(rules.get("discovery_base", 0.0)) + float(rules.get("discovery_weight", 0.0))
		* gauge(state, target, "cyber") / PERCENT + (0.0 if success else float(rules.get("discovery_failed", 0.0))), 0.0, 1.0)


static func _section(action: String) -> String:
	match action:
		STRIKE:
			return "missiles"
		SPECIAL:
			return "special"
	return "cyber"


## Raison du refus d'une action (clé de localisation), vide si elle est possible.
static func refusal(state: SimState, tag: String, action: String, kind: String, target: String,
		building: String = "") -> String:
	var country := state.get_country(tag)
	if country == null or country.military == null or settings_of(state).is_empty() \
			or not (KINDS.get(action, []) as Array).has(kind):
		return "ACTION_INVALID"
	if action == STRIKE and country.military.missile_stock < 1.0:
		return "ACTION_NO_MISSILES"
	if action != STRIKE and int(country.military.action_cooldowns.get(action, 0)) > 0:
		return "MILITARY_COOLDOWN"
	match kind:
		BUILDING, INFRASTRUCTURE:
			if not WarSystem.at_war(state, tag, ControlSystem.controller(state, target)):
				return "ACTION_NOT_ENEMY"
			if kind == BUILDING and EnergySystem.building_count(state, target, building) <= 0:
				return "ACTION_NO_BUILDING"
		FRONT:
			var front: Front = state.fronts.get(target)
			if front == null or (front.a != tag and front.b != tag):
				return "ACTION_INVALID"
		_:
			if state.get_country(target) == null or target == tag:
				return "ACTION_INVALID"
	return ""


# --- Exécution ------------------------------------------------------------------------------------------------

## Exécute l'action (elle doit être possible) : {success, discovered}.
static func execute(state: SimState, tag: String, action: String, kind: String, target: String,
		building: String = "") -> Dictionary:
	var settings := settings_of(state)
	var rules: Dictionary = settings.get(_section(action), {})
	var country := state.get_country(tag)
	var enemy := defender(state, tag, kind, target)
	var success := state.rng.randf() < chance(state, tag, action, kind, target)
	var discovered := false
	InvestmentSystem.add_debt_usd(country, state, float(rules.get("cost_billion", 0.0)))
	if action == STRIKE:
		country.military.missile_stock -= 1.0
	else:
		country.military.action_cooldowns[action] = int(rules.get("cooldown", 0))
	if success:
		match kind:
			BUILDING:
				EnergySystem.destroy_building(state, ControlSystem.owner(state, target), building, target)
			INFRASTRUCTURE:
				state.infrastructure_damage[target] = float(state.infrastructure_damage.get(target, 0.0)) \
					+ float(rules.get("infrastructure_damage", 0.0))
			FRONT:
				var key := target + "|" + enemy
				var current: Dictionary = state.front_penalties.get(key, {})
				state.front_penalties[key] = {"factor": minf(float(current.get("factor", 0.0))
					+ float(rules.get("front_penalty", 0.0)), MAX_FRONT_PENALTY), "days_left": int(rules.get("front_days", 0))}
			ECONOMY, GRID:
				_add_effect(state, target, float(rules.get(kind + "_growth", 0.0)), int(rules.get(kind + "_months", 0)))
			ARMY:
				var land: Dictionary = state.get_country(target).military.branches.get("land", {})
				if not land.is_empty():
					land["morale"] = maxf(float(land["morale"]) + float(rules.get("military_morale", 0.0)), 1.0)
	elif action == SPECIAL:
		country.military.special["special_forces"] = maxf(gauge(state, tag, "special_forces")
			- float(rules.get("failure_points", 0.0)), 0.0)
	if action == STRIKE and kind != FRONT:
		_strike_consequences(state, tag, enemy, target, rules)
	if action == CYBER and state.rng.randf() < discovery_chance(state, target, success):
		discovered = true
		_discovered(state, tag, target, rules)
	state.add_event(EVENT_ACTION, tag, {"action": action, "kind": kind, "target": enemy, "province":
		target if kind == BUILDING or kind == INFRASTRUCTURE else "", "building": building, "success": success,
		"discovered": discovered})
	return {"success": success, "discovered": discovered}


static func _add_effect(state: SimState, tag: String, growth: float, months: int) -> void:
	if not state.attack_effects.has(tag):
		state.attack_effects[tag] = []
	(state.attack_effects[tag] as Array).append({"growth": growth, "months_left": months})
	_refresh_growth(state, tag)


static func _refresh_growth(state: SimState, tag: String) -> void:
	var country := state.get_country(tag)
	if country == null:
		return
	var total := 0.0
	for effect: Dictionary in state.attack_effects.get(tag, []):
		total += float(effect["growth"])
	country.economy.attack_growth = total


## Frappe sur une province : opinion de la cible, victimes civiles si elle est très peuplée, tension.
static func _strike_consequences(state: SimState, tag: String, enemy: String, province_id: String, rules: Dictionary) -> void:
	if state.get_country(enemy) != null:
		state.diplomacy.change_opinion(enemy, tag, float(rules.get("target_opinion", 0.0)))
	var population := int(((state.energy_definitions.get("provinces", {}) as Dictionary).get(province_id, {})
		as Dictionary).get("population", 0))
	if population >= int(rules.get("civilian_population", 0)):
		for other: String in state.countries.keys():
			if other != tag and other != enemy:
				state.diplomacy.change_opinion(other, tag, float(rules.get("civilian_world_opinion", 0.0)))
	TensionSystem.add(state, float(rules.get("tension", 0.0)))


## Cyberattaque découverte : relations, confiance et opinion de la cible, tension mondiale.
static func _discovered(state: SimState, tag: String, target: String, rules: Dictionary) -> void:
	if WarSystem.at_war(state, tag, target):
		return
	state.diplomacy.change_relation(tag, target, float(rules.get("discovered_relation", 0.0)))
	state.diplomacy.change_trust(tag, target, float(rules.get("discovered_trust", 0.0)))
	state.diplomacy.change_opinion(target, tag, float(rules.get("discovered_opinion", 0.0)))
	TensionSystem.add(state, float(rules.get("discovered_tension", 0.0)))


# --- Durées ---------------------------------------------------------------------------------------------------

## Affaiblissement d'un camp sur un front (0 à 0,9).
static func front_penalty(state: SimState, front: Front, tag: String) -> float:
	return float((state.front_penalties.get(front.key + "|" + tag, {}) as Dictionary).get("factor", 0.0))


static func update_day(state: SimState) -> void:
	for key: Variant in state.front_penalties.keys():
		var penalty: Dictionary = state.front_penalties[key]
		penalty["days_left"] = int(penalty["days_left"]) - 1
		if int(penalty["days_left"]) <= 0:
			state.front_penalties.erase(key)


## Chaque mois : missiles reconstitués, délais, infrastructures réparées, effets sur la croissance qui s'éteignent.
static func update_month(state: SimState) -> void:
	var settings := settings_of(state)
	if settings.is_empty():
		return
	var regen := float((settings.get("missiles", {}) as Dictionary).get("regen_share", 0.0))
	for tag: String in state.countries.keys():
		var military: MilitaryState = (state.countries[tag] as CountryState).military
		if military == null:
			continue
		var top := max_missiles(state, tag)
		military.missile_stock = minf(military.missile_stock + top * regen, top)
		for action: Variant in military.action_cooldowns.keys():
			military.action_cooldowns[action] = int(military.action_cooldowns[action]) - 1
			if int(military.action_cooldowns[action]) <= 0:
				military.action_cooldowns.erase(action)
	var repair := float(settings.get("infrastructure_repair", 0.0))
	for province_id: Variant in state.infrastructure_damage.keys():
		var left := float(state.infrastructure_damage[province_id]) - repair
		if left <= 0.0:
			state.infrastructure_damage.erase(province_id)
		else:
			state.infrastructure_damage[province_id] = left
	for tag: Variant in state.attack_effects.keys():
		var kept: Array = []
		for effect: Dictionary in state.attack_effects[tag]:
			effect["months_left"] = int(effect["months_left"]) - 1
			if int(effect["months_left"]) > 0:
				kept.append(effect)
		state.attack_effects[tag] = kept
		_refresh_growth(state, str(tag))
		if kept.is_empty():
			state.attack_effects.erase(tag)

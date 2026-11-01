class_name NuclearSystem
extends RefCounted
## Nucléaire : arsenal (têtes), niveau d'alerte national, programmes militaires secrets des pays non dotés,
## frappe nucléaire et riposte.
##
## Alerte (0 à 3) : coûte une part du PIB chaque mois et fait monter la tension quand on la relève ; seule
## l'alerte maximale permet une frappe. Programme : quelques années de travaux payés chaque mois, découvert
## avec une chance mensuelle (relations, tension) ; à terme, le pays reçoit ses premières têtes.
## Frappe (une salve de têtes) sur une province ennemie : une part de sa population tuée, PIB du pays touché,
## bâtiments détruits, infrastructures ruinées, forces présentes décimées ; effondrement diplomatique de
## l'attaquant (relations, confiance, opinion de tous les pays), tension au maximum. Riposte : la cible dotée
## riposte ; sinon une puissance nucléaire qui la protège (alliance, garantie) riposte avec une forte chance.
## Une riposte n'en déclenche pas d'autre (pas d'escalade automatique sans fin).

const EVENT_STRIKE := &"nuclear_strike"
const EVENT_ALERT := &"nuclear_alert_changed"
const EVENT_PROGRAM := &"nuclear_program"
const MAX_ALERT := 3
const PERCENT := 100.0
const MONTHS_PER_YEAR := 12.0


static func settings_of(state: SimState) -> Dictionary:
	return state.military_settings.get("nuclear", {})


static func warheads(state: SimState, tag: String) -> int:
	var country := state.get_country(tag)
	return country.military.nuclear_warheads if country != null and country.military != null else 0


static func setup_start(state: SimState) -> void:
	state.nuclear_programs.clear()
	state.devastated.clear()
	var programs: Dictionary = state.diplomacy_start.get("nuclear_programs", {})
	for tag: Variant in programs.keys():
		if state.countries.has(tag) and programs[tag] is Dictionary:
			var data: Dictionary = programs[tag]
			state.nuclear_programs[tag] = {"months_left": int(data.get("months_left", 0)),
				"detected": bool(data.get("detected", false))}


# --- Alerte ---------------------------------------------------------------------------------------------------

static func alert_refusal(state: SimState, tag: String, level: int) -> String:
	var country := state.get_country(tag)
	if country == null or country.military == null or level < 0 or level > MAX_ALERT or settings_of(state).is_empty():
		return "NUCLEAR_INVALID"
	if warheads(state, tag) <= 0:
		return "NUCLEAR_NO_WARHEADS"
	if country.military.nuclear_alert == level:
		return "MILITARY_ALREADY"
	if country.military.alert_cooldown > 0:
		return "MILITARY_COOLDOWN"
	return ""


static func set_alert(state: SimState, tag: String, level: int) -> void:
	var settings := settings_of(state)
	var military := state.get_country(tag).military
	var previous := military.nuclear_alert
	military.nuclear_alert = level
	military.alert_cooldown = int(settings.get("alert_cooldown", 0))
	if level > previous:
		TensionSystem.add(state, _level_value(settings.get("alert_tension", []), level))
		var opinion := _level_value(settings.get("alert_world_opinion", []), level)
		for other: String in state.countries.keys():
			if other != tag:
				state.diplomacy.change_opinion(other, tag, opinion)
	state.add_event(EVENT_ALERT, tag, {"level": level, "previous": previous})


static func _level_value(values: Array, level: int) -> float:
	return float(values[clampi(level, 0, values.size() - 1)]) if not values.is_empty() else 0.0


# --- Programmes -----------------------------------------------------------------------------------------------

static func program_refusal(state: SimState, tag: String, start: bool) -> String:
	if state.get_country(tag) == null or settings_of(state).is_empty():
		return "NUCLEAR_INVALID"
	if start:
		if warheads(state, tag) > 0:
			return "NUCLEAR_ALREADY_ARMED"
		if state.nuclear_programs.has(tag):
			return "MILITARY_ALREADY"
	elif not state.nuclear_programs.has(tag):
		return "NUCLEAR_NO_PROGRAM"
	return ""


static func start_program(state: SimState, tag: String) -> void:
	var rules: Dictionary = settings_of(state).get("program", {})
	state.nuclear_programs[tag] = {"months_left": int(rules.get("months", 0)), "detected": false}
	state.add_event(EVENT_PROGRAM, tag, {"step": "started"})


## Abandon : si le programme était connu, les autres pays l'apprécient.
static func abandon_program(state: SimState, tag: String) -> void:
	var rules: Dictionary = settings_of(state).get("program", {})
	var program: Dictionary = state.nuclear_programs[tag]
	state.nuclear_programs.erase(tag)
	if bool(program.get("detected", false)):
		for other: String in _nuclear_powers(state):
			state.diplomacy.change_relation(tag, other, float(rules.get("abandon_relation", 0.0)))
	state.add_event(EVENT_PROGRAM, tag, {"step": "abandoned"})


static func _nuclear_powers(state: SimState) -> Array[String]:
	var result: Array[String] = []
	for tag: String in state.countries.keys():
		if warheads(state, tag) > 0:
			result.append(tag)
	result.sort()
	return result


# --- Chaque mois ----------------------------------------------------------------------------------------------

## Coût de l'alerte, délais, avancement et découverte des programmes, provinces dévastées qui se relèvent.
static func update_month(state: SimState) -> void:
	var settings := settings_of(state)
	if settings.is_empty():
		return
	for tag: String in state.countries.keys():
		var country: CountryState = state.countries[tag]
		var military := country.military
		if military == null:
			continue
		if military.alert_cooldown > 0:
			military.alert_cooldown -= 1
		var share := _level_value(settings.get("alert_cost_share", []), military.nuclear_alert)
		if share > 0.0:
			InvestmentSystem.add_debt_usd(country, state, share / PERCENT * TradeSystem.current_gdp(state, tag) / MONTHS_PER_YEAR)
	var rules: Dictionary = settings.get("program", {})
	var tags: Array = state.nuclear_programs.keys()
	tags.sort()
	for tag: String in tags:
		var program: Dictionary = state.nuclear_programs[tag]
		var country := state.get_country(tag)
		InvestmentSystem.add_debt_usd(country, state, float(rules.get("monthly_cost_billion", 0.0)))
		program["months_left"] = int(program["months_left"]) - 1
		if not bool(program["detected"]) and state.rng.randf() < float(rules.get("detection_chance", 0.0)):
			program["detected"] = true
			for other: String in _nuclear_powers(state):
				state.diplomacy.change_relation(tag, other, float(rules.get("detected_relation", 0.0)))
			TensionSystem.add(state, float(rules.get("detected_tension", 0.0)))
			state.add_event(EVENT_PROGRAM, tag, {"step": "detected"})
		if int(program["months_left"]) <= 0:
			state.nuclear_programs.erase(tag)
			country.military.nuclear_warheads = int(rules.get("completed_warheads", 0))
			TensionSystem.add(state, float(rules.get("completed_tension", 0.0)))
			state.add_event(EVENT_PROGRAM, tag, {"step": "completed"})
	for province_id: Variant in state.devastated.keys():
		state.devastated[province_id] = int(state.devastated[province_id]) - 1
		if int(state.devastated[province_id]) <= 0:
			state.devastated.erase(province_id)


# --- Frappe ---------------------------------------------------------------------------------------------------

static func strike_refusal(state: SimState, tag: String, province_id: String) -> String:
	var country := state.get_country(tag)
	if country == null or country.military == null or settings_of(state).is_empty():
		return "NUCLEAR_INVALID"
	if warheads(state, tag) <= 0:
		return "NUCLEAR_NO_WARHEADS"
	if country.military.nuclear_alert < MAX_ALERT:
		return "NUCLEAR_ALERT_TOO_LOW"
	if not WarSystem.at_war(state, tag, ControlSystem.controller(state, province_id)):
		return "ACTION_NOT_ENEMY"
	return ""


## Frappe nucléaire sur une province ; retaliate : vrai pour une riposte (qui n'en déclenche pas d'autre).
static func strike(state: SimState, tag: String, province_id: String, retaliate: bool = true) -> void:
	var settings := settings_of(state)
	var attacker := state.get_country(tag)
	var target := ControlSystem.controller(state, province_id)
	var owner := ControlSystem.owner(state, province_id)
	attacker.military.nuclear_warheads = maxi(attacker.military.nuclear_warheads - int(settings.get("strike_warheads", 1)), 0)
	_devastate(state, province_id, owner, settings)
	# Forces présentes décimées (groupes d'armées dans la province, tous camps).
	for group: ArmyGroup in state.army_groups.values():
		if group.province != province_id or group.is_embarked():
			continue
		var war := WarSystem.war_between(state, tag, group.owner)
		if war != null:
			var men := group.personnel(state.get_country(group.owner).military, ArmyGroupModel.reserve_share(state))
			WarResolver.apply_losses(state, war, group.owner, men * float(settings.get("front_losses", 0.0)),
				FrontSystem.combat_settings(state))
	for other: String in state.countries.keys():
		if other == tag:
			continue
		state.diplomacy.change_relation(tag, other, float(settings.get("attacker_relation", 0.0)))
		state.diplomacy.change_trust(tag, other, float(settings.get("attacker_trust", 0.0)))
		state.diplomacy.change_opinion(other, tag, float(settings.get("attacker_opinion", 0.0)))
	attacker.society.start_stability -= float(settings.get("attacker_stability", 0.0))
	attacker.society.start_legitimacy -= float(settings.get("attacker_legitimacy", 0.0))
	var victim := state.get_country(owner)
	if victim != null:
		victim.society.start_stability -= float(settings.get("target_stability", 0.0))
	TensionSystem.add(state, TensionSystem.LIMIT)
	state.add_event(EVENT_STRIKE, tag, {"target": target, "province": province_id, "retaliation": not retaliate})
	if retaliate:
		_retaliation(state, tag, target)


## Province dévastée : population tuée, PIB du pays touché, bâtiments détruits, infrastructures ruinées.
static func _devastate(state: SimState, province_id: String, owner: String, settings: Dictionary) -> void:
	var country := state.get_country(owner)
	var population := float(((state.energy_definitions.get("provinces", {}) as Dictionary).get(province_id, {})
		as Dictionary).get("population", 0))
	if country != null and country.economy.population > 0:
		var killed := minf(population * float(settings.get("kill_share", 0.0)), float(country.economy.population) * 0.5)
		var share := killed / float(country.economy.population)
		country.economy.population = maxi(country.economy.population - int(killed), 1)
		country.economy.real_gdp *= maxf(1.0 - share * float(settings.get("gdp_factor", 1.0)), 0.1)
	for building_id: Variant in (state.buildings.get(province_id, {}) as Dictionary).keys():
		for _index: int in EnergySystem.building_count(state, province_id, str(building_id)):
			EnergySystem.destroy_building(state, owner, str(building_id), province_id)
	state.infrastructure_damage[province_id] = float(state.infrastructure_damage.get(province_id, 0.0)) \
		+ float(settings.get("infrastructure_damage", 0.0))
	state.devastated[province_id] = int(settings.get("devastation_months", 0))


## Riposte : la cible si elle est dotée, sinon une puissance nucléaire qui la protège (une seule), sur la province
## la plus peuplée de l'attaquant. Le joueur décide lui-même de riposter.
static func _retaliation(state: SimState, attacker: String, target: String) -> void:
	var responder := ""
	if warheads(state, target) > 0:
		responder = target
	else:
		for power: String in _nuclear_powers(state):
			if power == attacker or ControlSystem.allied(state, power, attacker):
				continue
			if (ControlSystem.allied(state, power, target) or state.diplomacy.guarantees_independence(power, target)) \
					and state.rng.randf() < float(settings_of(state).get("umbrella_chance", 0.0)):
				responder = power
				break
	if responder.is_empty() or responder == str(state.player_tag):
		return
	var war := WarSystem.war_between(state, attacker, target)
	if not WarSystem.at_war(state, responder, attacker) and war != null:
		WarSystem.join(state, war, responder, war.side_of(target), true)
	var military := state.get_country(responder).military
	military.nuclear_alert = MAX_ALERT
	var aim := FrontSystem.seat(state, attacker)
	if not aim.is_empty():
		strike(state, responder, aim, false)

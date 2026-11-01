class_name OccupationSystem
extends RefCounted
## Occupation et gouvernements fantoches.
##
## Résistance (0 à 1) dans chaque province tenue par un ennemi de son propriétaire pendant une guerre : elle tend
## vers le maximum × la volonté de se battre du propriétaire, et chaque mois tue des soldats de l'occupant
## (pertes par million d'habitants × résistance) et abîme les infrastructures (ravitaillement).
## Fantoche (exigence de paix « changer le régime ») : gouvernement aligné sur le suzerain (même idéologie,
## stabilité et légitimité en baisse), défense mutuelle et base du suzerain, tribut annuel ; il ne peut pas
## attaquer son suzerain. Indépendance : le joueur la proclame ; un fantoche de l'IA la tente avec une chance
## mensuelle s'il pèse assez face à son suzerain ; crise avec l'ancien suzerain.

const PUPPET := "puppet"
const EVENT_PUPPET := &"puppet_installed"
const EVENT_INDEPENDENCE := &"puppet_independence"
const PERCENT := 100.0
const MILLION := 1000000.0
const MONTHS_PER_YEAR := 12.0


static func occupation_settings(state: SimState) -> Dictionary:
	return state.military_settings.get("occupation", {})


static func puppet_settings(state: SimState) -> Dictionary:
	return state.military_settings.get("puppet", {})


static func overlord_of(state: SimState, tag: String) -> String:
	return str(state.puppets.get(tag, ""))


static func is_puppet(state: SimState, tag: String) -> bool:
	return state.puppets.has(tag)


static func puppets_of(state: SimState, overlord: String) -> Array[String]:
	var result: Array[String] = []
	for tag: Variant in state.puppets.keys():
		if str(state.puppets[tag]) == overlord:
			result.append(str(tag))
	result.sort()
	return result


# --- Résistance -----------------------------------------------------------------------------------------------

static func update_month(state: SimState) -> void:
	_update_resistance(state)
	_update_puppets(state)


static func _update_resistance(state: SimState) -> void:
	var rules := occupation_settings(state)
	if rules.is_empty():
		return
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var active: Dictionary = {}
	for war: War in state.wars.values():
		if war.civil:
			continue
		for owner: String in war.attackers + war.defenders:
			var enemies := war.enemies_of(owner)
			for province_id: Variant in state.provinces_by_owner.get(owner, []):
				var key := str(province_id)
				var occupier := ControlSystem.controller(state, key)
				if not enemies.has(occupier) or state.get_country(occupier) == null:
					continue
				var target := float(rules.get("resistance_max", 0.0)) * WarEnd.support(war, owner) / PERCENT
				var level := float(state.resistance.get(key, 0.0))
				level += (target - level) * float(rules.get("adjustment", 0.0))
				active[key] = level
				var population := float((provinces.get(key, {}) as Dictionary).get("population", 0.0))
				var killed := population / MILLION * level * float(rules.get("losses_per_million", 0.0))
				WarResolver.apply_losses(state, war, occupier, killed, FrontSystem.combat_settings(state))
				state.infrastructure_damage[key] = float(state.infrastructure_damage.get(key, 0.0)) \
					+ level * float(rules.get("infrastructure_damage", 0.0))
	state.resistance = active


# --- Fantoches ------------------------------------------------------------------------------------------------

## Le vainqueur peut exiger un gouvernement fantoche si son but de guerre est le changement de régime.
static func puppet_demand_available(state: SimState, war: War, tag: String) -> bool:
	return war.goal == "regime_change" and war.side_of(tag) == War.ATTACKERS and WarEnd.score_for(state, war, tag) > 0.0 \
		and not puppet_settings(state).is_empty()


static func install_puppet(state: SimState, puppet: String, overlord: String) -> void:
	var rules := puppet_settings(state)
	var country := state.get_country(puppet)
	var master := state.get_country(overlord)
	if country == null or master == null or puppet == overlord:
		return
	state.puppets[puppet] = overlord
	if not master.politics.ideology.is_empty():
		country.politics.ideology = master.politics.ideology
	country.society.start_stability -= float(rules.get("stability", 0.0))
	country.society.start_legitimacy -= float(rules.get("legitimacy", 0.0))
	state.diplomacy.change_relation(puppet, overlord, float(rules.get("relation", 0.0)))
	for treaty_type: String in ["mutual_defense", "military_access"]:
		if not state.diplomacy.has_treaty(puppet, overlord, treaty_type):
			if treaty_type == "military_access":
				DiplomacySystem.add_treaty(state, treaty_type, overlord, puppet, true)
			else:
				DiplomacySystem.add_treaty(state, treaty_type, puppet, overlord, true)
	state.add_event(EVENT_PUPPET, overlord, {"puppet": puppet})


static func independence_refusal(state: SimState, tag: String) -> String:
	if not is_puppet(state, tag):
		return "PUPPET_NOT_PUPPET"
	return ""


## Fin de la tutelle : alliance et base rompues, crise avec l'ancien suzerain.
static func declare_independence(state: SimState, tag: String) -> void:
	var rules := puppet_settings(state)
	var overlord := overlord_of(state, tag)
	state.puppets.erase(tag)
	for treaty_id: int in state.diplomacy.treaties_between(tag, overlord):
		var treaty_type := str((state.diplomacy.treaties[treaty_id] as Dictionary)["type"])
		if treaty_type == "mutual_defense" or treaty_type == "military_access":
			state.diplomacy.treaties.erase(treaty_id)
	state.diplomacy.bases.erase(DiplomacyState.opinion_key(overlord, tag))
	state.diplomacy.change_relation(tag, overlord, float(rules.get("independence_relation", 0.0)))
	TensionSystem.add(state, float(rules.get("independence_tension", 0.0)))
	state.add_event(EVENT_INDEPENDENCE, tag, {"overlord": overlord})


## Tribut mensuel ; un fantoche de l'IA tente parfois l'indépendance s'il pèse assez face à son suzerain.
static func _update_puppets(state: SimState) -> void:
	var rules := puppet_settings(state)
	if rules.is_empty():
		return
	var tags: Array = state.puppets.keys()
	tags.sort()
	for tag: Variant in tags:
		var puppet := state.get_country(str(tag))
		var overlord := state.get_country(str(state.puppets[tag]))
		if puppet == null or overlord == null:
			state.puppets.erase(tag)
			continue
		var amount := float(rules.get("tribute_share", 0.0)) / PERCENT * TradeSystem.current_gdp(state, puppet.tag) / MONTHS_PER_YEAR
		InvestmentSystem.add_debt_usd(puppet, state, amount)
		InvestmentSystem.add_debt_usd(overlord, state, -amount)
		if puppet.tag == str(state.player_tag):
			continue
		var strong := DiplomacyModel.power(state, puppet.tag) >= float(rules.get("independence_power_ratio", INF)) \
			* DiplomacyModel.power(state, overlord.tag)
		if strong and state.rng.randf() < float(rules.get("independence_chance", 0.0)):
			declare_independence(state, puppet.tag)

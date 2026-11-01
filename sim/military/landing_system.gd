class_name LandingSystem
extends RefCounted
## Débarquements : un groupe d'armées posté sur une côte traverse la mer vers une province ennemie côtière dont
## une mer voisine porte une flotte de notre camp sans que l'ennemi la domine.
##
## Chance = base + poids × log2(forces débarquées / défenseurs) - pénalité si la mer est disputée (bornée).
## Défenseurs = groupes ennemis dans la province + garnison (part de l'armée de terre ennemie), × qualité
## × défense du terrain. Succès : tête de pont (part de la province), le groupe s'y installe, pertes légères.
## Échec : lourdes pertes, le groupe reste à quai. Une tête de pont perdue force le rembarquement (pertes).

const EVENT_SUCCEEDED := &"landing_succeeded"
const EVENT_FAILED := &"landing_failed"
const EVENT_EVACUATED := &"beachhead_lost"
const LOG2 := 0.6931471805599453


static func settings_of(state: SimState) -> Dictionary:
	return NavalModel.settings_of(state).get("landing", {})


## Mers voisines d'une province (mers seulement, lacs exclus).
static func sea_neighbors(state: SimState, province_id: String) -> Array[String]:
	var province: Dictionary = (state.energy_definitions.get("provinces", {}) as Dictionary).get(province_id, {})
	var result: Array[String] = []
	for zone_id: Variant in province.get("sea_neighbors", []):
		if NavalModel.is_sea(state, str(int(zone_id))):
			result.append(str(int(zone_id)))
	return result


## Mer d'approche : voisine de la cible, avec une flotte de notre camp, sans domination ennemie (une mer
## disputée est possible, avec une pénalité). Celles que nous dominons ou que personne ne dispute d'abord.
## "" si aucune.
static func landing_zone(state: SimState, tag: String, target: String) -> String:
	var war := WarSystem.war_between(state, tag, ControlSystem.controller(state, target))
	if war == null:
		return ""
	var side := war.side_of(tag)
	var fallback := ""
	for zone_id: String in sea_neighbors(state, target):
		var ours := false
		for fleet: Fleet in state.fleets.values():
			if fleet.zone == zone_id and not fleet.is_moving() and war.side_of(fleet.owner) == side:
				ours = true
				break
		if not ours:
			continue
		var control: Dictionary = state.sea_control.get(zone_id, {})
		if bool(control.get("contested", false)):
			fallback = zone_id
		elif control.is_empty() or str(control.get("side", "")) == side:
			return zone_id
	return fallback


## Raison du refus d'un débarquement (clé de localisation), vide s'il est possible.
static func refusal(state: SimState, tag: String, group_id: int, target: String) -> String:
	var group: ArmyGroup = state.army_groups.get(group_id)
	if group == null or group.owner != tag or group.is_embarked():
		return "ARMY_INVALID"
	if not WarSystem.at_war(state, tag, ControlSystem.controller(state, target)):
		return "LANDING_NOT_ENEMY"
	if sea_neighbors(state, target).is_empty():
		return "LANDING_NOT_COASTAL"
	if group.is_moving() or sea_neighbors(state, group.province).is_empty() \
			or ControlSystem.controller(state, group.province) != tag:
		return "LANDING_GROUP_INLAND"
	var zone := landing_zone(state, tag, target)
	if zone.is_empty():
		return "LANDING_NO_FLEET"
	if _sea_route(state, group.province, zone).is_empty():
		return "LANDING_UNREACHABLE"
	return ""


## Mer de départ (voisine de la province du groupe) d'où la mer d'approche est atteignable ; "" sinon.
static func _sea_route(state: SimState, from_province: String, zone: String) -> String:
	for start: String in sea_neighbors(state, from_province):
		if start == zone or not NavalModel.find_path(state, start, zone).is_empty():
			return start
	return ""


## Chance de réussite d'un débarquement (0 à 1).
static func chance(state: SimState, group: ArmyGroup, target: String, zone: String) -> float:
	var rules := settings_of(state)
	var tag := group.owner
	var enemy := ControlSystem.controller(state, target)
	var reserve_share := ArmyGroupModel.reserve_share(state)
	var ours := group.personnel(state.get_country(tag).military, reserve_share) * FrontSystem.quality(state, tag)
	var defenders := FrontSystem.land_personnel(state, enemy) * float(rules.get("garrison_share", 0.0))
	var enemy_country := state.get_country(enemy)
	if enemy_country != null:
		for other: ArmyGroup in ArmyGroupModel.groups_of(state, enemy):
			if other.province == target and not other.is_embarked():
				defenders += other.personnel(enemy_country.military, reserve_share)
	defenders *= FrontSystem.quality(state, enemy) * WarResolver.terrain_defense(state, target)
	var odds := log(maxf(ours, WarResolver.MIN_STRENGTH) / maxf(defenders, WarResolver.MIN_STRENGTH)) / LOG2
	var value := float(rules.get("base_chance", 0.0)) + float(rules.get("odds_weight", 0.0)) * odds
	if bool((state.sea_control.get(zone, {}) as Dictionary).get("contested", false)):
		value -= float(rules.get("contested_penalty", 0.0))
	return clampf(value, float(rules.get("min_chance", 0.0)), float(rules.get("max_chance", 1.0)))


## Embarquement : le groupe prend la mer (jours de traversée selon la distance).
static func launch(state: SimState, group: ArmyGroup, target: String) -> void:
	var zone := landing_zone(state, group.owner, target)
	var start := _sea_route(state, group.province, zone)
	var days := 1
	var previous := start
	for step: String in NavalModel.find_path(state, start, zone):
		days += NavalModel.travel_days(state, previous, step)
		previous = step
	group.path.clear()
	group.days_left = 0
	group.landing_target = target
	group.landing_zone = zone
	group.landing_days = days


## Chaque jour : traversées en cours, puis têtes de pont perdues.
static func update_day(state: SimState) -> void:
	var ids: Array = state.army_groups.keys()
	ids.sort()
	for group_id: Variant in ids:
		var group: ArmyGroup = state.army_groups[group_id]
		if group.is_embarked():
			group.landing_days -= 1
			if group.landing_days <= 0:
				_resolve(state, group)
		elif ControlSystem.controller(state, group.province) != group.owner \
				and ControlSystem.share_held(state, group.province, group.owner) <= 0.0:
			_evacuate(state, group)


static func _resolve(state: SimState, group: ArmyGroup) -> void:
	var rules := settings_of(state)
	var target := group.landing_target
	group.landing_target = ""
	group.landing_zone = ""
	group.landing_days = 0
	var enemy := ControlSystem.controller(state, target)
	var war := WarSystem.war_between(state, group.owner, enemy)
	if war == null:
		return
	var zone := landing_zone(state, group.owner, target)
	var personnel := group.personnel(state.get_country(group.owner).military, ArmyGroupModel.reserve_share(state))
	var combat := FrontSystem.combat_settings(state)
	if not zone.is_empty() and state.rng.randf() < chance(state, group, target, zone):
		ControlSystem.advance(state, target, group.owner, float(rules.get("beachhead_share", 0.0)))
		group.province = target
		WarResolver.apply_losses(state, war, group.owner, personnel * float(rules.get("success_losses", 0.0)), combat)
		state.add_event(EVENT_SUCCEEDED, group.owner, {"group": group.id, "province": target, "target": enemy})
	else:
		WarResolver.apply_losses(state, war, group.owner, personnel * float(rules.get("failure_losses", 0.0)), combat)
		state.add_event(EVENT_FAILED, group.owner, {"group": group.id, "province": target, "target": enemy})


## Tête de pont perdue : le groupe rembarque vers notre province la plus peuplée, avec des pertes.
static func _evacuate(state: SimState, group: ArmyGroup) -> void:
	var war := WarSystem.war_between(state, group.owner, ControlSystem.controller(state, group.province))
	if war != null:
		var personnel := group.personnel(state.get_country(group.owner).military, ArmyGroupModel.reserve_share(state))
		WarResolver.apply_losses(state, war, group.owner, personnel * float(settings_of(state).get("evacuation_losses", 0.0)),
			FrontSystem.combat_settings(state))
	var lost := group.province
	var refuge := FrontSystem.seat(state, group.owner)
	group.path.clear()
	group.days_left = 0
	if not refuge.is_empty():
		group.province = refuge
	state.add_event(EVENT_EVACUATED, group.owner, {"group": group.id, "province": lost})

class_name FrontSystem
extends RefCounted
## Fronts automatiques : pour chaque guerre, une paire d'ennemis dont les provinces se touchent (voisines ou
## disputées) forme un front. Les fronts sont recalculés quand le contrôle des provinces ou les guerres
## changent ; les postures sont gardées d'un calcul à l'autre.
##
## Forces d'un camp sur un front = groupes d'armées posés sur ses provinces du front (un groupe sur plusieurs
## fronts se partage) + une garnison (part des forces terrestres) ; puissance = effectifs × niveau^exposant
## × entraînement × moral (comme la puissance militaire). Une faction rebelle répartit ses forces entre ses
## fronts.

const POSTURES := ["offensive", "defensive", "hold", "retreat"]


static func combat_settings(state: SimState) -> Dictionary:
	return state.military_settings.get("combat", {})


## Recalcule les fronts si nécessaire.
static func refresh(state: SimState) -> void:
	if not state.fronts_dirty:
		return
	state.fronts_dirty = false
	var previous := state.fronts
	state.fronts = {}
	state.front_seats = {}
	state.front_holdings = {}
	var definitions: Dictionary = state.energy_definitions.get("provinces", {})
	var seat_population: Dictionary = {}
	var default_posture := str(combat_settings(state).get("default_posture", "defensive"))
	# Guerres de chaque belligérant : seules leurs provinces sont parcourues.
	var wars_by_tag: Dictionary = {}
	for war: War in state.wars.values():
		for tag: String in war.attackers + war.defenders:
			if not wars_by_tag.has(tag):
				wars_by_tag[tag] = []
			(wars_by_tag[tag] as Array).append(war)
	for tag: Variant in wars_by_tag.keys():
		state.front_seats[tag] = ""
	for province_id: String in state.province_control.keys():
		var holder := ControlSystem.controller(state, province_id)
		if not wars_by_tag.has(holder):
			continue
		state.front_holdings[holder] = true
		if WarSystem.is_rebel(state, holder) or ControlSystem.owner(state, province_id) == holder:
			var population := int((definitions.get(province_id, {}) as Dictionary).get("population", 0))
			if population > int(seat_population.get(holder, -1)) or (population == int(seat_population.get(holder, -1))
					and int(province_id) < int(state.front_seats[holder])):
				seat_population[holder] = population
				state.front_seats[holder] = province_id
		var held_contest: Dictionary = state.contested.get(province_id, {})
		if not held_contest.is_empty():
			state.front_holdings[str(held_contest["by"])] = true
		for war: War in wars_by_tag[holder]:
			var side := war.side_of(holder)
			var contest: Dictionary = state.contested.get(province_id, {})
			var contester := str(contest.get("by", ""))
			if not contest.is_empty() and war.side_of(contester) == War.other_side(side):
				var front := _front(state, war, holder, contester, previous, default_posture)
				_add(front, holder, province_id)
				_add(front, contester, province_id)
				if not front.contested.has(province_id):
					front.contested.append(province_id)
			for neighbor: Variant in ControlSystem.neighbors(state, province_id):
				var enemy := ControlSystem.controller(state, str(neighbor))
				if war.side_of(enemy) == War.other_side(side):
					_add(_front(state, war, holder, enemy, previous, default_posture), holder, province_id)
	for front: Front in state.fronts.values():
		for tag: Variant in front.provinces.keys():
			(front.provinces[tag] as Array).sort_custom(func(x: String, y: String) -> bool: return int(x) < int(y))
		front.contested.sort_custom(func(x: String, y: String) -> bool: return int(x) < int(y))


static func _front(state: SimState, war: War, x: String, y: String, previous: Dictionary, default_posture: String) -> Front:
	var a := x if war.side_of(x) == War.ATTACKERS else y
	var b := y if a == x else x
	var key := Front.key_for(war.id, a, b)
	if state.fronts.has(key):
		return state.fronts[key]
	var front := Front.new()
	front.key = key
	front.war_id = war.id
	front.a = a
	front.b = b
	front.provinces = {a: [], b: []}
	var old: Front = previous.get(key)
	front.postures = old.postures.duplicate() if old != null else {a: default_posture, b: default_posture}
	state.fronts[key] = front
	return front


static func _add(front: Front, tag: String, province_id: String) -> void:
	var list: Array = front.provinces[tag]
	if not list.has(province_id):
		list.append(province_id)


## Fronts d'un pays (ou d'une faction), dans l'ordre des clés.
static func fronts_of(state: SimState, tag: String) -> Array[Front]:
	var result: Array[Front] = []
	var keys: Array = state.fronts.keys()
	keys.sort()
	for key: Variant in keys:
		var front: Front = state.fronts[key]
		if front.a == tag or front.b == tag:
			result.append(front)
	return result


static func fronts_of_war(state: SimState, war_id: int) -> Array[Front]:
	var result: Array[Front] = []
	var keys: Array = state.fronts.keys()
	keys.sort()
	for key: Variant in keys:
		var front: Front = state.fronts[key]
		if front.war_id == war_id:
			result.append(front)
	return result


# --- Forces --------------------------------------------------------------------------------------------------

## Puissance d'un soldat de l'armée de terre (niveau, entraînement, moral) ; 0 sans armée de terre.
static func quality(state: SimState, tag: String) -> float:
	var rules: Dictionary = state.military_settings.get("power", {})
	var level := 0.0
	var training := 0.0
	var morale := 0.0
	var faction: RebelFaction = state.rebels.get(tag)
	if faction != null:
		level = faction.level
		training = faction.training
		morale = faction.morale
	else:
		var country := state.get_country(tag)
		if country == null or country.military == null or not country.military.has_branch("land"):
			return 0.0
		var land: Dictionary = country.military.branches["land"]
		level = float(land["level"])
		training = float(land["training"])
		morale = float(land["morale"])
	return pow(level, float(rules.get("level_exponent", 1.0))) * training / float(rules.get("training_reference", 1.0)) \
		* morale / float(rules.get("morale_reference", 1.0))


## Effectifs de l'armée de terre d'un pays ou d'une faction.
static func land_personnel(state: SimState, tag: String) -> float:
	var faction: RebelFaction = state.rebels.get(tag)
	if faction != null:
		return faction.personnel
	var country := state.get_country(tag)
	if country == null or country.military == null or not country.military.has_branch("land"):
		return 0.0
	return country.military.personnel(ArmyGroupModel.reserve_share(state)) \
		* float((country.military.branches["land"] as Dictionary)["share"])


## Soldats engagés par un camp sur chaque front : {clé de front: effectifs}. Groupes sur les provinces du front
## (partagés entre les fronts où ils se trouvent) + garnison ; les rebelles se répartissent entre leurs fronts.
static func engaged_personnel(state: SimState, tag: String) -> Dictionary:
	var result: Dictionary = {}
	var fronts := fronts_of(state, tag)
	if fronts.is_empty():
		return result
	var land := land_personnel(state, tag)
	if WarSystem.is_rebel(state, tag):
		for front: Front in fronts:
			result[front.key] = land / fronts.size()
		return result
	var garrison := land * float(combat_settings(state).get("garrison_share", 0.0))
	for front: Front in fronts:
		result[front.key] = garrison
	var country := state.get_country(tag)
	for group: ArmyGroup in ArmyGroupModel.groups_of(state, tag):
		if group.is_embarked():
			continue
		var here: Array[Front] = []
		for front: Front in fronts:
			if front.provinces_of(tag).has(group.province):
				here.append(front)
		if here.is_empty():
			continue
		var men := group.personnel(country.military, ArmyGroupModel.reserve_share(state))
		for front: Front in here:
			result[front.key] = float(result[front.key]) + men / here.size()
	return result


## Groupes d'armées d'un pays posés sur un front.
static func groups_on(state: SimState, front: Front, tag: String) -> Array[ArmyGroup]:
	var result: Array[ArmyGroup] = []
	for group: ArmyGroup in ArmyGroupModel.groups_of(state, tag):
		if front.provinces_of(tag).has(group.province):
			result.append(group)
	return result


# --- Répartition des groupes ----------------------------------------------------------------------------------

## Envoie les groupes d'un pays sur ses fronts, en proportion des forces ennemies en face (au moins un groupe
## par front tant qu'il y en a assez). Les groupes déjà sur le bon front restent ; les autres partent vers une
## province du front (disputées d'abord). Sans front, rien ne bouge.
static func auto_deploy(state: SimState, tag: String) -> void:
	refresh(state)
	var fronts := fronts_of(state, tag)
	var groups := ArmyGroupModel.groups_of(state, tag)
	if fronts.is_empty() or groups.is_empty():
		return
	var weights: Array[float] = []
	var total := 0.0
	for front: Front in fronts:
		var enemy := front.other(tag)
		var enemy_engaged: Dictionary = engaged_personnel(state, enemy)
		var weight := float(enemy_engaged.get(front.key, 0.0)) * quality(state, enemy) + 1.0
		weights.append(weight)
		total += weight
	var counts := _allocate(groups.size(), weights, total)
	var free: Array[ArmyGroup] = []
	var needed: Array[int] = counts.duplicate()
	# Les groupes en mer ou sur une tête de pont restent où ils sont.
	var movable: Array[ArmyGroup] = []
	for group: ArmyGroup in groups:
		if not group.is_embarked() and ControlSystem.controller(state, group.province) == tag:
			movable.append(group)
	for group: ArmyGroup in movable:
		var placed := false
		for index: int in fronts.size():
			var target_province := group.destination if group.is_moving() else group.province
			if needed[index] > 0 and fronts[index].provinces_of(tag).has(target_province):
				needed[index] -= 1
				placed = true
				break
		if not placed:
			free.append(group)
	for index: int in fronts.size():
		var targets := _deploy_targets(fronts[index], tag)
		var slot := 0
		while needed[index] > 0 and not free.is_empty():
			var group: ArmyGroup = free.pop_front()
			needed[index] -= 1
			for attempt: int in targets.size():
				var destination: String = targets[(slot + attempt) % targets.size()]
				if destination == group.province:
					group.path.clear()
					group.days_left = 0
					break
				if not ArmyGroupModel.find_path(state, tag, group.province, destination).is_empty():
					ArmyGroupModel.order_move(state, group, destination)
					break
			slot += 1


## Répartition entière proportionnelle (plus forts restes), au moins 1 par front si possible.
static func _allocate(count: int, weights: Array[float], total: float) -> Array[int]:
	var result: Array[int] = []
	var minimum := 1 if count >= weights.size() else 0
	var left := count - minimum * weights.size()
	var remainders: Array = []
	for index: int in weights.size():
		var exact := left * weights[index] / total if total > 0.0 else 0.0
		result.append(minimum + floori(exact))
		remainders.append([exact - floorf(exact), index])
	var given := 0
	for value: int in result:
		given += value
	remainders.sort_custom(func(x: Array, y: Array) -> bool:
		return float(x[0]) > float(y[0]) if not is_equal_approx(float(x[0]), float(y[0])) else int(x[1]) < int(y[1]))
	var cursor := 0
	while given < count and not remainders.is_empty():
		result[int(remainders[cursor % remainders.size()][1])] += 1
		given += 1
		cursor += 1
	return result


## Provinces où poser des groupes sur un front : les disputées que le pays contrôle d'abord, puis les autres.
static func _deploy_targets(front: Front, tag: String) -> Array[String]:
	var first: Array[String] = []
	var rest: Array[String] = []
	for province_id: Variant in front.provinces_of(tag):
		if front.contested.has(str(province_id)):
			first.append(str(province_id))
		else:
			rest.append(str(province_id))
	return first + rest


## Province la plus peuplée tenue par un pays ou une faction (centre du ravitaillement) ; gardée en cache avec
## les fronts pour les belligérants.
static func seat(state: SimState, tag: String) -> String:
	if state.front_seats.has(tag) and not state.fronts_dirty:
		return str(state.front_seats[tag])
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var owner := WarSystem.country_of(state, tag)
	var best := ""
	var best_population := -1
	for province_id: String in state.province_control.keys():
		if ControlSystem.controller(state, province_id) != tag:
			continue
		if not WarSystem.is_rebel(state, tag) and ControlSystem.owner(state, province_id) != owner:
			continue
		var population := int((provinces.get(province_id, {}) as Dictionary).get("population", 0))
		if population > best_population or (population == best_population and int(province_id) < int(best)):
			best = province_id
			best_population = population
	return best

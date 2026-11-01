class_name ArmyGroupModel
extends RefCounted
## Groupes d'armées : création au départ, placement selon les menaces, déplacements par voie de terre.
##
## Nombre de groupes = effectifs terrestres / effectifs par groupe (au moins 1, au plus le maximum des données).
## Menace d'une province = poids du front si elle touche (ou est) une province disputée ou occupée de part et
## d'autre, sinon hostilité des voisins (relations sous le seuil). Les groupes vont d'abord aux provinces les
## plus menacées (jamais deux voisines), puis à la capitale et aux provinces les plus peuplées. Les groupes
## du front reçoivent une plus grande part des forces.

const EARTH_RADIUS_KM := 6371.0
const DEGREES_HALF_TURN := 180.0
const EVENT_ARRIVED := &"army_group_arrived"


static func settings_of(state: SimState) -> Dictionary:
	return state.military_settings.get("army_groups", {})


static func reserve_share(state: SimState) -> Array:
	return (state.military_settings.get("mobilization", {}) as Dictionary).get("reserve_share", [])


## Crée les groupes d'armées de tous les pays (après les forces armées et le contrôle des provinces).
static func setup_start(state: SimState, countries: Dictionary) -> void:
	state.army_groups.clear()
	state.next_army_group_id = 1
	var settings := settings_of(state)
	if settings.is_empty():
		return
	var by_owner := _controlled_by_country(state)
	var relations: Dictionary = {}
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		var provinces: Array = by_owner.get(tag, [])
		if country.military == null or not country.military.has_branch("land") or provinces.is_empty():
			continue
		var capital_value: Variant = (countries.get(tag, {}) as Dictionary).get("capital", -1)
		var capital := str(int(capital_value)) if capital_value is float or capital_value is int else str(capital_value)
		var land := country.military.personnel(reserve_share(state)) 			* float((country.military.branches["land"] as Dictionary)["share"])
		var count := clampi(ceili(land / float(settings.get("personnel_per_group", 1.0))), 1,
			int(settings.get("max_groups", 1)))
		_place(state, tag, provinces, capital, count, settings, relations)


static func _controlled_by_country(state: SimState) -> Dictionary:
	var result: Dictionary = {}
	for province_id: String in state.province_control.keys():
		var tag := str(state.province_control[province_id])
		if not result.has(tag):
			result[tag] = []
		(result[tag] as Array).append(province_id)
	return result


## Placement : provinces du front d'abord (voisines permises), puis provinces hostiles espacées ; à partir de
## quelques groupes, un groupe reste en réserve à la capitale ; enfin les provinces les plus peuplées.
static func _place(state: SimState, tag: String, provinces: Array, capital: String, count: int,
		settings: Dictionary, relations: Dictionary) -> void:
	var definitions: Dictionary = state.energy_definitions.get("provinces", {})
	var front_weight := float(settings.get("front_weight", 1.0))
	var front_level := front_weight * float(settings.get("near_front", 1.0))
	var scores: Dictionary = {}
	for province_id: String in provinces:
		scores[province_id] = threat(state, tag, province_id, settings, relations)
	var ranked: Array = provinces.duplicate()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		if not is_equal_approx(float(scores[a]), float(scores[b])):
			return float(scores[a]) > float(scores[b])
		return int((definitions.get(a, {}) as Dictionary).get("population", 0)) 			> int((definitions.get(b, {}) as Dictionary).get("population", 0)))
	var field_slots := count - (1 if count >= int(settings.get("reserve_from_groups", count + 1)) else 0)
	var chosen: Array[String] = []
	for province_id: String in ranked:
		if chosen.size() >= field_slots or float(scores[province_id]) < front_level:
			break
		chosen.append(province_id)
	for province_id: String in ranked:
		if chosen.size() >= field_slots or float(scores[province_id]) <= 0.0:
			break
		if float(scores[province_id]) < front_level and _spaced(state, province_id, chosen):
			chosen.append(province_id)
	if chosen.size() < count and provinces.has(capital) and not chosen.has(capital):
		chosen.append(capital)
	for province_id: String in ranked:
		if chosen.size() >= count:
			break
		if float(scores[province_id]) >= 0.0 and not chosen.has(province_id) and _spaced(state, province_id, chosen):
			chosen.append(province_id)
	var weights: Array[float] = []
	var total := 0.0
	for province_id: String in chosen:
		var weight := 1.0 + float(settings.get("front_share_bonus", 0.0)) * clampf(float(scores[province_id]) / front_weight,
			0.0, 1.0)
		weights.append(weight)
		total += weight
	for index: int in chosen.size():
		var group := ArmyGroup.new()
		group.id = state.next_army_group_id
		state.next_army_group_id += 1
		group.owner = tag
		group.number = index + 1
		group.province = chosen[index]
		group.share = weights[index] / total
		state.army_groups[group.id] = group


static func _spaced(state: SimState, province_id: String, chosen: Array[String]) -> bool:
	for other: String in chosen:
		if other == province_id or ControlSystem.neighbors(state, other).has(province_id):
			return false
	return true


## Menace sur une province tenue par tag : poids du front si elle est disputée, un peu moins si une voisine
## l'est, sinon hostilité des voisins tenus par d'autres pays (relations sous le seuil). Une province tenue
## hors de son territoire loin du front (base louée…) ne reçoit pas de groupe (-1).
## relations : cache des relations déjà lues (« A>B » → valeur).
static func threat(state: SimState, tag: String, province_id: String, settings: Dictionary,
		relations: Dictionary = {}) -> float:
	var front := float(settings.get("front_weight", 1.0))
	if state.contested.has(province_id):
		return front
	var score := 0.0
	var hostile := float(settings.get("hostile_relation", 0.0))
	for neighbor: Variant in ControlSystem.neighbors(state, province_id):
		var neighbor_id := str(neighbor)
		if state.contested.has(neighbor_id):
			return front * float(settings.get("near_front", 1.0))
		var other := ControlSystem.controller(state, neighbor_id)
		if other.is_empty() or other == tag:
			continue
		if WarSystem.at_war(state, tag, other):
			return front * float(settings.get("near_front", 1.0))
		var key := tag + ">" + other
		if not relations.has(key):
			relations[key] = state.diplomacy.relation(tag, other)
		var relation := float(relations[key])
		if relation < hostile:
			score = maxf(score, front * (hostile - relation) / (DiplomacyState.LIMIT + hostile))
	if ControlSystem.owner(state, province_id) != tag:
		return -1.0
	return score


## Chemin terrestre (provinces tenues par tag) de from vers to, sans la province de départ. Vide si impossible.
static func find_path(state: SimState, tag: String, from: String, to: String) -> Array[String]:
	var result: Array[String] = []
	if from == to or ControlSystem.controller(state, to) != tag:
		return result
	var previous: Dictionary = {from: ""}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == to:
			break
		for neighbor: Variant in ControlSystem.neighbors(state, current):
			var next := str(neighbor)
			if previous.has(next) or ControlSystem.controller(state, next) != tag:
				continue
			previous[next] = current
			queue.append(next)
	if not previous.has(to):
		return result
	var step := to
	while step != from:
		result.push_front(step)
		step = str(previous[step])
	return result


## Jours pour aller d'une province à sa voisine (distance entre centres, vitesse des données).
static func travel_days(state: SimState, from: String, to: String) -> int:
	var speed := float(settings_of(state).get("speed_km_per_day", 1.0))
	return maxi(ceili(distance_km(state, from, to) / speed), 1)


static func distance_km(state: SimState, from: String, to: String) -> float:
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var a: Array = (provinces.get(from, {}) as Dictionary).get("center", [0.0, 0.0])
	var b: Array = (provinces.get(to, {}) as Dictionary).get("center", [0.0, 0.0])
	var size := state.map_size
	var lon_a := deg_to_rad(float(a[0]) / size.x * 2.0 * DEGREES_HALF_TURN - DEGREES_HALF_TURN)
	var lat_a := deg_to_rad(DEGREES_HALF_TURN / 2.0 - float(a[1]) / size.y * DEGREES_HALF_TURN)
	var lon_b := deg_to_rad(float(b[0]) / size.x * 2.0 * DEGREES_HALF_TURN - DEGREES_HALF_TURN)
	var lat_b := deg_to_rad(DEGREES_HALF_TURN / 2.0 - float(b[1]) / size.y * DEGREES_HALF_TURN)
	var h := pow(sin((lat_b - lat_a) / 2.0), 2.0) + cos(lat_a) * cos(lat_b) * pow(sin((lon_b - lon_a) / 2.0), 2.0)
	return 2.0 * EARTH_RADIUS_KM * asin(sqrt(clampf(h, 0.0, 1.0)))


## Donne l'ordre de marche (le chemin doit exister).
static func order_move(state: SimState, group: ArmyGroup, destination: String) -> void:
	group.path = find_path(state, group.owner, group.province, destination)
	group.destination = destination
	group.days_left = travel_days(state, group.province, group.path[0]) if not group.path.is_empty() else 0


## Un jour de marche pour tous les groupes en mouvement.
static func update_day(state: SimState) -> void:
	for group: ArmyGroup in state.army_groups.values():
		if not group.is_moving():
			continue
		# Une province perdue en route coupe le chemin : le groupe s'arrête.
		if ControlSystem.controller(state, group.path[0]) != group.owner:
			group.path.clear()
			group.days_left = 0
			continue
		group.days_left -= 1
		if group.days_left > 0:
			continue
		group.province = group.path.pop_front()
		if group.path.is_empty():
			state.add_event(EVENT_ARRIVED, group.owner, {"group": group.id, "province": group.province})
		else:
			group.days_left = travel_days(state, group.province, group.path[0])


## Groupes d'armées d'un pays, dans l'ordre.
static func groups_of(state: SimState, tag: String) -> Array[ArmyGroup]:
	var result: Array[ArmyGroup] = []
	for group: ArmyGroup in state.army_groups.values():
		if group.owner == tag:
			result.append(group)
	result.sort_custom(func(a: ArmyGroup, b: ArmyGroup) -> bool: return a.number < b.number)
	return result

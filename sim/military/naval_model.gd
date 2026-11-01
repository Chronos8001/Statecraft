class_name NavalModel
extends RefCounted
## Flottes : réseau des mers, création et placement au départ, déplacements, puissance navale, réparations.
##
## Réseau : zones maritimes voisines + liaisons des détroits et canaux (fermées quand le détroit est fermé) ;
## les lacs sont exclus. Les grandes marines ont leurs mers de base saisies (une flotte par mer). Pour les autres :
## nombre de flottes = effectifs de la marine / effectifs par flotte (1 au moins, au plus le maximum des données),
## placées dans les mers qui bordent le pays, les plus peuplées d'abord, en évitant deux mers voisines.
## Puissance d'une flotte = puissance de la marine du pays (effectifs × niveau^exposant × entraînement × moral,
## comme la puissance militaire) × sa part × son état.

const EARTH_RADIUS_KM := 6371.0
const DEGREES_HALF_TURN := 180.0
const SEA_KIND := "sea"
const EVENT_ARRIVED := &"fleet_arrived"


static func settings_of(state: SimState) -> Dictionary:
	return state.military_settings.get("navy", {})


## Réseau des mers (zones de mer seulement) et liaisons par les détroits et canaux.
static func setup_seas(state: SimState, sea_zones: Dictionary, straits: Dictionary) -> void:
	state.sea_zones = sea_zones
	state.sea_links.clear()
	state.sea_link_straits.clear()
	for zone_id: String in sea_zones.keys():
		var zone: Dictionary = sea_zones[zone_id]
		if str(zone.get("kind", "")) != SEA_KIND:
			continue
		var links: Array = []
		for neighbor: Variant in zone.get("neighbors", []):
			var key := str(int(neighbor))
			if str((sea_zones.get(key, {}) as Dictionary).get("kind", "")) == SEA_KIND:
				links.append(key)
		state.sea_links[zone_id] = links
	for strait_id: String in straits.keys():
		var pair: Array = (straits[strait_id] as Dictionary).get("sea_zones", [])
		if pair.size() != 2:
			continue
		var a := str(int(pair[0]))
		var b := str(int(pair[1]))
		if not state.sea_links.has(a) or not state.sea_links.has(b):
			continue
		if not (state.sea_links[a] as Array).has(b):
			(state.sea_links[a] as Array).append(b)
			(state.sea_links[b] as Array).append(a)
		state.sea_link_straits[a + "|" + b] = strait_id
		state.sea_link_straits[b + "|" + a] = strait_id


static func is_sea(state: SimState, zone_id: String) -> bool:
	return state.sea_links.has(zone_id)


## Mers qui bordent les provinces tenues par un pays (ou possédées, selon by_owner) : zone → population côtière.
static func coastal_zones(state: SimState, tag: String, by_owner: bool = false) -> Dictionary:
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var result: Dictionary = {}
	for zone_id: String in state.sea_links.keys():
		var weight := 0
		for province_id: Variant in (state.sea_zones[zone_id] as Dictionary).get("coasts", []):
			var key := str(int(province_id))
			var holder := ControlSystem.owner(state, key) if by_owner else ControlSystem.controller(state, key)
			if holder == tag:
				weight += int((provinces.get(key, {}) as Dictionary).get("population", 0)) + 1
		if weight > 0:
			result[zone_id] = weight
	return result


# --- Création -------------------------------------------------------------------------------------------------

static func navy_personnel(state: SimState, tag: String) -> float:
	var country := state.get_country(tag)
	if country == null or country.military == null or not country.military.has_branch("sea"):
		return 0.0
	return country.military.personnel(ArmyGroupModel.reserve_share(state)) \
		* float((country.military.branches["sea"] as Dictionary)["share"])


## Flottes de tous les pays qui ont une marine et une côte.
static func setup_start(state: SimState) -> void:
	state.fleets.clear()
	state.next_fleet_id = 1
	var settings := settings_of(state)
	if settings.is_empty() or state.sea_links.is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var personnel := navy_personnel(state, tag)
		if personnel <= 0.0:
			continue
		var chosen: Array[String] = []
		for zone_id: Variant in (state.diplomacy_start.get("fleets", {}) as Dictionary).get(tag, []):
			if is_sea(state, str(int(zone_id))):
				chosen.append(str(int(zone_id)))
		if chosen.is_empty():
			chosen = _home_seas(state, tag, personnel, settings)
		for index: int in chosen.size():
			var fleet := Fleet.new()
			fleet.id = state.next_fleet_id
			state.next_fleet_id += 1
			fleet.owner = tag
			fleet.number = index + 1
			fleet.zone = chosen[index]
			fleet.share = 1.0 / chosen.size()
			state.fleets[fleet.id] = fleet


## Mers où placer les flottes d'un pays sans base saisie : les plus peuplées, espacées si possible.
static func _home_seas(state: SimState, tag: String, personnel: float, settings: Dictionary) -> Array[String]:
	var chosen: Array[String] = []
	var zones := coastal_zones(state, tag, true)
	if zones.is_empty():
		return chosen
	var count := clampi(ceili(personnel / float(settings.get("personnel_per_fleet", 1.0))), 1,
		int(settings.get("max_fleets", 1)))
	var ranked: Array = zones.keys()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		return int(zones[a]) > int(zones[b]) if int(zones[a]) != int(zones[b]) else int(a) < int(b))
	for zone_id: String in ranked:
		if chosen.size() >= count:
			break
		if chosen.all(func(other: String) -> bool: return not (state.sea_links[other] as Array).has(zone_id)):
			chosen.append(zone_id)
	for zone_id: String in ranked:
		if chosen.size() >= count:
			break
		if not chosen.has(zone_id):
			chosen.append(zone_id)
	return chosen


static func fleets_of(state: SimState, tag: String) -> Array[Fleet]:
	var result: Array[Fleet] = []
	for fleet: Fleet in state.fleets.values():
		if fleet.owner == tag:
			result.append(fleet)
	result.sort_custom(func(a: Fleet, b: Fleet) -> bool: return a.number < b.number)
	return result


# --- Puissance ------------------------------------------------------------------------------------------------

## Puissance de toute la marine d'un pays (même échelle que la puissance militaire).
static func navy_power(state: SimState, tag: String) -> float:
	var country := state.get_country(tag)
	if country == null or country.military == null or not country.military.has_branch("sea"):
		return 0.0
	var rules: Dictionary = state.military_settings.get("power", {})
	var sea: Dictionary = country.military.branches["sea"]
	return navy_personnel(state, tag) * float((rules.get("branch_weights", {}) as Dictionary).get("sea", 1.0)) \
		* pow(float(sea["level"]), float(rules.get("level_exponent", 1.0))) \
		* float(sea["training"]) / float(rules.get("training_reference", 1.0)) \
		* float(sea["morale"]) / float(rules.get("morale_reference", 1.0)) * float(rules.get("scale", 1.0))


static func fleet_power(state: SimState, fleet: Fleet) -> float:
	return navy_power(state, fleet.owner) * fleet.share * fleet.condition


## Défense côtière d'un pays dans une mer qui borde ses côtes : part de sa puissance militaire, renforcée par
## ses missiles.
static func coastal_defense(state: SimState, tag: String) -> float:
	var country := state.get_country(tag)
	if country == null or country.military == null:
		return 0.0
	var settings := settings_of(state)
	return MilitarySystem.power(state, tag) * float(settings.get("coastal_share", 0.0)) \
		* float(country.military.special.get("missiles", 0.0)) / float(settings.get("coastal_missiles_reference", 1.0))


# --- Déplacements ---------------------------------------------------------------------------------------------

## Liaison franchissable entre deux zones (un détroit fermé coupe la liaison).
static func link_open(state: SimState, a: String, b: String) -> bool:
	var strait := str(state.sea_link_straits.get(a + "|" + b, ""))
	return strait.is_empty() or not state.closed_straits.has(strait)


## Chemin par la mer de from vers to, sans la zone de départ. Vide si impossible.
static func find_path(state: SimState, from: String, to: String) -> Array[String]:
	var result: Array[String] = []
	if from == to or not is_sea(state, to) or not is_sea(state, from):
		return result
	var previous: Dictionary = {from: ""}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == to:
			break
		for next: Variant in state.sea_links.get(current, []):
			var key := str(next)
			if previous.has(key) or not link_open(state, current, key):
				continue
			previous[key] = current
			queue.append(key)
	if not previous.has(to):
		return result
	var step := to
	while step != from:
		result.push_front(step)
		step = str(previous[step])
	return result


static func distance_km(state: SimState, from: String, to: String) -> float:
	var a: Array = (state.sea_zones.get(from, {}) as Dictionary).get("center", [0.0, 0.0])
	var b: Array = (state.sea_zones.get(to, {}) as Dictionary).get("center", [0.0, 0.0])
	var size := state.map_size
	var lon_a := deg_to_rad(float(a[0]) / size.x * 2.0 * DEGREES_HALF_TURN - DEGREES_HALF_TURN)
	var lat_a := deg_to_rad(DEGREES_HALF_TURN / 2.0 - float(a[1]) / size.y * DEGREES_HALF_TURN)
	var lon_b := deg_to_rad(float(b[0]) / size.x * 2.0 * DEGREES_HALF_TURN - DEGREES_HALF_TURN)
	var lat_b := deg_to_rad(DEGREES_HALF_TURN / 2.0 - float(b[1]) / size.y * DEGREES_HALF_TURN)
	var h := pow(sin((lat_b - lat_a) / 2.0), 2.0) + cos(lat_a) * cos(lat_b) * pow(sin((lon_b - lon_a) / 2.0), 2.0)
	return 2.0 * EARTH_RADIUS_KM * asin(sqrt(clampf(h, 0.0, 1.0)))


static func travel_days(state: SimState, from: String, to: String) -> int:
	return maxi(ceili(distance_km(state, from, to) / float(settings_of(state).get("speed_km_per_day", 1.0))), 1)


## Donne l'ordre de route (le chemin doit exister).
static func order_move(state: SimState, fleet: Fleet, destination: String) -> void:
	fleet.path = find_path(state, fleet.zone, destination)
	fleet.destination = destination
	fleet.days_left = travel_days(state, fleet.zone, fleet.path[0]) if not fleet.path.is_empty() else 0


## Un jour de route pour toutes les flottes en mouvement (un détroit fermé en route les arrête).
static func update_day(state: SimState) -> void:
	for fleet: Fleet in state.fleets.values():
		if not fleet.is_moving():
			continue
		if not link_open(state, fleet.zone, fleet.path[0]):
			fleet.path.clear()
			fleet.days_left = 0
			continue
		fleet.days_left -= 1
		if fleet.days_left > 0:
			continue
		fleet.zone = fleet.path.pop_front()
		if fleet.path.is_empty():
			state.add_event(EVENT_ARRIVED, fleet.owner, {"fleet": fleet.id, "zone": fleet.zone})
		else:
			fleet.days_left = travel_days(state, fleet.zone, fleet.path[0])


## Chaque mois, une flotte près de ses côtes et hors de portée de l'ennemi (aucune force ennemie dans la mer) se
## répare.
static func repair_month(state: SimState) -> void:
	var settings := settings_of(state)
	for fleet: Fleet in state.fleets.values():
		if fleet.condition >= 1.0 or fleet.is_moving():
			continue
		if NavalResolver.under_fire(state, fleet.zone, fleet.owner) or not coastal_zones(state, fleet.owner).has(fleet.zone):
			continue
		fleet.condition = minf(fleet.condition + float(settings.get("repair_per_month", 0.0)), 1.0)
		if fleet.condition >= float(settings.get("retreat_condition", 0.0)):
			fleet.damage_reported = false


## Mer côtière sûre la plus proche (bordant nos côtes, sans force ennemie, à distance de repli) ; "" si aucune.
static func safe_harbor(state: SimState, fleet: Fleet) -> String:
	var best := ""
	var best_distance := INF
	for zone_id: Variant in coastal_zones(state, fleet.owner).keys():
		var key := str(zone_id)
		if NavalResolver.under_fire(state, key, fleet.owner):
			continue
		var distance := distance_km(state, fleet.zone, key)
		if distance > float(settings_of(state).get("retreat_max_km", INF)):
			continue
		if key != fleet.zone and find_path(state, fleet.zone, key).is_empty():
			continue
		if distance < best_distance:
			best = key
			best_distance = distance
	return best

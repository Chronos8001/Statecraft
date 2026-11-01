class_name ControlSystem
extends RefCounted
## Contrôle militaire des provinces pendant la partie. Chaque province a un contrôleur ; une province disputée
## est en partie tenue par un autre pays (part de 0 à 1). Quand la part atteint 1, le contrôleur change : les
## provinces changent de main progressivement. Départ : contrôleurs de provinces.json + front réel de 2026.

const EVENT_CONTROL := &"province_control_changed"
const FULL := 1.0


static func setup_start(state: SimState) -> void:
	state.province_control.clear()
	state.contested.clear()
	state.province_neighbors.clear()
	state.provinces_by_owner.clear()
	state.province_owner.clear()
	state.border_provinces.clear()
	state.control_version += 1
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	for province_id: String in provinces.keys():
		var province: Dictionary = provinces[province_id]
		var ids: Array[String] = []
		for neighbor: Variant in province.get("neighbors", []):
			ids.append(str(int(neighbor)))
		state.province_neighbors[province_id] = ids
		var owner := str(province.get("owner", ""))
		if not owner.is_empty():
			state.province_control[province_id] = str(province.get("controller", owner))
			state.province_owner[province_id] = owner
			if not state.provinces_by_owner.has(owner):
				state.provinces_by_owner[owner] = []
			(state.provinces_by_owner[owner] as Array).append(province_id)
	refresh_borders(state)
	for entry: Variant in (state.diplomacy_start.get("front", {}) as Dictionary).get("list", []):
		var values: Array = entry
		var province_id := str(int(values[0]))
		if state.province_control.has(province_id) and state.countries.has(values[1]):
			state.contested[province_id] = {"by": str(values[1]), "share": clampf(float(values[2]), 0.0, FULL)}


## Voisins terrestres entre pays et provinces frontalières, d'après les propriétaires du moment.
static func refresh_borders(state: SimState) -> void:
	state.border_provinces.clear()
	state.land_neighbors.clear()
	for province_id: String in state.province_owner.keys():
		var owner := str(state.province_owner[province_id])
		var border := false
		for neighbor: String in state.province_neighbors.get(province_id, []):
			var other := str(state.province_owner.get(neighbor, ""))
			if other != owner and not other.is_empty():
				border = true
				if not state.land_neighbors.has(owner):
					state.land_neighbors[owner] = {}
				(state.land_neighbors[owner] as Dictionary)[other] = true
		if border:
			state.border_provinces.append(province_id)
	state.trade.land_neighbors = state.land_neighbors
	state.trade.dirty = true


static func controller(state: SimState, province_id: String) -> String:
	return str(state.province_control.get(province_id, ""))


static func owner(state: SimState, province_id: String) -> String:
	if not state.province_owner.is_empty():
		return str(state.province_owner.get(province_id, ""))
	var province: Dictionary = (state.energy_definitions.get("provinces", {}) as Dictionary).get(province_id, {})
	return str(province.get("owner", ""))


## Part de la province tenue par un pays (contrôleur : 1 - part disputée ; autre pays : sa part disputée).
static func share_held(state: SimState, province_id: String, tag: String) -> float:
	var contest: Dictionary = state.contested.get(province_id, {})
	var disputed := float(contest.get("share", 0.0))
	if controller(state, province_id) == tag:
		return FULL - disputed
	return disputed if str(contest.get("by", "")) == tag else 0.0


## Part de la province occupée (tenue par d'autres que son propriétaire).
static func occupied_share(state: SimState, province_id: String) -> float:
	var owner_tag := owner(state, province_id)
	return FULL - share_held(state, province_id, owner_tag) if not owner_tag.is_empty() else 0.0


## Change le contrôleur entier d'une province.
static func set_controller(state: SimState, province_id: String, tag: String) -> void:
	var previous := controller(state, province_id)
	if state.contested.erase(province_id):
		state.fronts_dirty = true
		state.control_version += 1
	if previous == tag:
		return
	state.fronts_dirty = true
	state.control_version += 1
	state.province_control[province_id] = tag
	state.add_event(EVENT_CONTROL, tag, {"province": province_id, "previous": previous})


## Un pays gagne (ou perd, si delta < 0) du terrain dans une province ; à 100 %, il en prend le contrôle.
static func advance(state: SimState, province_id: String, tag: String, delta: float) -> void:
	if controller(state, province_id) == tag:
		var contest: Dictionary = state.contested.get(province_id, {})
		if contest.is_empty():
			return
		var left := float(contest["share"]) - delta
		if left <= 0.0:
			state.contested.erase(province_id)
			state.fronts_dirty = true
			state.control_version += 1
		else:
			contest["share"] = minf(left, FULL)
		return
	var current: Dictionary = state.contested.get(province_id, {})
	var share := float(current.get("share", 0.0)) if str(current.get("by", "")) == tag else 0.0
	share = clampf(share + delta, 0.0, FULL)
	if share >= FULL:
		set_controller(state, province_id, tag)
	elif share <= 0.0:
		if state.contested.erase(province_id):
			state.fronts_dirty = true
			state.control_version += 1
	else:
		if str(current.get("by", "")) != tag:
			state.fronts_dirty = true
			state.control_version += 1
		state.contested[province_id] = {"by": tag, "share": share}


## Provinces terrestres voisines d'une province (identifiants en texte).
static func neighbors(state: SimState, province_id: String) -> Array:
	return state.province_neighbors.get(province_id, [])


## Alliés militaires : traité de défense mutuelle ou même alliance militaire (OTAN, OTSC…).
static func allied(state: SimState, a: String, b: String) -> bool:
	if a == b:
		return true
	if state.diplomacy.has_treaty(a, b, "mutual_defense"):
		return true
	for organization: Dictionary in state.diplomacy.organizations.values():
		if str(organization.get("kind", "")) == "military_alliance":
			var members: Array = organization.get("members", [])
			if members.has(a) and members.has(b):
				return true
	return false

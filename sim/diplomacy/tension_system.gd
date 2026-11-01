class_name TensionSystem
extends SimSystem
## Tension mondiale (0 à 100) et revendications territoriales. La tension monte avec les ultimatums, les
## revendications, les coups d'État, les guerres civiles et les sanctions, baisse avec les traités ; elle revient
## lentement vers son niveau de fond. Elle débloque des actions de plus en plus agressives (seuils en données).
## Les cessions de territoire viendront avec les guerres et les traités de paix (étape 7).

const PRIORITY := 33
const LIMIT := 100.0
const EVENT_CLAIM := &"claim_changed"
const EVENT_THRESHOLD := &"tension_threshold"


func get_id() -> StringName:
	return &"tension"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	var settings := settings_of(state)
	if settings.is_empty():
		return
	var diplomacy := state.diplomacy
	var before := diplomacy.world_tension
	diplomacy.world_tension += (float(settings.get("baseline", 0.0)) - diplomacy.world_tension) \
		* float(settings.get("return", 0.0))
	_announce_thresholds(state, before)


static func settings_of(state: SimState) -> Dictionary:
	return state.diplomacy_settings.get("tension", {})


## Ajoute à la tension la part prévue pour un type d'événement.
static func add_event(state: SimState, event: String) -> void:
	var settings := settings_of(state)
	if settings.is_empty():
		return
	add(state, float((settings.get("events", {}) as Dictionary).get(event, 0.0)))


## Ajoute (ou retire) des points de tension.
static func add(state: SimState, amount: float) -> void:
	if settings_of(state).is_empty():
		return
	var before := state.diplomacy.world_tension
	state.diplomacy.world_tension = clampf(before + amount, 0.0, LIMIT)
	_announce_thresholds(state, before)


## Seuil franchi (dans un sens ou dans l'autre) : une action se débloque ou se referme.
static func _announce_thresholds(state: SimState, before: float) -> void:
	var now := state.diplomacy.world_tension
	var thresholds: Dictionary = settings_of(state).get("thresholds", {})
	for action: Variant in thresholds.keys():
		var level := float(thresholds[action])
		if (before < level) != (now < level):
			state.add_event(EVENT_THRESHOLD, "", {"action": action, "unlocked": now >= level})


static func unlocked(state: SimState, action: String) -> bool:
	var thresholds: Dictionary = settings_of(state).get("thresholds", {})
	return not thresholds.has(action) or state.diplomacy.world_tension >= float(thresholds[action])


static func threshold(state: SimState, action: String) -> float:
	return float((settings_of(state).get("thresholds", {}) as Dictionary).get(action, 0.0))


static func setup_start(state: SimState) -> void:
	var settings := settings_of(state)
	state.diplomacy.world_tension = float(settings.get("start", 0.0))
	for entry: Variant in (state.diplomacy_start.get("claims", {}) as Dictionary).get("list", []):
		var values: Array = entry
		if state.countries.has(values[0]) and state.countries.has(values[1]):
			var provinces: Array[String] = []
			for province_id: Variant in values[2]:
				provinces.append(str(int(province_id)))
			add_claim(state, str(values[0]), str(values[1]), provinces)


static func add_claim(state: SimState, claimant: String, target: String, provinces: Array[String]) -> int:
	var diplomacy := state.diplomacy
	var claim_id := diplomacy.next_claim_id
	diplomacy.next_claim_id += 1
	diplomacy.claims[claim_id] = {"claimant": claimant, "target": target, "provinces": provinces}
	return claim_id


## Revendications entre deux pays (dans les deux sens) : [identifiants].
static func claims_between(state: SimState, a: String, b: String) -> Array[int]:
	var result: Array[int] = []
	for claim_id: Variant in state.diplomacy.claims.keys():
		var claim: Dictionary = state.diplomacy.claims[claim_id]
		if (claim["claimant"] == a and claim["target"] == b) or (claim["claimant"] == b and claim["target"] == a):
			result.append(int(claim_id))
	return result


## Provinces visées par une revendication (toutes celles du pays visé si la liste est vide).
static func claimed_provinces(state: SimState, claim: Dictionary) -> Array:
	var provinces: Array = claim.get("provinces", [])
	if not provinces.is_empty():
		return provinces
	var result: Array = []
	for entry: Array in (state.politics_definitions.get("provinces", {}) as Dictionary).get(str(claim["target"]), []):
		result.append(str(entry[0]))
	return result


## Provinces du pays visé qui touchent notre territoire (revendicables).
static func adjacent_provinces(state: SimState, claimant: String, target: String, provinces: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for province_id: String in provinces.keys():
		var province: Dictionary = provinces[province_id]
		if str(province.get("owner", "")) != target:
			continue
		for neighbor: Variant in province.get("neighbors", []):
			if str((provinces.get(str(neighbor), {}) as Dictionary).get("owner", "")) == claimant:
				result.append(province_id)
				break
	result.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return result


static func is_claimed_by(state: SimState, claimant: String, province_id: String) -> bool:
	for claim: Dictionary in state.diplomacy.claims.values():
		if claim["claimant"] == claimant and claimed_provinces(state, claim).has(province_id):
			return true
	return false


## Faire valoir, abandonner ou ajouter une revendication.
static func press_claim(state: SimState, claim_id: int) -> void:
	var settings: Dictionary = settings_of(state).get("claims", {})
	var claim: Dictionary = state.diplomacy.claims[claim_id]
	var claimant := str(claim["claimant"])
	var country := state.get_country(claimant)
	state.diplomacy.set_cooldown("claim_%d" % claim_id, claimant, str(claim["target"]), int(settings.get("cooldown", 0)))
	state.diplomacy.change_relation(claimant, str(claim["target"]), float(settings.get("press_relation", 0.0)))
	var points := float(settings.get("press_military", 0.0))
	country.society.bonuses["military"] = float(country.society.bonuses.get("military", 0.0)) + points
	country.crisis_bonuses.append({"group": "military", "points": points, "months_left": int(settings.get("press_months", 1))})
	var ruling: PartyState = country.politics.parties.get(country.politics.ruling_party())
	if ruling != null:
		ruling.drift += float(settings.get("press_drift", 0.0))
	add_event(state, "claim_pressed")
	state.add_event(EVENT_CLAIM, claimant, {"target": claim["target"], "action": "press"})


static func renounce_claim(state: SimState, claim_id: int) -> void:
	var settings: Dictionary = settings_of(state).get("claims", {})
	var claim: Dictionary = state.diplomacy.claims[claim_id]
	var claimant := str(claim["claimant"])
	var target := str(claim["target"])
	var country := state.get_country(claimant)
	state.diplomacy.claims.erase(claim_id)
	state.diplomacy.change_relation(claimant, target, float(settings.get("renounce_relation", 0.0)))
	state.diplomacy.change_trust(claimant, target, float(settings.get("renounce_trust", 0.0)))
	var points := float(settings.get("renounce_military", 0.0))
	country.society.bonuses["military"] = float(country.society.bonuses.get("military", 0.0)) + points
	country.crisis_bonuses.append({"group": "military", "points": points, "months_left": int(settings.get("press_months", 1))})
	if country.society.start_satisfaction.has("military"):
		country.society.start_satisfaction["military"] = float(country.society.start_satisfaction["military"]) \
			+ float(settings.get("renounce_military_start", 0.0))
	add_event(state, "claim_renounced")
	state.add_event(EVENT_CLAIM, claimant, {"target": target, "action": "renounce"})


static func new_claim(state: SimState, claimant: String, target: String, province_id: String) -> void:
	var settings: Dictionary = settings_of(state).get("claims", {})
	var provinces: Array[String] = [province_id]
	add_claim(state, claimant, target, provinces)
	state.diplomacy.change_relation(claimant, target, float(settings.get("add_relation", 0.0)))
	add_event(state, "claim_added")
	state.add_event(EVENT_CLAIM, claimant, {"target": target, "action": "add"})

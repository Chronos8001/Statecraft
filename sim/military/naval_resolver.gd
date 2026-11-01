class_name NavalResolver
extends RefCounted
## Contrôle des mers et combats navals (module remplaçable via MilitaryRegistry). Chaque jour, pour chaque
## guerre entre États, dans chaque mer disputée (les deux camps y ont une force, ou une flotte croise au large des
## côtes ennemies) :
##
## force d'un camp = puissance de ses flottes présentes + défense côtière de ses membres dont la côte borde la mer ;
## le camp qui dépasse l'autre du rapport de contrôle domine la mer, sinon elle est disputée.
## Une flotte face à une force ennemie s'abîme : taux × (force ennemie / force de son camp)^exposant (borné)
## × aviation de l'ennemi. Sous un seuil d'état, l'avarie grave est signalée (l'IA rentre au port).

const EVENT_DAMAGED := &"fleet_damaged"
const MIN_STRENGTH := 0.001

## Mers côtières de chaque belligérant, gardées tant que le contrôle des provinces ne change pas.
var _coasts: Dictionary = {}
var _coasts_version: int = -1


func resolve_day(state: SimState) -> void:
	state.sea_control.clear()
	var settings := NavalModel.settings_of(state)
	if state.wars.is_empty() or settings.is_empty() or state.sea_links.is_empty():
		return
	if _coasts_version != state.control_version:
		_coasts.clear()
		_coasts_version = state.control_version
	var by_zone: Dictionary = {}
	for fleet: Fleet in state.fleets.values():
		if not by_zone.has(fleet.zone):
			by_zone[fleet.zone] = []
		(by_zone[fleet.zone] as Array).append(fleet)
	var ids: Array = state.wars.keys()
	ids.sort()
	for war_id: Variant in ids:
		var war: War = state.wars[war_id]
		if war.civil:
			continue
		var zones: Dictionary = {}
		for tag: String in war.attackers + war.defenders:
			for zone_id: Variant in _coastal(state, tag).keys():
				zones[zone_id] = true
		for zone_id: Variant in by_zone.keys():
			for fleet: Fleet in by_zone[zone_id]:
				if war.involves(fleet.owner):
					zones[zone_id] = true
		var airs := {War.ATTACKERS: WarResolver.side_air_power(state, war, War.ATTACKERS),
			War.DEFENDERS: WarResolver.side_air_power(state, war, War.DEFENDERS)}
		var keys: Array = zones.keys()
		keys.sort()
		for zone_id: Variant in keys:
			_resolve_zone(state, war, str(zone_id), by_zone.get(zone_id, []), airs, settings)


func _coastal(state: SimState, tag: String) -> Dictionary:
	if not _coasts.has(tag):
		_coasts[tag] = NavalModel.coastal_zones(state, tag)
	return _coasts[tag]


## Une mer compte dans la guerre si les deux camps y ont une force, ou si une flotte d'un camp croise au large
## des côtes de l'autre (blocus possible même sans défense côtière).
func _disputed(state: SimState, war: War, zone_id: String, fleets: Array, attack: float, defense: float) -> bool:
	if attack > 0.0 and defense > 0.0:
		return true
	for fleet: Fleet in fleets:
		var side := war.side_of(fleet.owner)
		if side.is_empty():
			continue
		for enemy: String in war.members(War.other_side(side)):
			if _coastal(state, enemy).has(zone_id):
				return true
	return false


## Forces des deux camps dans une mer : {attackers, defenders}.
func zone_strength(state: SimState, war: War, zone_id: String, fleets: Array) -> Dictionary:
	var strength := {War.ATTACKERS: 0.0, War.DEFENDERS: 0.0}
	for fleet: Fleet in fleets:
		var side := war.side_of(fleet.owner)
		if not side.is_empty():
			strength[side] = float(strength[side]) + NavalModel.fleet_power(state, fleet)
	for tag: String in war.attackers + war.defenders:
		if _coastal(state, tag).has(zone_id):
			var side := war.side_of(tag)
			strength[side] = float(strength[side]) + NavalModel.coastal_defense(state, tag)
	return strength


func _resolve_zone(state: SimState, war: War, zone_id: String, fleets: Array, airs: Dictionary,
		settings: Dictionary) -> void:
	var strength := zone_strength(state, war, zone_id, fleets)
	var attack := float(strength[War.ATTACKERS])
	var defense := float(strength[War.DEFENDERS])
	if not _disputed(state, war, zone_id, fleets, attack, defense):
		return
	if not state.sea_control.has(zone_id):
		var ratio := float(settings.get("control_ratio", 1.0))
		var control := {"war": war.id, War.ATTACKERS: attack, War.DEFENDERS: defense}
		if attack >= ratio * defense:
			control.merge({"side": War.ATTACKERS, "leader": war.attacker_leader()})
		elif defense >= ratio * attack:
			control.merge({"side": War.DEFENDERS, "leader": war.defender_leader()})
		else:
			control["contested"] = true
		state.sea_control[zone_id] = control
	for fleet: Fleet in fleets:
		var side := war.side_of(fleet.owner)
		if side.is_empty():
			continue
		var other := War.other_side(side)
		var enemy := float(strength[other])
		if enemy <= 0.0:
			continue
		var odds := clampf(pow(enemy / maxf(float(strength[side]), MIN_STRENGTH), float(settings.get("damage_odds_exponent", 1.0))),
			float(settings.get("damage_odds_min", 0.0)), float(settings.get("damage_odds_max", 1.0)))
		var damage := float(settings.get("damage_rate", 0.0)) * odds \
			* WarResolver.air_factor(state, war, war.members(other)[0], airs)
		fleet.condition = maxf(fleet.condition - damage, float(settings.get("min_condition", 0.0)))
		if fleet.condition < float(settings.get("retreat_condition", 0.0)) and not fleet.damage_reported:
			fleet.damage_reported = true
			state.add_event(EVENT_DAMAGED, fleet.owner, {"fleet": fleet.id, "zone": zone_id})


## Camp qui domine une mer (tag de son meneur, "" si personne ou si elle est disputée).
static func controller(state: SimState, zone_id: String) -> String:
	var control: Dictionary = state.sea_control.get(zone_id, {})
	return str(control.get("leader", ""))


## L'ennemi a une force dans cette mer (flottes ou défense côtière) : pas de réparation possible.
static func under_fire(state: SimState, zone_id: String, tag: String) -> bool:
	var control: Dictionary = state.sea_control.get(zone_id, {})
	var war: War = state.wars.get(int(control.get("war", -1)))
	if war == null or not war.involves(tag):
		return false
	return float(control.get(War.other_side(war.side_of(tag)), 0.0)) > 0.0


## La mer est dangereuse pour un pays : l'ennemi la domine ou la dispute.
static func hostile_to(state: SimState, zone_id: String, tag: String) -> bool:
	var control: Dictionary = state.sea_control.get(zone_id, {})
	if control.is_empty():
		return false
	var war: War = state.wars.get(int(control.get("war", -1)))
	if war == null or not war.involves(tag):
		return false
	return bool(control.get("contested", false)) or war.side_of(tag) != str(control.get("side", ""))

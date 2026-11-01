class_name WarResolver
extends RefCounted
## Résolution des combats (module remplaçable via MilitaryRegistry ; un DLC peut le remplacer par une
## résolution détaillée). Chaque jour et sur chaque front, chaque camp pousse sur une province ennemie :
##
## poussée = forces engagées × attaque de la posture × aviation × ravitaillement × (1 - frappes et raids subis) ;
## tenue = forces adverses × défense de leur posture × aviation × ravitaillement × défense du terrain visé.
## Si la poussée dépasse la tenue, le camp gagne avance/jour × avance de la posture × log2(poussée / tenue)
## (plafonné) d'une part de la province visée, qui change de contrôleur à 100 %.
## Aviation : 1 ± maximum × (2 × part de l'aviation des deux camps de la guerre - 1).
## Ravitaillement : (base + poids × infrastructures du front, moins les dégâts des frappes) × (1 - pénalité au-delà d'une distance libre
## depuis la province la plus peuplée), borné ; forfait pour les rebelles.
## Pertes : soldats engagés × taux × pertes de la posture × (forces adverses / nos forces)^exposant (borné) ;
## elles usent l'équipement et le moral de l'armée de terre.

const EVENT_PROVINCE_TAKEN := &"province_taken"
const LOG2 := 0.6931471805599453
const KM_PER_UNIT := 1000.0
const INFRASTRUCTURE_MAX := 10.0
const MIN_STRENGTH := 0.001


## Un jour de combat sur tous les fronts.
func resolve_day(state: SimState) -> void:
	if state.wars.is_empty():
		return
	FrontSystem.refresh(state)
	var settings := FrontSystem.combat_settings(state)
	if settings.is_empty() or state.fronts.is_empty():
		return
	var engaged: Dictionary = {}
	var seats: Dictionary = {}
	var keys: Array = state.fronts.keys()
	keys.sort()
	var fronts: Array[Front] = []
	for key: Variant in keys:
		fronts.append(state.fronts[key])
	for front: Front in fronts:
		for tag: String in [front.a, front.b]:
			if not engaged.has(tag):
				engaged[tag] = FrontSystem.engaged_personnel(state, tag)
				seats[tag] = FrontSystem.seat(state, tag)
	var airs: Dictionary = {}
	for front: Front in fronts:
		var war: War = state.wars.get(front.war_id)
		if war == null:
			continue
		if not airs.has(war.id):
			airs[war.id] = {War.ATTACKERS: side_air_power(state, war, War.ATTACKERS),
				War.DEFENDERS: side_air_power(state, war, War.DEFENDERS)}
		for tag: String in [front.a, front.b]:
			var men := float((engaged[tag] as Dictionary).get(front.key, 0.0))
			front.engaged[tag] = men
			front.strength[tag] = men * FrontSystem.quality(state, tag) \
				* air_factor(state, war, tag, airs[war.id]) * supply(state, front, tag, str(seats[tag])) \
				* (1.0 - MilitaryActions.front_penalty(state, front, tag))
	for front: Front in fronts:
		var war: War = state.wars.get(front.war_id)
		if war == null or war.in_ceasefire():
			front.progress.clear()
			continue
		var pushes: Dictionary = {}
		for tag: String in [front.a, front.b]:
			pushes[tag] = _push(state, front, tag, settings)
		_losses(state, war, front, settings)
		for tag: String in [front.a, front.b]:
			var push: Dictionary = pushes[tag]
			front.progress[tag] = float(push.get("delta", 0.0))
			if float(push.get("delta", 0.0)) > 0.0 and state.wars.has(war.id):
				_advance(state, tag, str(push["target"]), float(push["delta"]), settings)


## Poussée d'un camp sur un front : {target, delta} (delta 0 si la posture n'attaque pas ou s'il est trop faible).
func _push(state: SimState, front: Front, tag: String, settings: Dictionary) -> Dictionary:
	var postures: Dictionary = settings.get("postures", {})
	var ours: Dictionary = postures.get(front.posture_of(tag), {})
	var enemy := front.other(tag)
	var theirs: Dictionary = postures.get(front.posture_of(enemy), {})
	var advance := float(ours.get("advance", 0.0))
	var attack := float(ours.get("attack", 0.0))
	if advance <= 0.0 or attack <= 0.0:
		return {}
	var target := target_province(state, front, tag)
	if target.is_empty():
		return {}
	var push := float(front.strength.get(tag, 0.0)) * attack
	var hold := maxf(float(front.strength.get(enemy, 0.0)) * float(theirs.get("defense", 1.0))
		* terrain_defense(state, target), MIN_STRENGTH)
	if push <= hold:
		return {}
	var odds := minf(log(push / hold) / LOG2, float(settings.get("max_odds_log", 1.0)))
	return {"target": target, "delta": float(settings.get("advance_per_day", 0.0)) * advance * odds}


## Province visée par un camp : une disputée où il progresse déjà (la plus avancée), puis une disputée tenue
## par l'ennemi chez nous, puis la province ennemie au contact la moins défendable par le terrain.
static func target_province(state: SimState, front: Front, tag: String) -> String:
	var enemy := front.other(tag)
	var best := ""
	var best_share := -1.0
	for province_id: String in front.contested:
		var contest: Dictionary = state.contested.get(province_id, {})
		if str(contest.get("by", "")) == tag and float(contest["share"]) > best_share:
			best = province_id
			best_share = float(contest["share"])
	if not best.is_empty():
		return best
	for province_id: String in front.contested:
		if ControlSystem.controller(state, province_id) == tag:
			return province_id
	var best_defense := INF
	for province_id: Variant in front.provinces_of(enemy):
		var key := str(province_id)
		if ControlSystem.controller(state, key) != enemy or state.contested.has(key):
			continue
		var defense := terrain_defense(state, key)
		if defense < best_defense:
			best = key
			best_defense = defense
	return best


static func terrain_defense(state: SimState, province_id: String) -> float:
	var province: Dictionary = (state.energy_definitions.get("provinces", {}) as Dictionary).get(province_id, {})
	return float((state.terrain_definitions.get(str(province.get("terrain", "")), {}) as Dictionary).get("defense", 1.0))


## Puissance aérienne d'un camp de la guerre (aviation des pays ; les rebelles n'en ont pas).
static func side_air_power(state: SimState, war: War, side: String) -> float:
	var rules: Dictionary = state.military_settings.get("power", {})
	var total := 0.0
	for tag: String in war.members(side):
		var country := state.get_country(tag)
		if country == null or country.military == null or not country.military.has_branch("air"):
			continue
		var air: Dictionary = country.military.branches["air"]
		total += country.military.personnel(ArmyGroupModel.reserve_share(state)) * float(air["share"]) \
			* pow(float(air["level"]), float(rules.get("level_exponent", 1.0))) * float(air["training"]) \
			* float(air["morale"])
	return total


static func air_factor(state: SimState, war: War, tag: String, airs: Dictionary) -> float:
	var side := war.side_of(tag)
	var ours := float(airs.get(side, 0.0))
	var total := ours + float(airs.get(War.other_side(side), 0.0))
	if total <= 0.0:
		return 1.0
	return 1.0 + float(FrontSystem.combat_settings(state).get("air_max", 0.0)) * (2.0 * ours / total - 1.0)


## Ravitaillement d'un camp sur un front (0 à 1).
static func supply(state: SimState, front: Front, tag: String, seat_id: String) -> float:
	var rules: Dictionary = FrontSystem.combat_settings(state).get("supply", {})
	if WarSystem.is_rebel(state, tag):
		return float(rules.get("rebel", 1.0))
	var provinces: Array = front.provinces_of(tag)
	if provinces.is_empty():
		return float(rules.get("min", 0.0))
	var definitions: Dictionary = state.energy_definitions.get("provinces", {})
	var infrastructure := 0.0
	for province_id: Variant in provinces:
		infrastructure += maxf(float((definitions.get(str(province_id), {}) as Dictionary).get("infrastructure", 0.0))
			- float(state.infrastructure_damage.get(str(province_id), 0.0)), 0.0)
	infrastructure /= provinces.size()
	var value := float(rules.get("infrastructure_base", 1.0)) + float(rules.get("infrastructure_weight", 0.0)) * infrastructure
	if not seat_id.is_empty():
		var distance := ArmyGroupModel.distance_km(state, seat_id, str(provinces[0]))
		value *= 1.0 - float(rules.get("penalty_per_1000_km", 0.0)) \
			* maxf(distance - float(rules.get("free_km", 0.0)), 0.0) / KM_PER_UNIT
	return clampf(value, float(rules.get("min", 0.0)), 1.0)


## Pertes du jour des deux camps d'un front.
func _losses(state: SimState, war: War, front: Front, settings: Dictionary) -> void:
	var postures: Dictionary = settings.get("postures", {})
	for tag: String in [front.a, front.b]:
		var men := float(front.engaged.get(tag, 0.0))
		if men <= 0.0:
			continue
		var enemy := front.other(tag)
		var odds := clampf(float(front.strength.get(enemy, 0.0)) / maxf(float(front.strength.get(tag, 0.0)), MIN_STRENGTH),
			float(settings.get("loss_odds_min", 0.0)), float(settings.get("loss_odds_max", 1.0)))
		var killed := men * float(settings.get("loss_rate", 0.0)) \
			* float((postures.get(front.posture_of(tag), {}) as Dictionary).get("losses", 1.0)) \
			* pow(odds, float(settings.get("loss_odds_exponent", 1.0)))
		apply_losses(state, war, tag, killed, settings)


## Pertes d'un pays ou d'une faction : effectifs, usure de l'équipement et du moral de l'armée de terre.
static func apply_losses(state: SimState, war: War, tag: String, killed: float, settings: Dictionary) -> void:
	if killed <= 0.0:
		return
	var land := FrontSystem.land_personnel(state, tag)
	var share := killed / land if land > 0.0 else 0.0
	war.casualties[tag] = float(war.casualties.get(tag, 0.0)) + killed
	var faction: RebelFaction = state.rebels.get(tag)
	var morale_drop := share * float(settings.get("morale_per_loss", 0.0))
	if faction != null:
		faction.personnel = maxf(faction.personnel - killed, 0.0)
		faction.morale = maxf(faction.morale - morale_drop, 1.0)
		return
	var military := state.get_country(tag).military
	military.losses += killed
	var values: Dictionary = military.branches["land"]
	var equipment: Dictionary = state.military_settings.get("equipment", {})
	values["level"] = maxf(float(values["level"]) - share * float(settings.get("equipment_wear", 0.0)),
		float(equipment.get("min_level", 1.0)))
	var morale: Dictionary = state.military_settings.get("morale", {})
	values["morale"] = maxf(float(values["morale"]) - morale_drop, float(morale.get("min", 1.0)))


## Le camp gagne du terrain ; une province prise remonte son moral et fait reculer les groupes ennemis.
func _advance(state: SimState, tag: String, province_id: String, delta: float, settings: Dictionary) -> void:
	var previous := ControlSystem.controller(state, province_id)
	ControlSystem.advance(state, province_id, tag, delta)
	if ControlSystem.controller(state, province_id) == tag and previous != tag:
		_morale(state, tag, float(settings.get("morale_capture", 0.0)))
		_morale(state, previous, -float(settings.get("morale_capture", 0.0)))
		ArmyGroupModel.evacuate(state, province_id)
		state.add_event(EVENT_PROVINCE_TAKEN, tag, {"province": province_id, "previous": previous})


static func _morale(state: SimState, tag: String, amount: float) -> void:
	var faction: RebelFaction = state.rebels.get(tag)
	if faction != null:
		faction.morale = clampf(faction.morale + amount, 1.0, 100.0)
		return
	var country := state.get_country(tag)
	if country == null or country.military == null or not country.military.has_branch("land"):
		return
	var values: Dictionary = country.military.branches["land"]
	var morale: Dictionary = state.military_settings.get("morale", {})
	values["morale"] = clampf(float(values["morale"]) + amount, float(morale.get("min", 1.0)), float(morale.get("max", 100.0)))

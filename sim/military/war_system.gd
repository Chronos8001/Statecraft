class_name WarSystem
extends RefCounted
## Guerres : déclaration avec un but de guerre justifié, appel aux armes des alliés, entrée en guerre aux côtés
## d'un pays, paix blanche (retour au contrôle d'avant-guerre, trêve) et guerres civiles contre une faction
## rebelle. Les fronts et les combats arrivent avec l'étape 7c2 : ici, les lignes ne bougent pas.
##
## Coût d'une déclaration : relations, confiance et opinion de la cible ; opinion du reste du monde, légitimité
## et stabilité selon le but (majorées en démocratie) ; tension mondiale. La cible bénéficie d'un ralliement.
## Appel aux armes (pays de l'IA) : score = base + relations avec l'allié appelant + hostilité envers l'ennemi
## + alliance ou garantie + rapport de forces des camps ; accepté si positif.
## Paix blanche (pays de l'IA qui la reçoit) : score = base + rapport de forces + durée de la guerre
## + lassitude (soutien à la guerre sous le seuil) + écart d'occupation (part de sa population tenue par l'ennemi moins celle qu'il tient chez l'ennemi).

const EVENT_DECLARED := &"war_declared"
const EVENT_JOINED := &"war_joined"
const EVENT_CALL := &"call_to_arms"
const EVENT_CALL_REFUSED := &"call_to_arms_refused"
const EVENT_ENDED := &"war_ended"
const EVENT_PEACE_REFUSED := &"white_peace_refused"
const EVENT_REBELS_WON := &"rebels_won"
const EVENT_PEACE_OFFER := &"white_peace_offered"
const TRUCE := "truce"
const WHITE_PEACE := "white_peace"
## Délai (mémoire) après une guerre entre États : clé de délai d'un pays envers lui-même.
const RECENT_WAR := "recent_war"
const REQUIRES_CLAIM := "claim"
const REQUIRES_OCCUPIED := "occupied"
const PERCENT := 100.0
const MAX_POWER_LOG := 1.5
const MIN_POWER := 1.0


static func settings_of(state: SimState) -> Dictionary:
	return state.military_settings.get("war", {})


## Guerres et factions rebelles de 2026 (après le contrôle des provinces, avant les groupes d'armées).
static func setup_start(state: SimState) -> void:
	state.wars.clear()
	state.rebels.clear()
	state.calls_to_arms.clear()
	state.peace_offers.clear()
	state.next_war_id = 1
	var start := state.diplomacy_start
	for entry: Variant in (start.get("wars", {}) as Dictionary).get("list", []):
		var values: Array = entry
		var attacker := str(values[0])
		var defender := str(values[1])
		var goal := str(values[2])
		if not state.countries.has(attacker) or not state.countries.has(defender) \
				or not state.war_goal_definitions.has(goal):
			continue
		var war := _create(state, [attacker], [defender], goal, goal_provinces(state, attacker, defender, goal))
		war.start_date = str(values[3])
		war.days = maxi(state.date.to_day_number() - _day_number(war.start_date), 0)
		for province_id: Variant in (values[4] if values.size() > 4 else []):
			var key := str(int(province_id))
			war.prewar[key] = ControlSystem.controller(state, key)
	for entry: Variant in (start.get("rebels", {}) as Dictionary).get("list", []):
		var values: Array = entry
		var tag := str(values[0])
		if not state.countries.has(tag):
			continue
		var faction := _add_faction(state, tag, str(values[1]))
		faction.strength_share = float(values[4]) if values.size() > 4 else float((settings_of(state).get("civil_war", {})
			as Dictionary).get("rebel_strength", 0.0))
		for hold: Variant in values[2]:
			var pair: Array = hold
			_rebel_hold(state, faction.id, str(int(pair[0])), float(pair[1]))
		var war := _create(state, [faction.id], [tag], "", [])
		war.civil = true
		war.seat = country_seat(state, tag)
		if values.size() > 3:
			war.start_date = str(values[3])
			war.days = maxi(state.date.to_day_number() - _day_number(war.start_date), 0)


## Forces des factions rebelles, une fois les armées des pays en place.
static func setup_forces(state: SimState) -> void:
	for faction: RebelFaction in state.rebels.values():
		_arm_faction(state, faction)


static func _arm_faction(state: SimState, faction: RebelFaction) -> void:
	var rules: Dictionary = settings_of(state).get("civil_war", {})
	faction.start_personnel = FrontSystem.land_personnel(state, faction.country) * faction.strength_share
	faction.personnel = faction.start_personnel
	faction.level = float(rules.get("rebel_level", 1.0))
	faction.training = float(rules.get("rebel_training", 0.0))
	faction.morale = float(rules.get("rebel_morale", 0.0))


## Province la plus peuplée d'un pays (qu'il la contrôle ou non).
static func country_seat(state: SimState, tag: String) -> String:
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var best := ""
	for province_id: String in state.province_control.keys():
		if ControlSystem.owner(state, province_id) != tag:
			continue
		if best.is_empty() or int((provinces.get(province_id, {}) as Dictionary).get("population", 0)) 				> int((provinces.get(best, {}) as Dictionary).get("population", 0)):
			best = province_id
	return best


static func _day_number(iso: String) -> int:
	var parts := iso.split("-")
	return GameDate.new(int(parts[0]), int(parts[1]), int(parts[2])).to_day_number() if parts.size() == 3 else 0


static func _create(state: SimState, attackers: Array, defenders: Array, goal: String, provinces: Array[String]) -> War:
	var war := War.new()
	war.id = state.next_war_id
	state.next_war_id += 1
	for tag: Variant in attackers:
		war.attackers.append(str(tag))
	for tag: Variant in defenders:
		war.defenders.append(str(tag))
	war.goal = goal
	war.goal_provinces = provinces
	war.start_date = "%04d-%02d-%02d" % [state.date.year, state.date.month, state.date.day]
	state.wars[war.id] = war
	state.fronts_dirty = true
	for tag: String in war.attackers + war.defenders:
		WarEnd.init_support(state, war, tag)
	return war


# --- Requêtes ---------------------------------------------------------------------------------------------

## Deux pays (ou un pays et une faction) dans des camps opposés d'une même guerre.
static func at_war(state: SimState, a: String, b: String) -> bool:
	return war_between(state, a, b) != null


static func war_between(state: SimState, a: String, b: String) -> War:
	for war: War in state.wars.values():
		var side := war.side_of(a)
		if not side.is_empty() and war.members(War.other_side(side)).has(b):
			return war
	return null


## Guerres d'un pays, dans l'ordre de leur création.
static func wars_of(state: SimState, tag: String) -> Array[War]:
	var result: Array[War] = []
	var ids: Array = state.wars.keys()
	ids.sort()
	for war_id: Variant in ids:
		var war: War = state.wars[war_id]
		if war.involves(tag):
			result.append(war)
	return result


static func is_rebel(state: SimState, tag: String) -> bool:
	return state.rebels.has(tag)


## Pays (ou faction) à l'origine d'un identifiant de contrôleur : le pays d'une faction rebelle, sinon lui-même.
static func country_of(state: SimState, tag: String) -> String:
	var faction: RebelFaction = state.rebels.get(tag)
	return faction.country if faction != null else tag


## Provinces visées par un but de guerre.
static func goal_provinces(state: SimState, attacker: String, target: String, goal: String) -> Array[String]:
	var result: Array[String] = []
	var definition: Dictionary = state.war_goal_definitions.get(goal, {})
	match str(definition.get("requires", "")):
		REQUIRES_CLAIM:
			for claim: Dictionary in state.diplomacy.claims.values():
				if claim["claimant"] == attacker and claim["target"] == target and bool(claim.get("active", true)):
					for province_id: Variant in TensionSystem.claimed_provinces(state, claim):
						if not result.has(str(province_id)):
							result.append(str(province_id))
		REQUIRES_OCCUPIED:
			for province_id: String in state.province_control.keys():
				if ControlSystem.owner(state, province_id) == attacker \
						and ControlSystem.share_held(state, province_id, target) > 0.0:
					result.append(province_id)
	result.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return result


## Raison du refus d'une déclaration (clé de localisation), vide si elle est possible.
static func declare_refusal(state: SimState, attacker: String, target: String, goal: String) -> String:
	if state.get_country(attacker) == null or state.get_country(target) == null or attacker == target \
			or settings_of(state).is_empty():
		return "WAR_INVALID"
	if at_war(state, attacker, target):
		return "WAR_ALREADY"
	if state.diplomacy.cooldown(TRUCE, attacker, target) > 0:
		return "WAR_TRUCE"
	if ControlSystem.allied(state, attacker, target):
		return "WAR_ALLIED"
	if OccupationSystem.overlord_of(state, attacker) == target or OccupationSystem.overlord_of(state, target) == attacker:
		return "WAR_PUPPET"
	return goal_refusal(state, attacker, target, goal)


## Justification du but de guerre : revendication, territoire occupé, tension et relations suffisantes.
static func goal_refusal(state: SimState, attacker: String, target: String, goal: String) -> String:
	var definition: Dictionary = state.war_goal_definitions.get(goal, {})
	if definition.is_empty():
		return "WAR_INVALID"
	# Conditions peu coûteuses d'abord (l'IA les teste pour beaucoup de pays).
	if state.diplomacy.world_tension < float(definition.get("min_tension", 0.0)):
		return "TENSION_TOO_LOW"
	if state.diplomacy.relation(attacker, target) > float(definition.get("max_relation", DiplomacyState.LIMIT)):
		return "WAR_RELATION_TOO_HIGH"
	match str(definition.get("requires", "")):
		REQUIRES_CLAIM:
			if goal_provinces(state, attacker, target, goal).is_empty():
				return "WAR_CLAIM_FROZEN" if _has_claim(state, attacker, target) else "WAR_NO_CLAIM"
		REQUIRES_OCCUPIED:
			if goal_provinces(state, attacker, target, goal).is_empty():
				return "WAR_NOT_OCCUPIED"
	return ""


static func _has_claim(state: SimState, claimant: String, target: String) -> bool:
	for claim: Dictionary in state.diplomacy.claims.values():
		if claim["claimant"] == claimant and claim["target"] == target:
			return true
	return false


## Coûts d'une déclaration pour le déclarant : {legitimacy, stability, world_opinion} (aperçu et application).
static func declaration_costs(state: SimState, attacker: String, goal: String) -> Dictionary:
	var definition: Dictionary = state.war_goal_definitions.get(goal, {})
	var country := state.get_country(attacker)
	var factor := float(settings_of(state).get("democratic_factor", 1.0)) \
		if country != null and country.politics.democratic else 1.0
	return {"legitimacy": float(definition.get("legitimacy", 0.0)) * factor,
		"stability": float(definition.get("stability", 0.0)) * factor,
		"world_opinion": float(definition.get("world_opinion", 0.0))}


## Pays appelés à défendre la cible : alliés militaires, garants de son indépendance et pays dont les troupes y
## sont stationnées (bases), sauf ceux qui sont aussi alliés de l'attaquant.
static func defenders_called(state: SimState, attacker: String, target: String) -> Array[String]:
	# Candidats : partenaires de défense mutuelle, membres des mêmes alliances militaires, garants.
	var candidates: Dictionary = {}
	for treaty_id: int in state.diplomacy.treaties_of(target):
		var treaty: Dictionary = state.diplomacy.treaties[treaty_id]
		if str(treaty["type"]) == "mutual_defense":
			candidates[str(treaty["b"]) if treaty["a"] == target else str(treaty["a"])] = true
	for organization: Dictionary in state.diplomacy.organizations.values():
		if str(organization.get("kind", "")) == "military_alliance" and (organization.get("members", []) as Array).has(target):
			for member: Variant in organization.get("members", []):
				candidates[str(member)] = true
	for table: Dictionary in [state.diplomacy.guarantees, state.diplomacy.bases]:
		for key: Variant in table.keys():
			var parts := str(key).split(">")
			if parts.size() == 2 and parts[1] == target:
				candidates[parts[0]] = true
	var result: Array[String] = []
	for tag: Variant in candidates.keys():
		if tag != attacker and tag != target and state.countries.has(tag) and not ControlSystem.allied(state, str(tag), attacker):
			result.append(str(tag))
	result.sort()
	return result


# --- Déclaration et entrée en guerre ---------------------------------------------------------------------

static func declare(state: SimState, attacker: String, target: String, goal: String) -> War:
	var settings := settings_of(state)
	var diplomacy := state.diplomacy
	var definition: Dictionary = state.war_goal_definitions.get(goal, {})
	var called := defenders_called(state, attacker, target)
	_break_treaties(state, attacker, target)
	var war := _create(state, [attacker], [target], goal, goal_provinces(state, attacker, target, goal))
	_snapshot(state, war, attacker)
	diplomacy.change_relation(attacker, target, float(settings.get("relation", 0.0)))
	diplomacy.change_trust(attacker, target, float(settings.get("trust", 0.0)))
	diplomacy.change_opinion(target, attacker, float(settings.get("target_opinion", 0.0)))
	var costs := declaration_costs(state, attacker, goal)
	_world_opinion(state, attacker, [attacker, target], float(costs["world_opinion"]))
	var society := state.get_country(attacker).society
	society.start_legitimacy -= float(costs["legitimacy"])
	society.start_stability -= float(costs["stability"])
	state.get_country(target).society.start_stability += float(settings.get("rally_stability", 0.0))
	_embargo(state, war, attacker, target)
	TensionSystem.add(state, float(definition.get("tension", 0.0)))
	state.add_event(EVENT_DECLARED, attacker, {"target": target, "war": war.id, "goal": goal})
	for ally: String in called:
		diplomacy.change_relation(ally, attacker, float(settings.get("ally_relation", 0.0)))
		call_to_arms(state, war, ally, War.DEFENDERS)
	return war


## Appel aux armes : le joueur répond plus tard (délai en jours), un pays de l'IA répond tout de suite.
static func call_to_arms(state: SimState, war: War, ally: String, side: String) -> void:
	if war.involves(ally):
		return
	if ally == str(state.player_tag):
		state.calls_to_arms.append({"war": war.id, "ally": ally, "side": side,
			"days_left": int((settings_of(state).get("call_to_arms", {}) as Dictionary).get("days", 1))})
		state.add_event(EVENT_CALL, ally, {"war": war.id, "caller": war.members(side)[0]})
	elif call_score(state, war, ally, side) > 0.0:
		join(state, war, ally, side, true)
	else:
		refuse_call(state, war, ally, side)


## Intérêt d'un pays de l'IA à répondre à l'appel (positif : il entre en guerre).
static func call_score(state: SimState, war: War, ally: String, side: String) -> float:
	var rules: Dictionary = settings_of(state).get("call_to_arms", {})
	var caller := war.members(side)[0]
	var enemy := war.members(War.other_side(side))[0]
	var diplomacy := state.diplomacy
	var score := float(rules.get("base", 0.0)) + float(rules.get("relation", 0.0)) * diplomacy.relation(ally, caller) \
		+ float(rules.get("enemy_relation", 0.0)) * diplomacy.relation(ally, enemy)
	if ControlSystem.allied(state, ally, caller):
		score += float(rules.get("alliance", 0.0))
	if diplomacy.guarantees_independence(ally, caller):
		score += float(rules.get("guarantee", 0.0))
	var ours := side_power(state, war, side) + MilitarySystem.power(state, ally)
	score += float(rules.get("power", 0.0)) * clampf(log(ours / side_power(state, war, War.other_side(side))) / log(10.0),
		-MAX_POWER_LOG, MAX_POWER_LOG)
	return score


## Refus d'un appel : l'appelant le prend mal.
static func refuse_call(state: SimState, war: War, ally: String, side: String) -> void:
	var rules: Dictionary = settings_of(state).get("call_to_arms", {})
	var caller := war.members(side)[0]
	state.diplomacy.change_relation(ally, caller, float(rules.get("refuse_relation", 0.0)))
	state.diplomacy.change_trust(ally, caller, float(rules.get("refuse_trust", 0.0)))
	state.add_event(EVENT_CALL_REFUSED, ally, {"war": war.id, "caller": caller})


## Réponse du joueur à un appel en attente.
static func answer_call(state: SimState, war_id: int, ally: String, accept: bool) -> void:
	for index: int in state.calls_to_arms.size():
		var call: Dictionary = state.calls_to_arms[index]
		if int(call["war"]) != war_id or str(call["ally"]) != ally:
			continue
		state.calls_to_arms.remove_at(index)
		var war: War = state.wars.get(war_id)
		if war == null:
			return
		if accept:
			join(state, war, ally, str(call["side"]), true)
		else:
			refuse_call(state, war, ally, str(call["side"]))
		return


## Retire les appels d'une guerre (d'un seul pays si ally n'est pas vide).
static func _drop_calls(state: SimState, war_id: int, ally: String = "") -> void:
	var kept: Array[Dictionary] = []
	for call: Dictionary in state.calls_to_arms:
		if int(call["war"]) != war_id or (not ally.is_empty() and str(call["ally"]) != ally):
			kept.append(call)
	state.calls_to_arms = kept


static func pending_call(state: SimState, war_id: int, ally: String) -> Dictionary:
	for call: Dictionary in state.calls_to_arms:
		if int(call["war"]) == war_id and str(call["ally"]) == ally:
			return call
	return {}


## Raison du refus d'une entrée en guerre volontaire aux côtés d'un camp.
static func join_refusal(state: SimState, tag: String, war_id: int, side: String) -> String:
	var war: War = state.wars.get(war_id)
	if war == null or war.civil or state.get_country(tag) == null or (side != War.ATTACKERS and side != War.DEFENDERS):
		return "WAR_INVALID"
	if war.involves(tag):
		return "WAR_ALREADY"
	var leader := war.members(side)[0]
	for enemy: String in war.members(War.other_side(side)):
		if ControlSystem.allied(state, tag, enemy):
			return "WAR_ALLIED"
		if state.diplomacy.cooldown(TRUCE, tag, enemy) > 0:
			return "WAR_TRUCE"
	var rules: Dictionary = settings_of(state).get("join", {})
	if not ControlSystem.allied(state, tag, leader) \
			and state.diplomacy.relation(tag, leader) < float(rules.get("min_relation", 0.0)):
		return "WAR_RELATION_TOO_LOW"
	return ""


## Entrée en guerre d'un pays dans un camp ; appelé : en réponse à un appel aux armes (mieux vu).
static func join(state: SimState, war: War, tag: String, side: String, called: bool) -> void:
	var settings := settings_of(state)
	var rules: Dictionary = settings.get("join", {})
	var leader := war.members(side)[0]
	var enemies := war.members(War.other_side(side)).duplicate()
	war.members(side).append(tag)
	WarEnd.init_support(state, war, tag)
	state.fronts_dirty = true
	_drop_calls(state, war.id, tag)
	_snapshot(state, war, tag)
	for enemy: String in enemies:
		if is_rebel(state, enemy):
			continue
		_break_treaties(state, tag, enemy)
		state.diplomacy.change_relation(tag, enemy, float(rules.get("enemy_relation", 0.0)))
		state.diplomacy.change_trust(tag, enemy, float(rules.get("enemy_trust", 0.0)))
		_embargo(state, war, tag, enemy)
	if called:
		state.diplomacy.change_relation(tag, leader, float((settings.get("call_to_arms", {}) as Dictionary).get(
			"join_relation", 0.0)))
	else:
		_world_opinion(state, tag, [tag] + enemies, float(rules.get("world_opinion", 0.0)))
	TensionSystem.add(state, float(rules.get("tension", 0.0)))
	state.add_event(EVENT_JOINED, tag, {"war": war.id, "side": side, "leader": leader})


static func _break_treaties(state: SimState, by: String, other: String) -> void:
	for treaty_id: int in state.diplomacy.treaties_between(by, other):
		DiplomacySystem.cancel_treaty(state, by, treaty_id)
	state.diplomacy.guarantees.erase(DiplomacyState.opinion_key(by, other))
	state.diplomacy.guarantees.erase(DiplomacyState.opinion_key(other, by))


static func _world_opinion(state: SimState, about: String, excluded: Array, amount: float) -> void:
	if is_zero_approx(amount):
		return
	for tag: String in state.countries.keys():
		if not excluded.has(tag):
			state.diplomacy.change_opinion(tag, about, amount)


## Le commerce s'arrête entre belligérants (embargo total dans les deux sens, levé à la paix s'il est neuf).
static func _embargo(state: SimState, war: War, a: String, b: String) -> void:
	if not bool(settings_of(state).get("embargo", false)):
		return
	for pair: Array in [[a, b], [b, a]]:
		var source := str(pair[0])
		var target := str(pair[1])
		if state.trade.is_embargoed(source, target):
			continue
		var table: Dictionary = state.trade.embargoes.get(source, {})
		table[target] = [TradeState.ALL_GOODS]
		state.trade.embargoes[source] = table
		war.embargoes.append(source + ">" + target)
	state.trade.dirty = true


## Provinces d'un participant déjà tenues par le camp adverse (ou qu'il tient chez lui) à son entrée en guerre.
static func _snapshot(state: SimState, war: War, tag: String) -> void:
	for province_id: String in state.province_control.keys():
		var controller := ControlSystem.controller(state, province_id)
		var owner := ControlSystem.owner(state, province_id)
		if controller != owner and (owner == tag or controller == tag) and not war.prewar.has(province_id):
			war.prewar[province_id] = controller


# --- Paix ------------------------------------------------------------------------------------------------

## Raison du refus d'une proposition de paix blanche par le meneur d'un camp.
static func white_peace_refusal(state: SimState, tag: String, war_id: int) -> String:
	var war: War = state.wars.get(war_id)
	if war == null or war.civil:
		return "WAR_INVALID"
	if tag != war.attacker_leader() and tag != war.defender_leader():
		return "WAR_NOT_LEADER"
	var other := war.defender_leader() if tag == war.attacker_leader() else war.attacker_leader()
	if state.diplomacy.cooldown(WHITE_PEACE, tag, other) > 0:
		return "DIPLOMACY_COOLDOWN"
	return ""


## Intérêt du meneur adverse (IA) pour une paix blanche proposée par tag (positif : il accepte).
static func white_peace_score(state: SimState, war: War, tag: String) -> float:
	var rules: Dictionary = settings_of(state).get("white_peace", {})
	var side := war.side_of(tag)
	var other := War.other_side(side)
	var ratio := side_power(state, war, side) / side_power(state, war, other)
	return float(rules.get("base", 0.0)) \
		+ float(rules.get("power", 0.0)) * clampf(log(ratio) / log(10.0), -MAX_POWER_LOG, MAX_POWER_LOG) \
		+ minf(float(rules.get("per_month", 0.0)) * war.months(), float(rules.get("max_months_bonus", 0.0))) \
		+ float(rules.get("occupation", 0.0)) * (occupied_percent(state, war, other) - occupied_percent(state, war, side)) 		+ maxf(float((WarEnd.settings_of(state).get("demands", {}) as Dictionary).get("allowance_support", 0.0))
			- WarEnd.support(war, war.members(other)[0]), 0.0)


## Proposition de paix blanche : acceptée, la guerre s'arrête ; refusée, délai avant une nouvelle proposition.
static func propose_white_peace(state: SimState, war: War, tag: String) -> bool:
	var other := war.defender_leader() if tag == war.attacker_leader() else war.attacker_leader()
	var accepted := other != str(state.player_tag) and white_peace_score(state, war, tag) > 0.0
	if accepted:
		end_war(state, war)
	else:
		state.diplomacy.set_cooldown(WHITE_PEACE, tag, other, int((settings_of(state).get("white_peace", {})
			as Dictionary).get("refused_cooldown", 0)))
		state.add_event(EVENT_PEACE_REFUSED, tag, {"war": war.id, "target": other})
	return accepted


## Paix blanche proposée par un pays de l'IA : au joueur, une proposition en attente (délai en jours) ; à un
## autre pays de l'IA, une réponse immédiate.
static func offer_peace(state: SimState, war: War, tag: String) -> void:
	var other := war.defender_leader() if tag == war.attacker_leader() else war.attacker_leader()
	if other != str(state.player_tag):
		propose_white_peace(state, war, tag)
		return
	WarEnd.offer(state, war, tag, WarEnd.WHITE, [])


## Réponse du joueur à une proposition de paix blanche ; un refus impose un délai avant la suivante.
static func answer_peace(state: SimState, war_id: int, accept: bool) -> void:
	for index: int in state.peace_offers.size():
		var offer: Dictionary = state.peace_offers[index]
		if int(offer["war"]) != war_id:
			continue
		state.peace_offers.remove_at(index)
		var war: War = state.wars.get(war_id)
		if war == null:
			return
		if accept:
			WarEnd.accept_offer(state, war, offer)
		else:
			state.diplomacy.set_cooldown(WHITE_PEACE, str(offer["from"]), str(state.player_tag), int((settings_of(state)
				.get("white_peace", {}) as Dictionary).get("refused_cooldown", 0)))
			state.add_event(EVENT_PEACE_REFUSED, str(state.player_tag), {"war": war_id, "target": offer["from"]})
		return


static func peace_offer(state: SimState, war_id: int) -> Dictionary:
	for offer: Dictionary in state.peace_offers:
		if int(offer["war"]) == war_id:
			return offer
	return {}


## Fin d'une guerre : chaque province non cédée revient à son contrôleur d'avant-guerre, trêve entre les deux
## camps, embargos de guerre levés (negotiated : après un traité, sinon paix blanche).
static func end_war(state: SimState, war: War, negotiated: bool = false) -> void:
	var rules: Dictionary = settings_of(state).get("white_peace", {})
	for province_id: String in state.province_control.keys():
		var owner := ControlSystem.owner(state, province_id)
		var controller := ControlSystem.controller(state, province_id)
		if war.prewar.has(province_id):
			if controller != str(war.prewar[province_id]) or state.contested.has(province_id):
				ControlSystem.set_controller(state, province_id, str(war.prewar[province_id]))
			continue
		var contest: Dictionary = state.contested.get(province_id, {})
		var hostile_control := controller != owner and _opposed(war, owner, controller)
		var hostile_contest := not contest.is_empty() and _opposed(war, controller, str(contest["by"]))
		if hostile_control or hostile_contest:
			ControlSystem.set_controller(state, province_id, owner)
	for key: String in war.embargoes:
		var pair := key.split(">")
		var table: Dictionary = state.trade.embargoes.get(pair[0], {})
		table.erase(pair[1])
		if table.is_empty():
			state.trade.embargoes.erase(pair[0])
	state.trade.dirty = true
	if not war.civil:
		for tag: String in war.attackers + war.defenders:
			state.diplomacy.set_cooldown(RECENT_WAR, tag, tag, int(rules.get("recent_war_months", 0)))
	for a: String in war.attackers:
		for b: String in war.defenders:
			if is_rebel(state, a) or is_rebel(state, b):
				continue
			state.diplomacy.set_cooldown(TRUCE, a, b, int(rules.get("truce_months", 0)))
			state.diplomacy.change_relation(a, b, float(rules.get("relation", 0.0)))
	state.wars.erase(war.id)
	state.fronts_dirty = true
	_drop_calls(state, war.id)
	var offers: Array[Dictionary] = []
	for offer: Dictionary in state.peace_offers:
		if int(offer["war"]) != war.id:
			offers.append(offer)
	state.peace_offers = offers
	for tag: String in war.attackers + war.defenders:
		if is_rebel(state, tag):
			state.rebels.erase(tag)
	if war.civil:
		var country := state.get_country(war.defender_leader())
		if country != null:
			CrisisSystem.end_civil_war_crisis(country, state)
	else:
		TensionSystem.add(state, float(rules.get("tension", 0.0)))
	state.add_event(EVENT_ENDED, war.attacker_leader(), {"war": war.id, "target": war.defender_leader(),
		"civil": war.civil, "negotiated": negotiated})


static func _opposed(war: War, a: String, b: String) -> bool:
	var side_a := war.side_of(a)
	var side_b := war.side_of(b)
	return not side_a.is_empty() and not side_b.is_empty() and side_a != side_b


## Puissance militaire d'un camp (une faction rebelle n'en a pas encore : étape 7c2).
static func side_power(state: SimState, war: War, side: String) -> float:
	var total := 0.0
	for tag: String in war.members(side):
		total += MilitarySystem.power(state, tag)
	return maxf(total, MIN_POWER)


## Part de la population des pays d'un camp vivant dans des provinces tenues par l'autre camp (en %).
static func occupied_percent(state: SimState, war: War, side: String) -> float:
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var members := war.members(side)
	var enemies := war.members(War.other_side(side))
	var total := 0.0
	var held := 0.0
	var owned: Array = []
	for member: String in members:
		owned.append_array(state.provinces_by_owner.get(member, []))
	for province_id: String in owned:
		var population := float((provinces.get(province_id, {}) as Dictionary).get("population", 0.0))
		total += population
		for enemy: String in enemies:
			held += population * ControlSystem.share_held(state, province_id, enemy)
	return held / total * PERCENT if total > 0.0 else 0.0


# --- Guerres civiles ---------------------------------------------------------------------------------------

static func _add_faction(state: SimState, tag: String, faction_id: String = "") -> RebelFaction:
	var faction := RebelFaction.new()
	faction.id = faction_id if not faction_id.is_empty() else RebelFaction.id_for(tag)
	faction.country = tag
	state.rebels[faction.id] = faction
	return faction


static func _rebel_hold(state: SimState, faction_id: String, province_id: String, share: float) -> void:
	if not state.province_control.has(province_id):
		return
	if share >= ControlSystem.FULL:
		state.province_control[province_id] = faction_id
		state.contested.erase(province_id)
	elif share > 0.0:
		state.contested[province_id] = {"by": faction_id, "share": share}


## Une guerre civile éclate en cours de partie : les rebelles tiennent une part des provinces les plus
## éloignées de la province la plus peuplée du pays.
static func start_civil_war(state: SimState, tag: String) -> void:
	if civil_war_of(state, tag) != null or settings_of(state).is_empty():
		return
	var rules: Dictionary = settings_of(state).get("civil_war", {})
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var own: Array[String] = []
	var seat := ""
	for province_id: String in state.province_control.keys():
		if ControlSystem.owner(state, province_id) == tag and ControlSystem.controller(state, province_id) == tag:
			own.append(province_id)
			if seat.is_empty() or int((provinces.get(province_id, {}) as Dictionary).get("population", 0)) \
					> int((provinces.get(seat, {}) as Dictionary).get("population", 0)):
				seat = province_id
	if own.is_empty():
		return
	var distances: Dictionary = {}
	for province_id: String in own:
		distances[province_id] = ArmyGroupModel.distance_km(state, seat, province_id)
	own.sort_custom(func(a: String, b: String) -> bool:
		if not is_equal_approx(float(distances[a]), float(distances[b])):
			return float(distances[a]) > float(distances[b])
		return int(a) < int(b))
	var faction := _add_faction(state, tag)
	faction.strength_share = float(rules.get("rebel_strength", 0.0))
	_arm_faction(state, faction)
	var count := clampi(ceili(own.size() * float(rules.get("province_share", 0.0))), 1, own.size())
	for index: int in count:
		_rebel_hold(state, faction.id, own[index], float(rules.get("start_share", 0.0)))
	var war := _create(state, [faction.id], [tag], "", [])
	war.civil = true
	war.seat = country_seat(state, tag)
	state.add_event(EVENT_DECLARED, faction.id, {"target": tag, "war": war.id, "civil": true})


## Issue des guerres civiles : le gouvernement gagne quand les rebelles n'ont plus de province ou presque plus de
## forces ; les rebelles gagnent en prenant la province la plus peuplée du pays (une junte prend le pouvoir).
static func check_civil_wars(state: SimState) -> void:
	var rules: Dictionary = settings_of(state).get("civil_war", {})
	var ids: Array = state.wars.keys()
	ids.sort()
	for war_id: Variant in ids:
		var war: War = state.wars[war_id]
		if not war.civil:
			continue
		var faction: RebelFaction = state.rebels.get(war.attacker_leader())
		if faction == null:
			continue
		if not war.seat.is_empty() and ControlSystem.controller(state, war.seat) == faction.id:
			var country := state.get_country(faction.country)
			end_war(state, war)
			if country != null:
				CrisisSystem.install_junta(country, state)
			state.add_event(EVENT_REBELS_WON, faction.country, {"war": war.id})
			continue
		var weak := faction.personnel < faction.start_personnel * float(rules.get("rebel_defeated_share", 0.0))
		FrontSystem.refresh(state)
		if weak or not state.front_holdings.has(faction.id):
			end_war(state, war)


## Chaque mois, les rebelles remplacent une part de leurs pertes (recrutement) et leur moral revient vers son
## niveau habituel, comme celui des armées.
static func update_month(state: SimState) -> void:
	var replacement := float(FrontSystem.combat_settings(state).get("replacement", 0.0))
	var morale := float((settings_of(state).get("civil_war", {}) as Dictionary).get("rebel_morale", 0.0))
	var adjustment := float((state.military_settings.get("morale", {}) as Dictionary).get("adjustment", 0.0))
	for faction: RebelFaction in state.rebels.values():
		faction.personnel += (faction.start_personnel - faction.personnel) * replacement
		faction.morale += (morale - faction.morale) * adjustment


## Fin d'une guerre civile (crise terminée) : le pays reprend ses provinces.
static func end_civil_war(state: SimState, tag: String) -> void:
	var war := civil_war_of(state, tag)
	if war != null:
		end_war(state, war)


static func civil_war_of(state: SimState, tag: String) -> War:
	for war: War in state.wars.values():
		if war.civil and war.defender_leader() == tag:
			return war
	return null


# --- Chaque jour -------------------------------------------------------------------------------------------

## Durée des guerres, délai des appels aux armes et des propositions de paix du joueur (sans réponse : refus).
static func update_day(state: SimState) -> void:
	for war: War in state.wars.values():
		war.days += 1
	var expired: Array[Dictionary] = []
	for call: Dictionary in state.calls_to_arms:
		call["days_left"] = int(call["days_left"]) - 1
		if int(call["days_left"]) <= 0:
			expired.append(call)
	for call: Dictionary in expired:
		answer_call(state, int(call["war"]), str(call["ally"]), false)
	var unanswered: Array[int] = []
	for offer: Dictionary in state.peace_offers:
		offer["days_left"] = int(offer["days_left"]) - 1
		if int(offer["days_left"]) <= 0:
			unanswered.append(int(offer["war"]))
	for war_id: int in unanswered:
		answer_peace(state, war_id, false)

class_name WarEnd
extends RefCounted
## Fin des guerres : soutien à la guerre de chaque belligérant, score de guerre, cessez-le-feu, paix négociée
## (provinces cédées, réparations) et paiement des réparations.
##
## Soutien (0 à 100) : départ selon le camp (l'attaquant moins s'il y a peu de justification), puis chaque mois
## - usure (plus forte en démocratie) - pertes du mois en % de la population × poids - blocus - récession
## + ralliement si notre territoire est occupé (plafonné). Sous un seuil : stabilité et, en démocratie, légitimité
## en baisse.
## Score (vue de l'attaquant, -100 à 100) = écart d'occupation (points de population) × poids + écart de pertes
## (part) × poids + écart de blocus × poids + part des buts atteints × poids.
## Exigences : province visée par les buts et tenue par notre camp (coût = sa part de la population du camp
## adverse × poids, avec un minimum), réparations (coût fixe). Marge acceptée par un pays de l'IA = score du
## demandeur × (1 - soutien / 100) + ce qui manque à son soutien pour atteindre le seuil.

const PROVINCE := "province"
const REPARATIONS := "reparations"
const WHITE := "white"
const CEASEFIRE := "ceasefire"
const PEACE := "peace"
const EVENT_CEASEFIRE := &"ceasefire"
const EVENT_CEASEFIRE_REFUSED := &"ceasefire_refused"
const EVENT_CEASEFIRE_ENDED := &"ceasefire_ended"
const EVENT_PEACE := &"peace_signed"
const EVENT_CEDED := &"province_ceded"
const PERCENT := 100.0
const MONTHS_PER_YEAR := 12.0
const REBEL_SUPPORT := 70.0
## Part d'une province qu'un camp doit tenir pour pouvoir l'exiger.
const MAJORITY := 0.5


static func settings_of(state: SimState) -> Dictionary:
	return state.military_settings.get("war_end", {})


# --- Soutien --------------------------------------------------------------------------------------------------

## Soutien de départ d'un participant (à l'entrée en guerre).
static func init_support(state: SimState, war: War, tag: String) -> void:
	var rules: Dictionary = settings_of(state).get("support", {})
	var value := float(rules.get("joiner_start", REBEL_SUPPORT))
	if WarSystem.is_rebel(state, tag):
		value = REBEL_SUPPORT
	elif tag == war.defender_leader():
		value = float(rules.get("defender_start", value))
	elif tag == war.attacker_leader():
		var goal: Dictionary = state.war_goal_definitions.get(war.goal, {})
		value = float(rules.get("attacker_start", value)) - float(goal.get("legitimacy", 0.0)) \
			* float(rules.get("attacker_legitimacy_weight", 0.0))
	war.support[tag] = clampf(value, 0.0, PERCENT)


static func support(war: War, tag: String) -> float:
	return float(war.support.get(tag, PERCENT))


# --- Score ----------------------------------------------------------------------------------------------------

## Score de guerre vu de l'attaquant (-100 : défaite complète, 100 : victoire complète).
static func score(state: SimState, war: War) -> float:
	var rules: Dictionary = settings_of(state).get("score", {})
	var occupation := WarSystem.occupied_percent(state, war, War.DEFENDERS) \
		- WarSystem.occupied_percent(state, war, War.ATTACKERS)
	var attack_losses := _sum(war.casualties, war.attackers)
	var defense_losses := _sum(war.casualties, war.defenders)
	var losses := (defense_losses - attack_losses) / maxf(attack_losses + defense_losses, 1.0)
	var blockade := _max_blockade(state, war.defenders) - _max_blockade(state, war.attackers)
	var goals := 0.0
	if not war.goal_provinces.is_empty():
		var held := 0
		for province_id: String in war.goal_provinces:
			if war.side_of(ControlSystem.controller(state, province_id)) == War.ATTACKERS:
				held += 1
		goals = float(held) / war.goal_provinces.size()
	var limit := float(rules.get("limit", PERCENT))
	return clampf(occupation * float(rules.get("occupation_weight", 0.0)) + losses * float(rules.get("casualty_weight", 0.0))
		+ blockade * float(rules.get("blockade_weight", 0.0)) + goals * float(rules.get("goal_weight", 0.0)), -limit, limit)


## Score vu d'un participant (positif : son camp mène).
static func score_for(state: SimState, war: War, tag: String) -> float:
	return score(state, war) * (1.0 if war.side_of(tag) == War.ATTACKERS else -1.0)


static func _sum(values: Dictionary, tags: Array[String]) -> float:
	var total := 0.0
	for tag: String in tags:
		total += float(values.get(tag, 0.0))
	return total


static func _max_blockade(state: SimState, tags: Array[String]) -> float:
	var result := 0.0
	for tag: String in tags:
		result = maxf(result, float(state.trade.blockades.get(tag, 0.0)))
	return result


# --- Chaque mois ----------------------------------------------------------------------------------------------

## Soutien à la guerre, effets d'un soutien faible, fin des cessez-le-feu, versement des réparations.
static func update_month(state: SimState) -> void:
	var settings := settings_of(state)
	if settings.is_empty():
		return
	var rules: Dictionary = settings.get("support", {})
	var ids: Array = state.wars.keys()
	ids.sort()
	for war_id: Variant in ids:
		var war: War = state.wars[war_id]
		if war.civil:
			continue
		for tag: String in war.attackers + war.defenders:
			_update_support(state, war, tag, rules)
		if war.ceasefire_months > 0:
			war.ceasefire_months -= 1
			if war.ceasefire_months == 0:
				# Les combats reprennent pour un temps avant toute nouvelle trêve.
				state.diplomacy.set_cooldown(CEASEFIRE, war.attacker_leader(), war.defender_leader(),
					int((settings.get("ceasefire", {}) as Dictionary).get("resume_months", 0)))
				state.add_event(EVENT_CEASEFIRE_ENDED, war.attacker_leader(), {"war": war.id, "target": war.defender_leader()})
	var kept: Array[Dictionary] = []
	for payment: Dictionary in state.reparations:
		var payer := state.get_country(str(payment["from"]))
		var payee := state.get_country(str(payment["to"]))
		if payer != null and payee != null:
			var amount := float(payment["share"]) / PERCENT * TradeSystem.current_gdp(state, payer.tag) / MONTHS_PER_YEAR
			InvestmentSystem.add_debt_usd(payer, state, amount)
			InvestmentSystem.add_debt_usd(payee, state, -amount)
		payment["months_left"] = int(payment["months_left"]) - 1
		if int(payment["months_left"]) > 0:
			kept.append(payment)
	state.reparations = kept


static func _update_support(state: SimState, war: War, tag: String, rules: Dictionary) -> void:
	var country := state.get_country(tag)
	if country == null:
		return
	var losses := float(war.casualties.get(tag, 0.0)) - float(war.casualties_last_month.get(tag, 0.0))
	war.casualties_last_month[tag] = float(war.casualties.get(tag, 0.0))
	var population := maxf(float(country.economy.population), 1.0)
	var democratic := country.politics.democratic
	var change := -float(rules.get("monthly_decay", 0.0)) * (float(rules.get("democratic_factor", 1.0)) if democratic else 1.0)
	change -= float(rules.get("casualty_weight", 0.0)) * losses / population * PERCENT
	change -= float(rules.get("blockade_weight", 0.0)) * float(state.trade.blockades.get(tag, 0.0))
	if country.economy.growth < 0.0:
		change -= float(rules.get("recession", 0.0))
	change += minf(WarSystem.occupied_percent(state, war, war.side_of(tag)) * float(rules.get("rally_per_occupied_percent", 0.0)),
		float(rules.get("rally_max", 0.0)))
	var value := clampf(support(war, tag) + change, 0.0, PERCENT)
	war.support[tag] = value
	var low := float(rules.get("low", 0.0))
	if value < low:
		country.society.start_stability -= (low - value) * float(rules.get("stability_per_point", 0.0))
		if democratic:
			country.society.start_legitimacy -= (low - value) * float(rules.get("legitimacy_per_point", 0.0))


# --- Cessez-le-feu --------------------------------------------------------------------------------------------

static func ceasefire_refusal(state: SimState, tag: String, war_id: int) -> String:
	var war: War = state.wars.get(war_id)
	if war == null or war.civil or settings_of(state).is_empty():
		return "WAR_INVALID"
	if tag != war.attacker_leader() and tag != war.defender_leader():
		return "WAR_NOT_LEADER"
	if war.in_ceasefire():
		return "WAR_IN_CEASEFIRE"
	if state.diplomacy.cooldown(CEASEFIRE, war.attacker_leader(), war.defender_leader()) > 0:
		return "DIPLOMACY_COOLDOWN"
	return ""


## L'adversaire (IA) accepte un cessez-le-feu s'il est las de la guerre ou s'il perd.
static func ceasefire_accepted(state: SimState, war: War, receiver: String) -> bool:
	var rules: Dictionary = settings_of(state).get("ceasefire", {})
	return support(war, receiver) < float(rules.get("accept_support", 0.0)) \
		or score_for(state, war, receiver) < float(rules.get("accept_score", 0.0))


static func propose_ceasefire(state: SimState, war: War, tag: String) -> void:
	var other := _other_leader(war, tag)
	if other == str(state.player_tag):
		offer(state, war, tag, CEASEFIRE, [])
		return
	if ceasefire_accepted(state, war, other):
		start_ceasefire(state, war)
	else:
		state.diplomacy.set_cooldown(CEASEFIRE, war.attacker_leader(), war.defender_leader(),
			int((settings_of(state).get("ceasefire", {}) as Dictionary).get("cooldown", 0)))
		state.add_event(EVENT_CEASEFIRE_REFUSED, tag, {"war": war.id, "target": other})


static func start_ceasefire(state: SimState, war: War) -> void:
	war.ceasefire_months = int((settings_of(state).get("ceasefire", {}) as Dictionary).get("months", 0))
	state.add_event(EVENT_CEASEFIRE, war.attacker_leader(), {"war": war.id, "target": war.defender_leader()})


static func _other_leader(war: War, tag: String) -> String:
	return war.defender_leader() if tag == war.attacker_leader() else war.attacker_leader()


# --- Paix négociée --------------------------------------------------------------------------------------------

## Exigences possibles pour le camp de tag : provinces visées par les buts (camp attaquant) dont son camp tient
## au moins la moitié, et réparations s'il mène.
static func available_demands(state: SimState, war: War, tag: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var side := war.side_of(tag)
	if side == War.ATTACKERS:
		for province_id: String in war.goal_provinces:
			if war.side_of(ControlSystem.owner(state, province_id)) == War.other_side(side) \
					and side_share(state, war, province_id, side) >= MAJORITY:
				result.append({"type": PROVINCE, "province": province_id})
	if score_for(state, war, tag) > 0.0:
		result.append({"type": REPARATIONS})
	return result


## Part d'une province tenue par les membres d'un camp (0 à 1).
static func side_share(state: SimState, war: War, province_id: String, side: String) -> float:
	var total := 0.0
	for member: String in war.members(side):
		total += ControlSystem.share_held(state, province_id, member)
	return total


## Coût d'une exigence en points de score.
static func demand_cost(state: SimState, war: War, demand: Dictionary, receiver: String) -> float:
	var rules: Dictionary = settings_of(state).get("demands", {})
	if str(demand.get("type", "")) == REPARATIONS:
		return float(rules.get("reparations_cost", 0.0))
	var province_id := str(demand.get("province", ""))
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	var total := 0.0
	for member: String in war.members(war.side_of(receiver)):
		for owned: Variant in state.provinces_by_owner.get(member, []):
			total += float((provinces.get(str(owned), {}) as Dictionary).get("population", 0.0))
	var share := float((provinces.get(province_id, {}) as Dictionary).get("population", 0.0)) / maxf(total, 1.0) * PERCENT
	return maxf(share * float(rules.get("province_cost_per_percent", 0.0)), float(rules.get("province_min_cost", 0.0)))


static func total_cost(state: SimState, war: War, demands: Array, receiver: String) -> float:
	var total := 0.0
	for demand: Variant in demands:
		total += demand_cost(state, war, demand, receiver)
	return total


## Ce qu'un pays de l'IA accepte de céder (en points de score) : selon le score de l'adversaire et son propre
## soutien à la guerre.
static func allowance(state: SimState, war: War, receiver: String) -> float:
	var rules: Dictionary = settings_of(state).get("demands", {})
	var value := support(war, receiver)
	return maxf(-score_for(state, war, receiver), 0.0) * (1.0 - value / PERCENT) \
		+ maxf(float(rules.get("allowance_support", 0.0)) - value, 0.0)


## Exigences qui tiennent dans la marge de l'adversaire (les moins coûteuses d'abord).
static func best_demands(state: SimState, war: War, tag: String) -> Array[Dictionary]:
	var receiver := _other_leader(war, tag)
	var budget := allowance(state, war, receiver)
	var candidates := available_demands(state, war, tag)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return demand_cost(state, war, a, receiver) < demand_cost(state, war, b, receiver))
	var result: Array[Dictionary] = []
	var spent := 0.0
	for demand: Dictionary in candidates:
		var cost := demand_cost(state, war, demand, receiver)
		if spent + cost <= budget:
			result.append(demand)
			spent += cost
	return result


static func peace_refusal(state: SimState, tag: String, war_id: int, demands: Array) -> String:
	var refusal := WarSystem.white_peace_refusal(state, tag, war_id)
	if not refusal.is_empty():
		return refusal
	var war: War = state.wars[war_id]
	var available := available_demands(state, war, tag)
	for demand: Variant in demands:
		if not available.has(demand):
			return "WAR_INVALID"
	return ""


## Proposition de paix avec exigences : à un pays de l'IA, acceptée si elle tient dans sa marge.
static func propose_peace(state: SimState, war: War, tag: String, demands: Array) -> bool:
	var other := _other_leader(war, tag)
	if other == str(state.player_tag):
		offer(state, war, tag, PEACE, demands)
		return false
	if total_cost(state, war, demands, other) <= allowance(state, war, other):
		sign_peace(state, war, tag, demands)
		return true
	state.diplomacy.set_cooldown(WarSystem.WHITE_PEACE, tag, other, int((WarSystem.settings_of(state).get("white_peace", {})
		as Dictionary).get("refused_cooldown", 0)))
	state.add_event(WarSystem.EVENT_PEACE_REFUSED, tag, {"war": war.id, "target": other})
	return false


## Traité de paix : provinces cédées (au membre du camp qui les tient), réparations, puis fin de la guerre
## (le reste revient au contrôle d'avant-guerre).
static func sign_peace(state: SimState, war: War, tag: String, demands: Array) -> void:
	var rules: Dictionary = settings_of(state).get("demands", {})
	var side := war.side_of(tag)
	var loser := _other_leader(war, tag)
	for demand: Variant in demands:
		var entry: Dictionary = demand
		if str(entry.get("type", "")) == PROVINCE:
			var province_id := str(entry["province"])
			var holder := ControlSystem.controller(state, province_id)
			cede(state, province_id, holder if war.side_of(holder) == side else tag)
		elif str(entry.get("type", "")) == REPARATIONS:
			state.reparations.append({"from": loser, "to": tag, "share": float(rules.get("reparations_share", 0.0)),
				"months_left": int(rules.get("reparations_years", 0)) * int(MONTHS_PER_YEAR)})
	state.add_event(EVENT_PEACE, tag, {"war": war.id, "target": loser, "demands": demands})
	WarSystem.end_war(state, war, true)


## Cession d'une province : nouveau propriétaire et contrôleur, transfert de sa population, de son économie et
## de sa circonscription (Territory), frontières recalculées, revendications mises à jour (le cédant garde une
## revendication active), groupes du cédant repliés.
static func cede(state: SimState, province_id: String, to: String) -> void:
	var previous := ControlSystem.owner(state, province_id)
	if previous == to or previous.is_empty():
		return
	(state.provinces_by_owner.get(previous, []) as Array).erase(province_id)
	Territory.transfer(state, province_id, previous, to)
	state.province_owner[province_id] = to
	if not state.provinces_by_owner.has(to):
		state.provinces_by_owner[to] = []
	(state.provinces_by_owner[to] as Array).append(province_id)
	ControlSystem.set_controller(state, province_id, to)
	ControlSystem.refresh_borders(state)
	state.fronts_dirty = true
	state.control_version += 1
	for claim_id: Variant in state.diplomacy.claims.keys():
		var claim: Dictionary = state.diplomacy.claims[claim_id]
		if claim["claimant"] == to and claim["target"] == previous:
			(claim.get("provinces", []) as Array).erase(province_id)
			if (claim.get("provinces", []) as Array).is_empty():
				state.diplomacy.claims.erase(claim_id)
	# Une seule revendication « territoire perdu » par pays : les provinces s'y ajoutent.
	var merged := false
	for claim: Dictionary in state.diplomacy.claims.values():
		if claim["claimant"] == previous and claim["target"] == to and not (claim.get("provinces", []) as Array).is_empty():
			(claim["provinces"] as Array).append(province_id)
			claim["active"] = true
			merged = true
			break
	if not merged:
		var lost: Array[String] = [province_id]
		TensionSystem.add_claim(state, previous, to, lost, true)
	ArmyGroupModel.evacuate(state, province_id)
	state.add_event(EVENT_CEDED, to, {"province": province_id, "previous": previous})


# --- Propositions au joueur -----------------------------------------------------------------------------------

## Proposition en attente pour le joueur (paix blanche, cessez-le-feu ou paix avec exigences).
static func offer(state: SimState, war: War, tag: String, kind: String, demands: Array) -> void:
	for existing: Dictionary in state.peace_offers:
		if int(existing["war"]) == war.id:
			return
	state.peace_offers.append({"war": war.id, "from": tag, "kind": kind, "demands": demands,
		"days_left": int((state.military_settings.get("ai", {}) as Dictionary).get("peace", {}).get("player_days", 1))})
	state.add_event(WarSystem.EVENT_PEACE_OFFER, _other_leader(war, tag), {"war": war.id, "from": tag, "kind": kind})


## Le joueur accepte une proposition.
static func accept_offer(state: SimState, war: War, offer_data: Dictionary) -> void:
	match str(offer_data.get("kind", WHITE)):
		CEASEFIRE:
			start_ceasefire(state, war)
		PEACE:
			sign_peace(state, war, str(offer_data["from"]), offer_data.get("demands", []))
		_:
			WarSystem.end_war(state, war)

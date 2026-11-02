class_name CountryLifecycle
extends RefCounted
## Pays qui changent pendant la partie : absorption pacifique (union, réunification) et dissolution du pays
## absorbé, changement de nom, de couleur et de drapeau.
## Absorption : les guerres du pays absorbé s'arrêtent (ou il en sort si son camp continue sans lui), toutes
## ses provinces passent à l'absorbant avec le reste de sa population, de son économie et de sa dette, ses
## technologies et une partie de son armée ; puis toutes les références au pays sont retirées.

const EVENT_ANNEXED := &"country_annexed"
const EVENT_RENAMED := &"country_renamed"
## Part de l'armée du pays absorbé reprise par l'absorbant.
const ARMY_SHARE := 1.0


## Raison du refus d'une absorption ("" si possible). Le pays du joueur ne peut pas être absorbé.
static func annex_refusal(state: SimState, absorber: String, target: String) -> String:
	if state.get_country(absorber) == null or state.get_country(target) == null or absorber == target:
		return "ANNEX_INVALID"
	if StringName(target) == state.player_tag:
		return "ANNEX_PLAYER"
	if WarSystem.is_rebel(state, absorber) or WarSystem.is_rebel(state, target):
		return "ANNEX_INVALID"
	return ""


static func annex(state: SimState, absorber: String, target: String) -> bool:
	if not annex_refusal(state, absorber, target).is_empty():
		return false
	var taker := state.get_country(absorber)
	var giver := state.get_country(target)
	_end_wars(state, absorber, target)
	# Les provinces qu'il occupait reviennent à leur propriétaire ; celles qu'il possède passent à l'absorbant.
	for province_id: Variant in state.province_control.keys():
		if ControlSystem.controller(state, str(province_id)) == target \
				and ControlSystem.owner(state, str(province_id)) != target:
			ControlSystem.set_controller(state, str(province_id), ControlSystem.owner(state, str(province_id)))
	for province_id: Variant in state.contested.keys():
		if str((state.contested[province_id] as Dictionary).get("by", "")) == target:
			state.contested.erase(province_id)
	for province_id: Variant in (state.provinces_by_owner.get(target, []) as Array).duplicate():
		WarEnd.cede(state, str(province_id), absorber, true)
	_merge_remainder(state, taker, giver)
	_merge_trade(state, absorber, target)
	dissolve(state, target)
	state.dissolved[target] = absorber
	recompute_land_neighbors(state)
	state.add_event(EVENT_ANNEXED, absorber, {"target": target})
	return true


## Guerres du pays absorbé : arrêtées si l'absorbant est en face ou s'il menait son camp, sinon il en sort.
static func _end_wars(state: SimState, absorber: String, target: String) -> void:
	for war: War in WarSystem.wars_of(state, target):
		if not state.wars.has(war.id):
			continue
		var side := war.side_of(target)
		var members := war.members(side)
		var absorber_side := war.side_of(absorber)
		if war.civil or members.size() <= 1 or (not absorber_side.is_empty() and absorber_side != side):
			WarSystem.end_war(state, war, true)
		else:
			members.erase(target)
			war.casualties.erase(target)
			war.support.erase(target)
	# Fronts et contrôles d'avant-guerre qui citaient le pays absorbé.
	for war: War in state.wars.values():
		for province_id: Variant in war.prewar.keys():
			if str(war.prewar[province_id]) == target:
				war.prewar[province_id] = absorber
	state.fronts_dirty = true


## Ce que les cessions province par province n'ont pas emporté (elles plafonnent la part transférée) : reste
## de la population, du PIB, de la demande d'électricité et de la production des ressources ; dette ; savoir
## technologique ; soldats.
static func _merge_remainder(state: SimState, taker: CountryState, giver: CountryState) -> void:
	taker.economy.population += giver.economy.population
	giver.economy.population = 0
	taker.economy.real_gdp += giver.economy.real_gdp
	giver.economy.real_gdp = 0.0
	taker.energy.demand += giver.energy.demand
	for resource_id: Variant in giver.resources.production_base.keys():
		taker.resources.production_base[resource_id] = float(taker.resources.production_base.get(resource_id, 0.0)) \
			+ float(giver.resources.production_base[resource_id])
	for resource_id: Variant in giver.resources.consumption_base.keys():
		taker.resources.consumption_base[resource_id] = float(taker.resources.consumption_base.get(resource_id, 0.0)) \
			+ float(giver.resources.consumption_base[resource_id])
	var giver_currency := state.get_currency(giver.economy.currency)
	if giver_currency != null:
		InvestmentSystem.add_debt_usd(taker, state, giver.economy.total_debt(giver_currency) / giver_currency.fx_factor())
	if taker.research != null and giver.research != null:
		for tech_id: Variant in giver.research.known.keys():
			if not taker.research.is_known(str(tech_id)):
				ResearchSystem.complete(state, taker, str(tech_id))
	if taker.military != null and giver.military != null:
		taker.military.active_personnel += giver.military.active_personnel * ARMY_SHARE
		taker.military.reserve_personnel += giver.military.reserve_personnel * ARMY_SHARE
		taker.military.nuclear_warheads += giver.military.nuclear_warheads
	var influence := state.diplomacy.influence_points
	influence[taker.tag] = float(influence.get(taker.tag, 0.0)) + float(influence.get(giver.tag, 0.0))


## Commerce : les flux du pays absorbé deviennent ceux de l'absorbant (les échanges entre eux deviennent
## intérieurs), son PIB de départ s'ajoute à celui de l'absorbant pour garder les mêmes proportions.
static func _merge_trade(state: SimState, absorber: String, target: String) -> void:
	var trade := state.trade
	var own: Dictionary = trade.start_flows.get(absorber, {})
	for importer: Variant in (trade.start_flows.get(target, {}) as Dictionary).keys():
		if str(importer) != absorber:
			own[importer] = float(own.get(importer, 0.0)) + float(trade.start_flows[target][importer])
	own.erase(target)
	trade.start_flows[absorber] = own
	for exporter: Variant in trade.start_flows.keys():
		var row: Dictionary = trade.start_flows[exporter]
		if row.has(target):
			if str(exporter) != absorber and str(exporter) != target:
				row[absorber] = float(row.get(absorber, 0.0)) + float(row[target])
			row.erase(target)
	for exporter: Variant in trade.start_tariffs.keys():
		var tariffs: Dictionary = trade.start_tariffs[exporter]
		if tariffs.has(target) and not tariffs.has(absorber):
			tariffs[absorber] = tariffs[target]
	var absorber_tariffs: Dictionary = trade.start_tariffs.get(absorber, {})
	for importer: Variant in (trade.start_tariffs.get(target, {}) as Dictionary).keys():
		if not absorber_tariffs.has(importer) and str(importer) != absorber:
			absorber_tariffs[importer] = trade.start_tariffs[target][importer]
	trade.start_tariffs[absorber] = absorber_tariffs
	trade.start_gdp[absorber] = float(trade.start_gdp.get(absorber, 0.0)) + float(trade.start_gdp.get(target, 0.0))
	trade.dirty = true


## Retire un pays de la partie et toutes les références qui le citent.
static func dissolve(state: SimState, tag: String) -> void:
	var diplomacy := state.diplomacy
	for org_id: Variant in diplomacy.organizations.keys():
		if ((diplomacy.organizations[org_id] as Dictionary).get("members", []) as Array).has(tag):
			OrganizationSystem.remove_member(state, str(org_id), tag)
	diplomacy.security_council.erase(tag)
	for treaty_id: Variant in diplomacy.treaties.keys():
		var treaty: Dictionary = diplomacy.treaties[treaty_id]
		if str(treaty.get("a", "")) == tag or str(treaty.get("b", "")) == tag:
			diplomacy.treaties.erase(treaty_id)
	for table: Dictionary in [diplomacy.start_relations, diplomacy.relation_changes, diplomacy.trust_changes,
			diplomacy.opinion_changes, diplomacy.treaty_bonus, diplomacy.closed_embassies, diplomacy.recognitions,
			diplomacy.guarantees, diplomacy.sanctions, diplomacy.start_sanction_effects, diplomacy.start_influence,
			diplomacy.influence_changes, diplomacy.bases, diplomacy.start_bases, diplomacy.cooldowns,
			diplomacy.influence_points, diplomacy.arms_received]:
		purge_keys(table, tag)
	diplomacy.aid_programs = diplomacy.aid_programs.filter(func(program: Dictionary) -> bool:
		return str(program.get("donor", "")) != tag and str(program.get("recipient", "")) != tag)
	for claim_id: Variant in diplomacy.claims.keys():
		var claim: Dictionary = diplomacy.claims[claim_id]
		if str(claim.get("claimant", "")) == tag or str(claim.get("target", "")) == tag:
			diplomacy.claims.erase(claim_id)
	var trade := state.trade
	for table: Dictionary in [trade.start_flows, trade.start_tariffs, trade.tariff_changes, trade.base_tariffs,
			trade.surcharges, trade.embargoes, trade.blockades, trade.land_neighbors, trade.start_gdp]:
		purge_nested(table, tag)
	for agreement_id: Variant in trade.agreements.keys():
		((trade.agreements[agreement_id] as Dictionary).get("members", []) as Array).erase(tag)
	trade.dirty = true
	for puppet: Variant in state.puppets.keys():
		if str(puppet) == tag or str(state.puppets[puppet]) == tag:
			state.puppets.erase(puppet)
	state.reparations = state.reparations.filter(func(entry: Dictionary) -> bool:
		return str(entry.get("from", "")) != tag and str(entry.get("to", "")) != tag)
	state.peace_offers = state.peace_offers.filter(func(entry: Dictionary) -> bool:
		return str(entry.get("from", "")) != tag)
	for group_id: Variant in state.army_groups.keys():
		if (state.army_groups[group_id] as ArmyGroup).owner == tag:
			state.army_groups.erase(group_id)
	for fleet_id: Variant in state.fleets.keys():
		if (state.fleets[fleet_id] as Fleet).owner == tag:
			state.fleets.erase(fleet_id)
	for project: Dictionary in state.joint_projects:
		(project.get("members", []) as Array).erase(tag)
	state.joint_projects = state.joint_projects.filter(func(project: Dictionary) -> bool:
		return (project.get("members", []) as Array).size() >= 2)
	state.projects = state.projects.filter(func(project: Dictionary) -> bool: return str(project.get("tag", "")) != tag)
	for table: Dictionary in [state.nuclear_programs, state.attack_effects, state.research_close, state.event_flags,
			state.front_seats, state.front_holdings, state.land_neighbors]:
		purge_nested(table, tag)
	state.ai_ranking.erase(tag)
	state.pending_events = state.pending_events.filter(func(entry: Dictionary) -> bool:
		return str(entry.get("country", "")) != tag)
	state.scheduled_events = state.scheduled_events.filter(func(entry: Dictionary) -> bool:
		return str(entry.get("country", "")) != tag)
	state.provinces_by_owner.erase(tag)
	state.countries.erase(tag)
	state.gdp_ranks.clear()


## Supprime les clés qui citent le pays : « tag », « A|B », « A>B », « action|A|B ».
static func purge_keys(table: Dictionary, tag: String) -> void:
	for key: Variant in table.keys():
		var text := str(key)
		if text == tag or Array(text.replace(">", "|").split("|")).has(tag):
			table.erase(key)


## Supprime la ligne du pays et la colonne du pays dans chaque ligne (tables [A][B] ou tag → {tag: …}).
static func purge_nested(table: Dictionary, tag: String) -> void:
	table.erase(tag)
	for key: Variant in table.keys():
		if table[key] is Dictionary:
			(table[key] as Dictionary).erase(tag)


## Voisins terrestres des pays d'après les propriétaires actuels des provinces.
static func recompute_land_neighbors(state: SimState) -> void:
	var neighbors: Dictionary = {}
	for province_id: Variant in state.province_neighbors.keys():
		var owner := ControlSystem.owner(state, str(province_id))
		if owner.is_empty():
			continue
		for other: Variant in state.province_neighbors[province_id]:
			var other_owner := ControlSystem.owner(state, str(other))
			if other_owner.is_empty() or other_owner == owner:
				continue
			if not neighbors.has(owner):
				neighbors[owner] = {}
			(neighbors[owner] as Dictionary)[other_owner] = true
	state.land_neighbors = neighbors
	state.trade.land_neighbors = neighbors.duplicate(true)


## Nouveau nom, couleur et drapeau (champs vides : inchangés).
static func rename(state: SimState, tag: String, name_key: String, color: String, flag: String) -> void:
	if state.get_country(tag) == null:
		return
	var overrides: Dictionary = state.country_overrides.get(tag, {})
	if not name_key.is_empty():
		overrides["name_key"] = name_key
	if not color.is_empty():
		overrides["color"] = color
	if not flag.is_empty():
		overrides["flag"] = flag
	state.country_overrides[tag] = overrides
	state.add_event(EVENT_RENAMED, tag, {"name_key": name_key})

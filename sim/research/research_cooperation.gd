class_name ResearchCooperation
extends RefCounted
## Coopération et espionnage industriel.
##
## Projet conjoint : deux pays mettent la même technologie dans un de leurs emplacements ; l'avancement est commun
## (et plus rapide) et la technologie est acquise par les deux. Un pays de l'IA accepte si relations × poids
## + alliance + union commune + base > 0 (relations minimales exigées) ; il libère au besoin un emplacement.
## Espionnage industriel : voler une technologie connue d'un autre pays ; chance selon les jauges cyber ; une
## réussite donne une part du coût en avancement ; découverte possible (relations, confiance).

const EVENT_JOINT := &"joint_project_started"
const EVENT_JOINT_REFUSED := &"joint_project_refused"
const EVENT_ESPIONAGE := &"industrial_espionage"
const PERCENT := 100.0


static func joint_rules(state: SimState) -> Dictionary:
	return ResearchSystem.settings_of(state).get("joint", {})


static func espionage_rules(state: SimState) -> Dictionary:
	return ResearchSystem.settings_of(state).get("espionage", {})


# --- Projets conjoints ----------------------------------------------------------------------------------------

static func joint_refusal(state: SimState, tag: String, partner: String, tech_id: String) -> String:
	var country := state.get_country(tag)
	var other := state.get_country(partner)
	if country == null or other == null or tag == partner or country.research == null or other.research == null:
		return "RESEARCH_INVALID"
	var status := ResearchSystem.availability(state, country, tech_id)
	if not status.is_empty():
		return status
	if other.research.is_known(tech_id) or not ResearchSystem.availability(state, other, tech_id).is_empty():
		return "RESEARCH_PARTNER_CANNOT"
	if not ResearchSystem.joint_project(state, tag, tech_id).is_empty() or country.research.is_researching(tech_id):
		return "RESEARCH_ALREADY"
	if not country.research.slots.has(""):
		return "RESEARCH_NO_SLOT"
	if state.diplomacy.relation(tag, partner) < float(joint_rules(state).get("min_relation", 0.0)):
		return "RESEARCH_RELATION_TOO_LOW"
	# Armement : co-développé seulement entre alliés.
	var tree := str((state.technology_definitions.get(tech_id, {}) as Dictionary).get("tree", ""))
	if (joint_rules(state).get("allied_trees", []) as Array).has(tree) and not ControlSystem.allied(state, tag, partner):
		return "RESEARCH_NOT_ALLIED"
	return ""


## Intérêt d'un pays de l'IA pour un projet conjoint (positif : il accepte).
static func joint_score(state: SimState, tag: String, partner: String) -> float:
	var rules := joint_rules(state)
	var score := float(rules.get("accept_base", 0.0)) + float(rules.get("accept_relation", 0.0)) * state.diplomacy.relation(tag, partner)
	if ControlSystem.allied(state, tag, partner):
		score += float(rules.get("accept_alliance", 0.0))
	for organization: Dictionary in state.diplomacy.organizations.values():
		var members: Array = organization.get("members", [])
		if str(organization.get("kind", "")) == "economic_union" and members.has(tag) and members.has(partner):
			score += float(rules.get("accept_union", 0.0))
			break
	return score


## Proposition : acceptée par un pays de l'IA si son intérêt est positif (le joueur ne reçoit pas encore de
## propositions). Vrai si le projet démarre.
static func propose_joint(state: SimState, tag: String, partner: String, tech_id: String) -> bool:
	if partner == str(state.player_tag) or joint_score(state, partner, tag) <= 0.0:
		state.add_event(EVENT_JOINT_REFUSED, tag, {"partner": partner, "technology": tech_id})
		return false
	start_joint(state, tag, partner, tech_id)
	return true


static func start_joint(state: SimState, tag: String, partner: String, tech_id: String) -> void:
	var members := [tag, partner]
	var progress := 0.0
	for member: String in members:
		var research := state.get_country(member).research
		progress += float(research.progress.get(tech_id, 0.0))
		research.progress.erase(tech_id)
		var slot := research.slots.find("")
		if slot < 0:
			# Le partenaire libère l'emplacement dont la recherche est la moins avancée.
			slot = 0
			for index: int in research.slots.size():
				if float(research.progress.get(research.slots[index], 0.0)) < float(research.progress.get(research.slots[slot], 0.0)):
					slot = index
		research.slots[slot] = tech_id
	state.joint_projects.append({"tech": tech_id, "members": members, "progress": progress})
	state.add_event(EVENT_JOINT, tag, {"partner": partner, "technology": tech_id})


## Un membre quitte le projet : il garde l'avancement commun ; le projet devient la recherche seule de l'autre.
static func leave(state: SimState, project: Dictionary, _tag: String) -> void:
	state.joint_projects.erase(project)
	var tech_id := str(project["tech"])
	for member: Variant in project["members"]:
		var research := state.get_country(str(member)).research
		research.progress[tech_id] = float(project["progress"])


static func partner_of(state: SimState, tag: String, tech_id: String) -> String:
	var project := ResearchSystem.joint_project(state, tag, tech_id)
	for member: Variant in project.get("members", []):
		if str(member) != tag:
			return str(member)
	return ""


# --- Espionnage industriel ------------------------------------------------------------------------------------

static func espionage_refusal(state: SimState, tag: String, target: String, tech_id: String) -> String:
	var country := state.get_country(tag)
	var victim := state.get_country(target)
	if country == null or victim == null or tag == target or country.research == null or victim.research == null:
		return "RESEARCH_INVALID"
	if country.research.espionage_cooldown > 0:
		return "MILITARY_COOLDOWN"
	if not victim.research.is_known(tech_id):
		return "RESEARCH_TARGET_UNKNOWN"
	return ResearchSystem.availability(state, country, tech_id)


static func espionage_chance(state: SimState, tag: String, target: String) -> float:
	var rules := espionage_rules(state)
	var edge := MilitaryActions.gauge(state, tag, "cyber") - MilitaryActions.gauge(state, target, "cyber")
	return clampf(float(rules.get("base", 0.0)) + float(rules.get("weight", 0.0)) * edge / PERCENT,
		float(rules.get("min", 0.0)), float(rules.get("max", 1.0)))


static func discovery_chance(state: SimState, target: String) -> float:
	var rules := espionage_rules(state)
	return clampf(float(rules.get("discovery_base", 0.0)) + float(rules.get("discovery_weight", 0.0))
		* MilitaryActions.gauge(state, target, "cyber") / PERCENT, 0.0, 1.0)


## Vol de technologie : avancement gagné en cas de réussite (achevée si le coût est atteint), découverte possible.
static func steal(state: SimState, tag: String, target: String, tech_id: String) -> Dictionary:
	var rules := espionage_rules(state)
	var country := state.get_country(tag)
	country.research.espionage_cooldown = int(rules.get("cooldown", 0))
	var success := state.rng.randf() < espionage_chance(state, tag, target)
	if success:
		var research := country.research
		var project := ResearchSystem.joint_project(state, tag, tech_id)
		var gained := ResearchSystem.cost(state, tech_id, country) * float(rules.get("progress_share", 0.0))
		if not project.is_empty():
			project["progress"] = float(project["progress"]) + gained
		else:
			research.progress[tech_id] = float(research.progress.get(tech_id, 0.0)) + gained
			if float(research.progress[tech_id]) >= ResearchSystem.cost(state, tech_id, country):
				ResearchSystem.complete(state, country, tech_id)
	var discovered := state.rng.randf() < discovery_chance(state, target)
	if discovered:
		state.diplomacy.change_relation(tag, target, float(rules.get("discovered_relation", 0.0)))
		state.diplomacy.change_trust(tag, target, float(rules.get("discovered_trust", 0.0)))
	state.add_event(EVENT_ESPIONAGE, tag, {"target": target, "technology": tech_id, "success": success,
		"discovered": discovered})
	return {"success": success, "discovered": discovered}


# --- IA ---------------------------------------------------------------------------------------------------------

## Chaque mois : projet conjoint avec un pays proche (alliés, partenaires), espionnage industriel pour les
## régimes non démocratiques bien équipés en cyber.
static func decide_month(state: SimState, country: CountryState) -> void:
	var tag := country.tag
	var joint := joint_rules(state)
	if country.research.slots.has("") and state.rng.randf() < float(joint.get("ai_chance", 0.0)):
		for partner: Variant in state.research_close.get(tag, []):
			var other := str(partner)
			if other == str(state.player_tag):
				continue
			var tech_id := _shared_target(state, country, other)
			if not tech_id.is_empty() and joint_refusal(state, tag, other, tech_id).is_empty():
				propose_joint(state, tag, other, tech_id)
				break
	var rules := espionage_rules(state)
	if country.politics.democratic or MilitaryActions.gauge(state, tag, "cyber") < float(rules.get("ai_min_cyber", INF)) \
			or state.rng.randf() >= float(rules.get("ai_chance", 0.0)):
		return
	var best_target := ""
	var best_tech := ""
	var best_cost := 0.0
	for other: String in state.countries.keys():
		if other == tag or state.diplomacy.relation(tag, other) >= 0.0:
			continue
		var victim: CountryState = state.countries[other]
		if victim.research == null:
			continue
		for tech_id: Variant in victim.research.known.keys():
			var key := str(tech_id)
			var value := ResearchSystem.cost(state, key, country)
			if value > best_cost and espionage_refusal(state, tag, other, key).is_empty():
				best_target = other
				best_tech = key
				best_cost = value
	if not best_tech.is_empty():
		steal(state, tag, best_target, best_tech)


## Technologie que deux pays peuvent rechercher ensemble (la plus chère, pour en tirer le plus).
static func _shared_target(state: SimState, country: CountryState, partner: String) -> String:
	var other := state.get_country(partner)
	if other == null or other.research == null:
		return ""
	var best := ""
	var best_cost := 0.0
	for tech_id: String in state.technology_definitions.keys():
		if not joint_refusal(state, country.tag, partner, tech_id).is_empty():
			continue
		var value := ResearchSystem.cost(state, tech_id, country)
		if value > best_cost:
			best = tech_id
			best_cost = value
	return best

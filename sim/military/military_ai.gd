class_name MilitaryAI
extends RefCounted
## Décisions militaires des pays de l'IA et des factions rebelles (module remplaçable via MilitaryRegistry).
##
## Chaque semaine : les groupes vont sur les fronts selon les forces en face, puis chaque front reçoit une
## posture selon le rapport de forces (offensive au-dessus d'un seuil, tenir en dessous d'un autre).
## Chaque mois, pour chaque pays de l'IA :
## - paix : le meneur d'un camp propose une paix blanche si sa population est occupée, s'il est nettement plus
##   faible ou si la guerre s'enlise sans gain ;
## - mobilisation : partielle en guerre, générale si la guerre tourne mal, démobilisation en paix ;
## - entrée en guerre volontaire aux côtés d'un ami proche, contre un ennemi sans arme nucléaire et à forces
##   favorables (chance mensuelle) ;
## - déclaration de guerre à un voisin ou à un pays revendiqué, avec un but justifié et un rapport de forces
##   favorable (alliés de la cible comptés). Score = base + revendication + hostilité + log10(rapport de forces)
##   (plafonné) + tension au-dessus du fond + régime + guerres en cours + dissuasion nucléaire de la cible ;
##   chance mensuelle = score × pas, plafonnée.

## Pays voisins de chaque pays (contrôleurs de provinces au contact) et provinces tenues par l'étranger
## (propriétaire → {pays qui en tient une part: true}), recalculés en début de mois.
var _borders: Dictionary = {}
var _foreign_held: Dictionary = {}
var _control_version: int = -1


## Début du mois : frontières terrestres entre pays (une passe sur la carte).
func begin_month(state: SimState) -> void:
	if state.control_version == _control_version and not _borders.is_empty():
		return
	_control_version = state.control_version
	_borders.clear()
	_foreign_held.clear()
	var watched: Dictionary = {}
	for province_id: String in state.province_control.keys():
		var tag := str(state.province_control[province_id])
		var owner := str(state.province_owner.get(province_id, ""))
		if tag != owner:
			_hold(owner, tag)
			watched[province_id] = true
	for province_id: String in state.contested.keys():
		_hold(str(state.province_owner.get(province_id, "")), str((state.contested[province_id] as Dictionary)["by"]))
	# Frontières : provinces frontalières et provinces disputées ou tenues par l'étranger.
	for province_id: String in state.border_provinces:
		watched[province_id] = true
	for province_id: String in state.contested.keys():
		watched[province_id] = true
	for province_id: Variant in watched.keys():
		var tag := ControlSystem.controller(state, str(province_id))
		if not state.countries.has(tag):
			continue
		for neighbor: Variant in ControlSystem.neighbors(state, str(province_id)):
			var other := ControlSystem.controller(state, str(neighbor))
			if other == tag or not state.countries.has(other):
				continue
			if not _borders.has(tag):
				_borders[tag] = {}
			(_borders[tag] as Dictionary)[other] = true


func _hold(owner: String, holder: String) -> void:
	if owner.is_empty() or holder == owner:
		return
	if not _foreign_held.has(owner):
		_foreign_held[owner] = {}
	(_foreign_held[owner] as Dictionary)[holder] = true


func settings_of(state: SimState) -> Dictionary:
	return state.military_settings.get("ai", {})


## Un mois de décisions pour un pays de l'IA.
func decide_month(country: CountryState, state: SimState) -> void:
	if country.military == null or country.military.branches.is_empty() or settings_of(state).is_empty():
		return
	var tag := country.tag
	_seek_peace(tag, state)
	_mobilize(country, state)
	_join_wars(tag, state)
	_declare_war(country, state)


# --- Paix ----------------------------------------------------------------------------------------------------

func _seek_peace(tag: String, state: SimState) -> void:
	var rules: Dictionary = settings_of(state).get("peace", {})
	for war: War in WarSystem.wars_of(state, tag):
		if war.civil or not WarSystem.white_peace_refusal(state, tag, war.id).is_empty():
			continue
		if war.months() < float(rules.get("min_months", 0.0)):
			continue
		if wants_peace(state, war, tag):
			WarSystem.offer_peace(state, war, tag)
			if not state.wars.has(war.id):
				return


## Le meneur d'un camp veut la paix : population occupée, forces nettement inférieures, ou guerre enlisée sans
## gain territorial.
func wants_peace(state: SimState, war: War, tag: String) -> bool:
	var rules: Dictionary = settings_of(state).get("peace", {})
	var side := war.side_of(tag)
	var other := War.other_side(side)
	var occupied := WarSystem.occupied_percent(state, war, side)
	var holding := WarSystem.occupied_percent(state, war, other)
	if occupied > holding + float(rules.get("occupied_percent", 0.0)):
		return true
	if WarSystem.side_power(state, war, side) < WarSystem.side_power(state, war, other) * float(rules.get("power_ratio", 0.0)) \
			and holding <= occupied:
		return true
	return war.months() >= float(rules.get("stalemate_months", INF)) and holding < float(rules.get("occupied_percent", 0.0))


# --- Mobilisation --------------------------------------------------------------------------------------------

func _mobilize(country: CountryState, state: SimState) -> void:
	var rules: Dictionary = settings_of(state).get("mobilization", {})
	var military := country.military
	var at_war := false
	var losing := false
	for war: War in WarSystem.wars_of(state, country.tag):
		if war.civil:
			continue
		at_war = true
		var side := war.side_of(country.tag)
		losing = losing or WarSystem.side_power(state, war, side) 			< WarSystem.side_power(state, war, War.other_side(side)) * float(rules.get("losing_ratio", 0.0)) 			or WarSystem.occupied_percent(state, war, side) >= float(rules.get("losing_occupied_percent", INF))
	# En guerre, on mobilise (sans jamais démobiliser) ; en paix, on revient au niveau de départ.
	var target := military.start_mobilization
	if at_war:
		target = maxi(military.mobilization, 2 if losing else 1)
	var command := MobilizeCommand.new(StringName(country.tag), target)
	if command.can_execute(state):
		command.execute(state)


# --- Entrée en guerre volontaire ------------------------------------------------------------------------------

func _join_wars(tag: String, state: SimState) -> void:
	var rules: Dictionary = settings_of(state).get("join", {})
	var ids: Array = state.wars.keys()
	ids.sort()
	for war_id: Variant in ids:
		var war: War = state.wars[war_id]
		if war.civil or war.involves(tag):
			continue
		for side: String in [War.ATTACKERS, War.DEFENDERS]:
			if join_score(state, war, tag, side) and state.rng.randf() < float(rules.get("chance", 0.0)):
				WarSystem.join(state, war, tag, side, false)
				return


## Conditions d'une entrée en guerre volontaire : ami proche du meneur, hostile à l'ennemi, voisin de l'ennemi
## ou allié du meneur, ennemi sans arme nucléaire, forces favorables une fois entré.
func join_score(state: SimState, war: War, tag: String, side: String) -> bool:
	var rules: Dictionary = settings_of(state).get("join", {})
	var leader := war.members(side)[0]
	var other := War.other_side(side)
	if state.diplomacy.relation(tag, leader) < float(rules.get("min_relation", 0.0)):
		return false
	var concerned := ControlSystem.allied(state, tag, leader)
	for enemy: String in war.members(other):
		concerned = concerned or (_borders.get(tag, {}) as Dictionary).has(enemy)
	if not concerned:
		return false
	if not WarSystem.join_refusal(state, tag, war.id, side).is_empty():
		return false
	for enemy: String in war.members(other):
		if state.diplomacy.relation(tag, enemy) > float(rules.get("max_enemy_relation", 0.0)):
			return false
		var enemy_country := state.get_country(enemy)
		if enemy_country != null and enemy_country.military != null and enemy_country.military.nuclear_warheads > 0:
			return false
	var ours := WarSystem.side_power(state, war, side) + MilitarySystem.power(state, tag)
	return ours >= WarSystem.side_power(state, war, other) * float(rules.get("min_power_ratio", 0.0))


# --- Déclaration de guerre ------------------------------------------------------------------------------------

func _declare_war(country: CountryState, state: SimState) -> void:
	var best := best_war(country, state)
	if best.is_empty():
		return
	var rules: Dictionary = settings_of(state).get("war", {})
	var chance := minf(float(best["score"]) * float(rules.get("chance_per_point", 0.0)), float(rules.get("max_chance", 0.0)))
	if state.rng.randf() < chance:
		WarSystem.declare(state, country.tag, str(best["target"]), str(best["goal"]))


## Meilleure guerre possible : {target, goal, score} (vide si aucune n'a un score positif).
func best_war(country: CountryState, state: SimState) -> Dictionary:
	var rules: Dictionary = settings_of(state).get("war", {})
	var tag := country.tag
	var candidates: Dictionary = (_borders.get(tag, {}) as Dictionary).duplicate()
	for claim: Dictionary in state.diplomacy.claims.values():
		if claim["claimant"] == tag and state.countries.has(claim["target"]):
			candidates[claim["target"]] = true
	var targets: Array = candidates.keys()
	targets.sort()
	var best: Dictionary = {}
	for target: String in targets:
		var evaluation := war_score(state, country, target)
		if not evaluation.is_empty() and float(evaluation["score"]) > float(best.get("score", 0.0)):
			best = evaluation
	return best


## Intérêt d'une guerre contre target : {target, goal, score}, vide si aucun but n'est justifié ou si le rapport
## de forces est insuffisant.
func war_score(state: SimState, country: CountryState, target: String) -> Dictionary:
	var rules: Dictionary = settings_of(state).get("war", {})
	var tag := country.tag
	# Filtres peu coûteux d'abord : rapport de forces seul et meilleur score possible.
	var ours := MilitarySystem.power(state, tag)
	var target_power := maxf(MilitarySystem.power(state, target), WarResolver.MIN_STRENGTH)
	var min_ratio := float(rules.get("min_power_ratio", 0.0))
	if ours < target_power * min_ratio:
		return {}
	var score := float(rules.get("base", 0.0)) + float(rules.get("relation", 0.0)) * state.diplomacy.relation(tag, target) 		+ float(rules.get("tension", 0.0)) * (state.diplomacy.world_tension - float(rules.get("tension_baseline", 0.0))) 		+ float(rules.get("democratic" if country.politics.democratic else "authoritarian", 0.0)) 		+ float(rules.get("per_war", 0.0)) * WarSystem.wars_of(state, tag).size()
	var max_log := float(rules.get("max_power_log", INF))
	var target_country := state.get_country(target)
	if target_country != null and target_country.military != null and target_country.military.nuclear_warheads > 0:
		score += float(rules.get("nuclear_target", 0.0))
	if score + float(rules.get("claim", 0.0)) + float(rules.get("power", 0.0)) * minf(log(ours / target_power) / log(10.0),
			max_log) <= 0.0:
		return {}
	var goal := ""
	for candidate: Variant in rules.get("goal_order", []):
		var requires := str((state.war_goal_definitions.get(str(candidate), {}) as Dictionary).get("requires", ""))
		if requires == WarSystem.REQUIRES_OCCUPIED and not (_foreign_held.get(tag, {}) as Dictionary).has(target):
			continue
		if WarSystem.declare_refusal(state, tag, target, str(candidate)).is_empty():
			goal = str(candidate)
			break
	if goal.is_empty():
		return {}
	var theirs := target_power
	for ally: String in WarSystem.defenders_called(state, tag, target):
		theirs += float(rules.get("ally_weight", 0.0)) * MilitarySystem.power(state, ally)
	var ratio := ours / theirs
	if ratio < min_ratio:
		return {}
	score += float(rules.get("power", 0.0)) * minf(log(ratio) / log(10.0), max_log)
	if goal == "annex" or goal == "liberate":
		score += float(rules.get("claim", 0.0))
	return {"target": target, "goal": goal, "score": score} if score > 0.0 else {}


# --- Chaque semaine -------------------------------------------------------------------------------------------

## Une semaine de décisions de guerre pour un pays de l'IA ou une faction rebelle.
func decide_week(tag: String, state: SimState) -> void:
	if FrontSystem.fronts_of(state, tag).is_empty():
		return
	if not WarSystem.is_rebel(state, tag):
		FrontSystem.auto_deploy(state, tag)
	choose_postures(tag, state)


## Posture de chaque front selon le rapport des forces engagées (puissance).
func choose_postures(tag: String, state: SimState) -> void:
	var rules: Dictionary = FrontSystem.combat_settings(state).get("ai", {})
	var rebel := WarSystem.is_rebel(state, tag)
	var ours := FrontSystem.engaged_personnel(state, tag)
	var quality := FrontSystem.quality(state, tag)
	for front: Front in FrontSystem.fronts_of(state, tag):
		var enemy := front.other(tag)
		var theirs: float = float(FrontSystem.engaged_personnel(state, enemy).get(front.key, 0.0)) \
			* FrontSystem.quality(state, enemy)
		var ratio := float(ours.get(front.key, 0.0)) * quality / maxf(theirs, WarResolver.MIN_STRENGTH)
		var posture := "defensive"
		if ratio >= float(rules.get("rebel_offensive_ratio" if rebel else "offensive_ratio", INF)):
			posture = "offensive"
		elif ratio < float(rules.get("hold_ratio", 0.0)):
			posture = "hold"
		front.postures[tag] = posture

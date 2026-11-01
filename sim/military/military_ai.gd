class_name MilitaryAI
extends RefCounted
## Décisions militaires des pays de l'IA et des factions rebelles (module remplaçable via MilitaryRegistry).
## Règle simple de l'étape 7c2 : chaque semaine, les groupes vont sur les fronts selon les forces en face, puis
## chaque front reçoit une posture selon le rapport de forces (offensive au-dessus d'un seuil, tenir en dessous
## d'un autre, défensive sinon). Déclarations de guerre, alliances et paix : étape 7c3.


## Un mois de décisions pour un pays de l'IA.
func decide_month(_country: CountryState, _state: SimState) -> void:
	pass


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

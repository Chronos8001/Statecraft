class_name ResearchSystem
extends SimSystem
## Recherche et technologie. Chaque mois, chaque pays produit des points de recherche, répartis entre ses
## emplacements ; une technologie achevée applique ses effets. L'IA remplit ses emplacements libres.
##
## Points du mois = poids × √(dépense de R&D en milliards par an) × (1 + bonus des universités) × (1 + effet
## « recherche » du budget × poids) × (1 + bonus des technologies). Dépense de R&D = PIB × part de R&D.
## Emplacements = 1 + √(dépense) / pas, bornés. Coût d'une technologie diminué (rattrapage) selon le nombre de
## pays qui la connaissent déjà. Une technologie n'est disponible qu'à partir de son année et une fois ses
## prérequis connus.
## Départ : un pays connaît une technologie si son indice technologique (niveau de vie, part de R&D, universités,
## taille de l'économie) atteint le seuil de la technologie, si son armée atteint le niveau demandé, ou s'il est
## dans la liste des pays qui la maîtrisent.

const PRIORITY := -20
const EVENT_COMPLETED := &"technology_completed"
const EVENT_SLOT_FREE := &"research_slot_free"
const PERCENT := 100.0
const MONTHS_PER_YEAR := 12.0
const GROWTH := "growth"
const RESEARCH := "research"
const STABILITY := "stability"
const MILITARY_PREFIX := "military:"
const SPECIAL_PREFIX := "special:"
const ENERGY_PREFIX := "energy:"


func get_id() -> StringName:
	return &"research"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


static func settings_of(state: SimState) -> Dictionary:
	return state.research_settings


# --- Départ ---------------------------------------------------------------------------------------------------

## Indice technologique d'un pays (0 à 100).
static func tech_index(state: SimState, country: CountryState) -> float:
	var rules: Dictionary = settings_of(state).get("index", {})
	var research := country.research
	var gdp := TradeSystem.current_gdp(state, country.tag)
	var per_capita := gdp * 1.0e9 / maxf(float(country.economy.population), 1.0)
	var value := float(rules.get("gdp_per_capita_weight", 0.0)) * log(maxf(per_capita / float(rules.get("gdp_per_capita_reference",
		1.0)), 1.0)) / log(10.0) \
		+ minf(float(rules.get("rd_weight", 0.0)) * research.rd_share, float(rules.get("rd_max", INF))) \
		+ float(rules.get("universities_weight", 0.0)) * log(1.0 + research.universities) / log(10.0) \
		+ float(rules.get("size_weight", 0.0)) * log(maxf(gdp, 1.0)) / log(10.0)
	return clampf(value, 0.0, PERCENT)


static func setup_country(state: SimState, country: CountryState, data: Dictionary) -> void:
	var research := ResearchState.new()
	var values: Dictionary = data.get("research", {})
	research.rd_share = float(values.get("rd_gdp_share", 0.0))
	research.universities = int(values.get("universities", 0))
	country.research = research
	var index := tech_index(state, country)
	for tech_id: String in state.technology_definitions.keys():
		if _known_at_start(state, country, state.technology_definitions[tech_id], index):
			research.known[tech_id] = true
	research.start_known = research.known.duplicate()
	research.slots.clear()
	for _index: int in slot_count(state, country):
		research.slots.append("")
	research.points = monthly_points(state, country)


static func _known_at_start(state: SimState, country: CountryState, definition: Dictionary, index: float) -> bool:
	var start: Dictionary = definition.get("start", {})
	if start.is_empty() or int(definition.get("year", 0)) > state.date.year:
		return false
	if start.has("countries"):
		return (start["countries"] as Array).has(country.tag)
	if start.has("military"):
		var rule: Array = start["military"]
		var branch: Dictionary = country.military.branches.get(str(rule[0]), {}) if country.military != null else {}
		return not branch.is_empty() and float(branch.get("level", 0.0)) >= float(rule[1])
	return index >= float(start.get("index", INF))


# --- Points, emplacements, coûts ------------------------------------------------------------------------------

## Dépense de R&D du pays (milliards de dollars par an).
static func rd_spending(state: SimState, country: CountryState) -> float:
	return TradeSystem.current_gdp(state, country.tag) * country.research.rd_share / PERCENT


static func monthly_points(state: SimState, country: CountryState) -> float:
	var rules := settings_of(state)
	var universities := minf(float(rules.get("university_bonus", 0.0)) * country.research.universities,
		float(rules.get("university_bonus_max", 0.0)))
	var budget := float(country.economy.budget.effects.get(RESEARCH, 0.0)) * float(rules.get("budget_weight", 0.0)) / PERCENT
	return float(rules.get("points_per_sqrt_billion", 0.0)) * sqrt(maxf(rd_spending(state, country), 0.0)) \
		* (1.0 + universities) * maxf(1.0 + budget, 0.1) * (1.0 + (country.research.effect(RESEARCH) + country.research.ai_research) / PERCENT)


static func slot_count(state: SimState, country: CountryState) -> int:
	var rules: Dictionary = settings_of(state).get("slots", {})
	return clampi(1 + floori(sqrt(maxf(rd_spending(state, country), 0.0)) / float(rules.get("sqrt_billion_per_slot", 1.0))),
		int(rules.get("min", 1)), int(rules.get("max", 1)))


## Coût d'une technologie : réduit quand beaucoup de pays la connaissent déjà (rattrapage), et pour un pays dont
## un allié ou un grand partenaire commercial la connaît (diffusion).
static func cost(state: SimState, tech_id: String, country: CountryState = null) -> float:
	var rules: Dictionary = settings_of(state).get("catch_up", {})
	var known := int(state.tech_known_counts.get(tech_id, 0))
	var discount := float(rules.get("max", 0.0)) * minf(float(known) / float(rules.get("countries_for_max", 1.0)), 1.0)
	if country != null:
		for other: Variant in state.research_close.get(country.tag, []):
			var close := state.get_country(str(other))
			if close != null and close.research != null and close.research.is_known(tech_id):
				discount += float((settings_of(state).get("diffusion", {}) as Dictionary).get("discount", 0.0))
				break
	return float((state.technology_definitions.get(tech_id, {}) as Dictionary).get("cost", 0.0)) * (1.0 - discount)


## Raison pour laquelle une technologie ne peut pas être recherchée ("" si elle peut l'être).
static func availability(state: SimState, country: CountryState, tech_id: String) -> String:
	var definition: Dictionary = state.technology_definitions.get(tech_id, {})
	if definition.is_empty():
		return "RESEARCH_INVALID"
	if country.research.is_known(tech_id):
		return "RESEARCH_ALREADY_KNOWN"
	if int(definition.get("year", 0)) > state.date.year:
		return "RESEARCH_TOO_EARLY"
	for required: Variant in definition.get("requires", []):
		if not country.research.is_known(str(required)):
			return "RESEARCH_MISSING_PREREQUISITE"
	return ""


## Mois restants pour achever une technologie dans un emplacement (au rythme du mois).
static func months_left(state: SimState, country: CountryState, tech_id: String) -> int:
	var research := country.research
	var busy := maxi(research.slots.filter(func(slot: String) -> bool: return not slot.is_empty()).size(), 1)
	var per_slot := research.points / busy
	var project := joint_project(state, country.tag, tech_id)
	var done := float(project.get("progress", 0.0)) if not project.is_empty() else float(research.progress.get(tech_id, 0.0))
	var left := cost(state, tech_id, country) - done
	return ceili(left / per_slot) if per_slot > 0.0 else -1


# --- Chaque mois ----------------------------------------------------------------------------------------------

func on_month(state: SimState) -> void:
	if state.technology_definitions.is_empty():
		return
	refresh_known_counts(state)
	refresh_close(state)
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		if country.research == null:
			continue
		_adjust_slots(state, country)
		advance(state, country)
		if country.research.espionage_cooldown > 0:
			country.research.espionage_cooldown -= 1
		if StringName(tag) != state.player_tag:
			ResearchCooperation.decide_month(state, country)
			choose_research(state, country)


## Pays proches de chacun (diffusion) : alliés militaires et principaux partenaires commerciaux.
static func refresh_close(state: SimState) -> void:
	state.research_close.clear()
	var count := int((settings_of(state).get("diffusion", {}) as Dictionary).get("trade_partners", 0))
	for tag: String in state.countries.keys():
		var close: Array = []
		if not state.trade.start_flows.is_empty():
			for entry: Variant in TradeSystem.top_partners(state, tag, count):
				close.append(str((entry as Array)[0]) if entry is Array else str(entry))
		for treaty_id: int in state.diplomacy.treaties_of(tag):
			var treaty: Dictionary = state.diplomacy.treaties[treaty_id]
			if str(treaty["type"]) == "mutual_defense":
				close.append(str(treaty["b"]) if treaty["a"] == tag else str(treaty["a"]))
		for organization: Dictionary in state.diplomacy.organizations.values():
			var members: Array = organization.get("members", [])
			if str(organization.get("kind", "")) == "military_alliance" and members.has(tag):
				for member: Variant in members:
					if str(member) != tag and not close.has(str(member)):
						close.append(str(member))
		state.research_close[tag] = close


## Nombre de pays qui connaissent chaque technologie (rattrapage).
static func refresh_known_counts(state: SimState) -> void:
	state.tech_known_counts.clear()
	for country: CountryState in state.countries.values():
		if country.research == null:
			continue
		for tech_id: Variant in country.research.known.keys():
			state.tech_known_counts[tech_id] = int(state.tech_known_counts.get(tech_id, 0)) + 1


static func _adjust_slots(state: SimState, country: CountryState) -> void:
	var wanted := slot_count(state, country)
	var slots := country.research.slots
	while slots.size() < wanted:
		slots.append("")
	while slots.size() > wanted and slots.has(""):
		slots.erase("")


## Un mois de recherche : points répartis entre les emplacements occupés, technologies achevées.
static func advance(state: SimState, country: CountryState) -> void:
	var research := country.research
	research.points = monthly_points(state, country)
	var busy: Array[String] = []
	for tech_id: String in research.slots:
		if not tech_id.is_empty():
			busy.append(tech_id)
	if busy.is_empty():
		return
	var share := research.points / busy.size()
	for tech_id: String in busy:
		var project := joint_project(state, country.tag, tech_id)
		if not project.is_empty():
			# Projet conjoint : avancement commun, plus rapide ; achevé pour tous les membres.
			project["progress"] = float(project["progress"]) + share * (1.0 + float((settings_of(state).get("joint", {})
				as Dictionary).get("speed_bonus", 0.0)))
			if float(project["progress"]) >= cost(state, tech_id, country):
				state.joint_projects.erase(project)
				for member: Variant in project["members"]:
					var partner := state.get_country(str(member))
					if partner != null and not partner.research.is_known(tech_id):
						complete(state, partner, tech_id)
			continue
		research.progress[tech_id] = float(research.progress.get(tech_id, 0.0)) + share
		if float(research.progress[tech_id]) >= cost(state, tech_id, country):
			complete(state, country, tech_id)


## Technologie acquise : connue, effets appliqués, emplacement libéré.
static func complete(state: SimState, country: CountryState, tech_id: String) -> void:
	var research := country.research
	research.known[tech_id] = true
	state.tech_known_counts[tech_id] = int(state.tech_known_counts.get(tech_id, 0)) + 1
	research.progress.erase(tech_id)
	var index := research.slots.find(tech_id)
	if index >= 0:
		research.slots[index] = ""
	apply_effects(state, country, (state.technology_definitions.get(tech_id, {}) as Dictionary).get("effects", {}))
	state.add_event(EVENT_COMPLETED, country.tag, {"technology": tech_id})
	if index >= 0 and StringName(country.tag) == state.player_tag:
		state.add_event(EVENT_SLOT_FREE, country.tag, {})


## Effets d'une technologie acquise pendant la partie : croissance, recherche, armée, capacités spéciales,
## sources d'énergie, stabilité ; santé, éducation, climat et renseignement sont gardés pour leurs étapes.
static func apply_effects(state: SimState, country: CountryState, effects: Dictionary) -> void:
	var research := country.research
	for key: Variant in effects.keys():
		var name := str(key)
		var value := float(effects[key])
		research.effects[name] = research.effect(name) + value
		if name == STABILITY:
			country.society.start_stability += value
		elif name.begins_with(ENERGY_PREFIX):
			var source := name.substr(ENERGY_PREFIX.length())
			if country.energy.capacity.has(source):
				country.energy.capacity[source] = float(country.energy.capacity[source]) * (1.0 + value)
	# La croissance de 2026 compte déjà le rythme habituel de l'innovation : seule une part de l'effet s'ajoute.
	country.economy.research_growth = research.effect(GROWTH) * float(settings_of(state).get("growth_scale", 1.0))
	if country.military != null:
		for key: Variant in research.effects.keys():
			var name := str(key)
			if name.begins_with(MILITARY_PREFIX):
				country.military.tech_levels[name.substr(MILITARY_PREFIX.length())] = research.effect(name)
			elif name.begins_with(SPECIAL_PREFIX):
				var gauge := name.substr(SPECIAL_PREFIX.length())
				country.military.tech_special[gauge] = research.effect(name) + (research.ai_cyber if gauge == "cyber" else 0.0)


# --- Choix -----------------------------------------------------------------------------------------------------

static func set_slot(state: SimState, country: CountryState, slot: int, tech_id: String) -> void:
	var slots := country.research.slots
	if slot < 0 or slot >= slots.size():
		return
	# Retirer un projet conjoint y met fin pour ce pays.
	var previous := slots[slot]
	if not previous.is_empty():
		var project := joint_project(state, country.tag, previous)
		if not project.is_empty():
			ResearchCooperation.leave(state, project, country.tag)
	slots[slot] = tech_id


## Projet conjoint d'un pays sur une technologie ({} s'il n'y en a pas).
static func joint_project(state: SimState, tag: String, tech_id: String) -> Dictionary:
	for project: Dictionary in state.joint_projects:
		if str(project["tech"]) == tech_id and (project["members"] as Array).has(tag):
			return project
	return {}


## L'IA remplit ses emplacements libres : technologie disponible la plus intéressante (préférence pour l'arbre
## selon la situation du pays, coût moindre), en évitant les doublons.
static func choose_research(state: SimState, country: CountryState) -> void:
	var research := country.research
	if not research.slots.has(""):
		return
	var weights: Dictionary = (settings_of(state).get("ai", {}) as Dictionary).get(
		"war_weights" if not WarSystem.wars_of(state, country.tag).is_empty() else "peace_weights", {})
	var candidates: Array = []
	for tech_id: String in state.technology_definitions.keys():
		if research.is_researching(tech_id) or not availability(state, country, tech_id).is_empty():
			continue
		var tree := str((state.technology_definitions[tech_id] as Dictionary).get("tree", ""))
		candidates.append([float(weights.get(tree, 1.0)) / maxf(cost(state, tech_id, country), 1.0), tech_id])
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0]) if not is_equal_approx(float(a[0]), float(b[0])) else str(a[1]) < str(b[1]))
	for index: int in research.slots.size():
		if not research.slots[index].is_empty() or candidates.is_empty():
			continue
		research.slots[index] = str((candidates.pop_front() as Array)[1])

class_name ResearchPanel
extends InfoPanel
## Panneau Recherche du pays joué : points du mois, emplacements (technologie, avancement, mois restants),
## puis les technologies d'un arbre (connues, en cours, disponibles, verrouillées) avec leurs effets.

const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const KNOWN_COLOR := Color(0.55, 0.85, 0.55)
const ACTIVE_COLOR := Color(0.55, 0.75, 1.0)
const LOCKED_COLOR := Color(0.55, 0.58, 0.62)
const TREES := ["economy", "industry", "energy", "ai", "land", "air", "naval", "cyber", "space", "biotech", "health",
	"social"]
## Effets appliqués par des étapes à venir (affichés comme tels).
const PENDING_EFFECTS := ["health", "education", "climate", "intel"]
const PERCENT := 100.0

@onready var _summary_grid: GridContainer = %SummaryGrid
@onready var _slots_box: VBoxContainer = %SlotsBox
@onready var _tree_option: OptionButton = %TreeOption
@onready var _tech_list: VBoxContainer = %TechList
@onready var _close_button: Button = %CloseButton

var _ai_grid: GridContainer
var _ai_ranking: VBoxContainer
var _plan_button: Button


func _ready() -> void:
	_close_button.pressed.connect(close)
	_build_ai_box()
	_tree_option.item_selected.connect(func(_index: int) -> void: refresh())
	EventBus.locale_changed.connect(func(_locale: String) -> void: refresh())
	EventBus.month_passed.connect(func(_date: GameDate) -> void: refresh())
	EventBus.command_executed.connect(func(_command: Command) -> void: refresh())
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		visible = true
		refresh()


func refresh() -> void:
	if not visible:
		return
	var state := GameState.sim
	var country := state.get_country(str(state.player_tag))
	_clear_rows(_summary_grid)
	_clear_box(_slots_box)
	_clear_box(_tech_list)
	_clear_rows(_ai_grid)
	_clear_box(_ai_ranking)
	if country == null or country.research == null:
		return
	var research := country.research
	var locale := Localization.get_locale()
	_add_row(_summary_grid, "RESEARCH_POINTS", NumberFormat.decimal(research.points, 1, locale))
	_add_row(_summary_grid, "RESEARCH_RD_SPENDING", tr("RESEARCH_RD_VALUE") % [NumberFormat.decimal(research.rd_share, 2, locale),
		NumberFormat.decimal(ResearchSystem.rd_spending(state, country), 1, locale)])
	_add_row(_summary_grid, "RESEARCH_UNIVERSITIES", str(research.universities))
	_add_row(_summary_grid, "RESEARCH_KNOWN", "%d / %d" % [research.known.size(), state.technology_definitions.size()])
	_add_row(_summary_grid, "RESEARCH_INDEX", str(roundi(ResearchSystem.tech_index(state, country))))
	_fill_slots(state, country)
	_fill_ai_race(state, country, locale)
	if _tree_option.item_count == 0:
		for tree: String in TREES:
			_tree_option.add_item(tr("TREE_%s" % tree.to_upper()))
		_tree_option.select(0)
	else:
		for index: int in TREES.size():
			_tree_option.set_item_text(index, tr("TREE_%s" % TREES[index].to_upper()))
	_fill_tree(state, country, TREES[maxi(_tree_option.selected, 0)])


func _fill_slots(state: SimState, country: CountryState) -> void:
	var research := country.research
	for index: int in research.slots.size():
		var tech_id := research.slots[index]
		var row := HBoxContainer.new()
		var name := tr("RESEARCH_SLOT_EMPTY") if tech_id.is_empty() else _tech_name(state, tech_id)
		var partner := ResearchCooperation.partner_of(state, country.tag, tech_id) if not tech_id.is_empty() else ""
		if not partner.is_empty():
			name += " " + tr("RESEARCH_JOINT_WITH") % MilitaryUI.side_name(state, partner)
		var label := _text(name, LOCKED_COLOR if tech_id.is_empty() else ACTIVE_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if not tech_id.is_empty():
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(140, 0)
			bar.max_value = PERCENT
			var project := ResearchSystem.joint_project(state, country.tag, tech_id)
			var done := float(project["progress"]) if not project.is_empty() else float(research.progress.get(tech_id, 0.0))
			bar.value = done / maxf(ResearchSystem.cost(state, tech_id, country), 1.0) * PERCENT
			bar.show_percentage = true
			row.add_child(bar)
			row.add_child(_text(tr("RESEARCH_MONTHS") % ResearchSystem.months_left(state, country, tech_id), LABEL_COLOR))
			var remove := Button.new()
			remove.text = "RESEARCH_REMOVE"
			remove.tooltip_text = "RESEARCH_REMOVE_TOOLTIP"
			remove.focus_mode = Control.FOCUS_NONE
			var slot := index
			remove.pressed.connect(func() -> void: _submit(SetResearchCommand.new(state.player_tag, slot, "")))
			row.add_child(remove)
		_slots_box.add_child(row)


## Bloc « Course à l'IA », placé sous les emplacements de recherche.
func _build_ai_box() -> void:
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "AI_RACE_TITLE"
	title.add_theme_color_override("font_color", HEADER_COLOR)
	box.add_child(title)
	_ai_grid = GridContainer.new()
	_ai_grid.columns = 2
	box.add_child(_ai_grid)
	_plan_button = Button.new()
	_plan_button.text = "AI_PLAN_LAUNCH"
	_plan_button.focus_mode = Control.FOCUS_NONE
	_plan_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_plan_button.pressed.connect(func() -> void: _submit(LaunchAiPlanCommand.new(GameState.sim.player_tag)))
	box.add_child(_plan_button)
	_ai_ranking = VBoxContainer.new()
	box.add_child(_ai_ranking)
	_slots_box.get_parent().add_child(box)
	_slots_box.get_parent().move_child(box, _slots_box.get_index() + 1)


## Niveau et rang, régulation, plan, gains et risques ; classement des premiers pays.
func _fill_ai_race(state: SimState, country: CountryState, locale: String) -> void:
	var research := country.research
	var rank := AiRaceSystem.rank(state, country.tag)
	var level := NumberFormat.decimal(research.ai_level, 0, locale)
	_add_row(_ai_grid, "AI_RACE_LEVEL", tr("AI_RACE_LEVEL_RANK") % [level, rank] if rank > 0 else level)
	var law := str(AiRaceSystem.rules_of(state).get("law", ""))
	var option := LawModel.option_of(DataLoader.get_entry("laws", law), str(country.laws.get(law, "")))
	_add_row(_ai_grid, "AI_RACE_REGULATION", tr(str(option.get("name_key", ""))))
	_add_row(_ai_grid, "AI_RACE_GROWTH", "+" + NumberFormat.decimal(country.economy.ai_growth, 2, locale) + " %")
	_add_row(_ai_grid, "AI_RACE_UNEMPLOYMENT", "+" + NumberFormat.decimal(country.economy.ai_unemployment, 2, locale))
	_add_row(_ai_grid, "AI_RACE_STABILITY", NumberFormat.decimal(country.ai_stability, 1, locale))
	if research.ai_plan_months > 0:
		_add_row(_ai_grid, "AI_PLAN", tr("AI_PLAN_MONTHS") % research.ai_plan_months)
	var refusal := AiRaceSystem.plan_refusal(state, country.tag)
	_plan_button.disabled = not refusal.is_empty()
	_plan_button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("AI_PLAN_TOOLTIP") % [
		NumberFormat.decimal(AiRaceSystem.plan_cost(state, country.tag), 1, locale),
		int((AiRaceSystem.rules_of(state).get("plan", {}) as Dictionary).get("months", 0))]
	for index: int in mini(state.ai_ranking.size(), 5):
		var tag := state.ai_ranking[index]
		var other := state.get_country(tag)
		var text := "%d. %s — %s" % [index + 1, MilitaryUI.side_name(state, tag),
			NumberFormat.decimal(other.research.ai_level, 0, locale)]
		if state.agi_first == tag:
			text += " " + tr("AI_RACE_AGI_MARK")
		_ai_ranking.add_child(_text(text, KNOWN_COLOR if tag == country.tag else LABEL_COLOR))


## Technologies d'un arbre, par année : statut, coût, effets ; bouton pour la mettre dans un emplacement libre.
func _fill_tree(state: SimState, country: CountryState, tree: String) -> void:
	var research := country.research
	var ids: Array = []
	for tech_id: String in state.technology_definitions.keys():
		if str((state.technology_definitions[tech_id] as Dictionary).get("tree", "")) == tree:
			ids.append(tech_id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var year_a := int((state.technology_definitions[a] as Dictionary)["year"])
		var year_b := int((state.technology_definitions[b] as Dictionary)["year"])
		return year_a < year_b if year_a != year_b else a < b)
	var free := research.slots.find("")
	var locale := Localization.get_locale()
	for tech_id: String in ids:
		var definition: Dictionary = state.technology_definitions[tech_id]
		var row := HBoxContainer.new()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var status := ResearchSystem.availability(state, country, tech_id)
		var color := KNOWN_COLOR if research.is_known(tech_id) else ACTIVE_COLOR if research.is_researching(tech_id) \
			else HEADER_COLOR if status.is_empty() else LOCKED_COLOR
		info.add_child(_text("%s (%d)" % [_tech_name(state, tech_id), int(definition["year"])], color))
		var details := _effects_text(definition.get("effects", {}), locale)
		if not research.is_known(tech_id):
			details = tr("RESEARCH_COST") % roundi(ResearchSystem.cost(state, tech_id, country)) + " · " + details
		var missing := _missing(state, country, definition)
		if not missing.is_empty():
			details += " · " + tr("RESEARCH_REQUIRES") % missing
		info.add_child(_text(details, LABEL_COLOR))
		row.add_child(info)
		if not research.is_known(tech_id) and not research.is_researching(tech_id):
			var button := Button.new()
			button.text = "RESEARCH_START"
			button.focus_mode = Control.FOCUS_NONE
			var refusal := status if not status.is_empty() else "" if free >= 0 else "RESEARCH_NO_SLOT"
			button.disabled = not refusal.is_empty()
			button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("RESEARCH_START_TOOLTIP")
			var target := tech_id
			button.pressed.connect(func() -> void:
				var slot := country.research.slots.find("")
				if slot >= 0:
					_submit(SetResearchCommand.new(state.player_tag, slot, target)))
			row.add_child(button)
		_tech_list.add_child(row)


func _missing(state: SimState, country: CountryState, definition: Dictionary) -> String:
	var names: PackedStringArray = []
	for required: Variant in definition.get("requires", []):
		if not country.research.is_known(str(required)):
			names.append(_tech_name(state, str(required)))
	return ", ".join(names)


## Effets lisibles : « croissance +0,1 », « armée de terre +0,2 », « santé +3 (à venir) »…
func _effects_text(effects: Dictionary, locale: String) -> String:
	var parts: PackedStringArray = []
	for key: Variant in effects.keys():
		var name := str(key)
		var label := tr("TECH_EFFECT_%s" % name.replace(":", "_").to_upper())
		var value := float(effects[key])
		var shown := NumberFormat.decimal(value * PERCENT, 0, locale) + " %" if name.begins_with(ResearchSystem.ENERGY_PREFIX) \
			else NumberFormat.decimal(value, 2 if absf(value) < 1.0 else 0, locale)
		var text := "%s +%s" % [label, shown]
		if PENDING_EFFECTS.has(name):
			text += " " + tr("RESEARCH_EFFECT_PENDING")
		parts.append(text)
	return ", ".join(parts)


func _tech_name(state: SimState, tech_id: String) -> String:
	return tr(str((state.technology_definitions.get(tech_id, {}) as Dictionary).get("name_key", tech_id)))


func _text(text: String, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label


func _clear_box(box: Container) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _submit(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()

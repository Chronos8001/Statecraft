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


func _ready() -> void:
	_close_button.pressed.connect(close)
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
		var label := _text(tr("RESEARCH_SLOT_EMPTY") if tech_id.is_empty() else _tech_name(state, tech_id),
			LOCKED_COLOR if tech_id.is_empty() else ACTIVE_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if not tech_id.is_empty():
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(140, 0)
			bar.max_value = PERCENT
			bar.value = float(research.progress.get(tech_id, 0.0)) / maxf(ResearchSystem.cost(state, tech_id), 1.0) * PERCENT
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
			details = tr("RESEARCH_COST") % roundi(ResearchSystem.cost(state, tech_id)) + " · " + details
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

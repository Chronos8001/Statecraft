class_name DecisionPanel
extends InfoPanel
## Panneau Décisions du pays joué : onglet des décisions ponctuelles (en cours, puis par catégorie) et onglet
## de l'arbre de décisions, dessiné en graphe (nœuds faits, en cours, disponibles, fermés, verrouillés).

const WIDTH := 1240.0
const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const DONE_COLOR := Color(0.55, 0.85, 0.55)
const ACTIVE_COLOR := Color(0.55, 0.75, 1.0)
const LOCKED_COLOR := Color(0.55, 0.58, 0.62)
const EXCLUDED_COLOR := Color(0.85, 0.45, 0.45)
const BACKGROUND := Color(0.07, 0.09, 0.125, 0.96)
const BORDER := Color(0.25, 0.32, 0.42, 1)
const CATEGORIES := ["economy", "politics", "diplomacy", "military", "society"]
const PERCENT := 100.0

var _tabs: TabContainer
var _decision_list: VBoxContainer
var _focus_header: VBoxContainer
var _tree_view: FocusTreeView


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
	offset_left = 16.0
	offset_top = 96.0
	offset_right = 16.0 + WIDTH
	offset_bottom = -170.0


func _ready() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "DECISIONS_TITLE"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "COMMON_CLOSE_SYMBOL"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	header.add_child(close_button)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)
	var decisions_scroll := ScrollContainer.new()
	decisions_scroll.name = "DECISIONS_TAB"
	decisions_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(decisions_scroll)
	_decision_list = VBoxContainer.new()
	_decision_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decisions_scroll.add_child(_decision_list)
	var tree_box := VBoxContainer.new()
	tree_box.name = "FOCUS_TAB"
	_tabs.add_child(tree_box)
	_focus_header = VBoxContainer.new()
	tree_box.add_child(_focus_header)
	var tree_scroll := ScrollContainer.new()
	tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_box.add_child(tree_scroll)
	_tree_view = FocusTreeView.new()
	_tree_view.node_pressed.connect(func(node_id: String) -> void:
		_submit(FocusCommand.new(GameState.sim.player_tag, node_id)))
	tree_scroll.add_child(_tree_view)
	_tabs.tab_changed.connect(func(_tab: int) -> void: refresh())
	EventBus.locale_changed.connect(func(_locale: String) -> void: refresh())
	EventBus.day_passed.connect(func(_date: GameDate) -> void: refresh())
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
	_tabs.set_tab_title(0, tr("DECISIONS_TAB"))
	_tabs.set_tab_title(1, tr("FOCUS_TAB"))
	_clear_box(_decision_list)
	_clear_box(_focus_header)
	if country == null:
		return
	if _tabs.current_tab == 0:
		_fill_decisions(state, country)
	else:
		_fill_focus_header(state, country)
		_tree_view.show_tree(state, country)


# --- Décisions ---------------------------------------------------------------------------------------------------

func _fill_decisions(state: SimState, country: CountryState) -> void:
	var locale := Localization.get_locale()
	var today := state.date.to_day_number()
	if not country.decisions_active.is_empty():
		_decision_list.add_child(_text(tr("DECISIONS_ACTIVE"), HEADER_COLOR))
		var active: Array = country.decisions_active.keys()
		active.sort()
		for id: String in active:
			var definition: Dictionary = state.decision_definitions.get(id, {})
			var row := HBoxContainer.new()
			var label := _text(tr(str(definition.get("name_key", id))), ACTIVE_COLOR)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.tooltip_text = _effects_tooltip(definition, locale)
			label.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(label)
			var days := int(definition.get("days", 1))
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(140, 0)
			bar.max_value = PERCENT
			bar.value = (1.0 - float(int(country.decisions_active[id]) - today) / maxf(days, 1.0)) * PERCENT
			row.add_child(bar)
			row.add_child(_text(tr("DECISIONS_DAYS_LEFT") % maxi(int(country.decisions_active[id]) - today, 0), LABEL_COLOR))
			var cancel := Button.new()
			cancel.text = "DECISIONS_CANCEL"
			cancel.tooltip_text = "DECISIONS_CANCEL_TOOLTIP"
			cancel.focus_mode = Control.FOCUS_NONE
			var decision := id
			cancel.pressed.connect(func() -> void: _submit(DecisionCommand.new(state.player_tag, decision, true)))
			row.add_child(cancel)
			_decision_list.add_child(row)
	var ids: Array = state.decision_definitions.keys()
	ids.sort()
	for category: String in CATEGORIES:
		var shown := false
		for id: String in ids:
			var definition: Dictionary = state.decision_definitions[id]
			if str(definition.get("category", "")) != category or country.decisions_active.has(id) \
					or not DecisionSystem.is_visible(state, country, id):
				continue
			if not shown:
				_decision_list.add_child(_text(tr("DECISIONS_CATEGORY_%s" % category.to_upper()), HEADER_COLOR))
				shown = true
			_decision_list.add_child(_decision_row(state, country, id, definition, locale))


func _decision_row(state: SimState, country: CountryState, id: String, definition: Dictionary,
		locale: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var refusal := DecisionSystem.decision_refusal(state, country, id)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_text(tr(str(definition.get("name_key", id))), HEADER_COLOR if refusal.is_empty() else LOCKED_COLOR))
	var details := PackedStringArray()
	var cost := _cost_text(definition.get("cost", {}), locale)
	details.append(tr("DECISIONS_COST") % cost if not cost.is_empty() else tr("DECISIONS_FREE"))
	var days := int(definition.get("days", 0))
	details.append(tr("DECISIONS_DURATION") % days if days > 0 else tr("DECISIONS_IMMEDIATE"))
	if refusal == "DECISION_COOLDOWN":
		details.append(tr("DECISIONS_READY_IN") % (int(country.decision_ready[id]) - state.date.to_day_number()))
	var line := _text(" · ".join(details), LABEL_COLOR)
	info.add_child(line)
	info.tooltip_text = tr(str(definition.get("desc_key", ""))) + "\n\n" + _effects_tooltip(definition, locale)
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(info)
	var button := Button.new()
	button.text = "DECISIONS_TAKE"
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not refusal.is_empty()
	button.tooltip_text = tr(refusal) if not refusal.is_empty() else ""
	button.pressed.connect(func() -> void: _submit(DecisionCommand.new(state.player_tag, id)))
	row.add_child(button)
	return row


func _cost_text(cost: Dictionary, locale: String) -> String:
	var parts := PackedStringArray()
	for key: String in DecisionSystem.COST_KEYS:
		if cost.has(key):
			parts.append(tr("DECISIONS_COST_%s" % key.to_upper()) % NumberFormat.decimal(float(cost[key]),
				1 if not is_equal_approx(float(cost[key]), roundf(float(cost[key]))) else 0, locale))
	return ", ".join(parts)


func _effects_tooltip(definition: Dictionary, locale: String) -> String:
	var lines := ScriptEffects.describe(definition.get("on_start", {}), locale)
	lines.append_array(ScriptEffects.describe(definition.get("effects", {}), locale))
	return "\n".join(lines) if not lines.is_empty() else tr("EFFECT_NONE")


# --- Arbre -------------------------------------------------------------------------------------------------------

func _fill_focus_header(state: SimState, country: CountryState) -> void:
	var tree: Dictionary = state.focus_trees.get(country.focus_tree, {})
	_focus_header.add_child(_text(tr(str(tree.get("name_key", ""))), HEADER_COLOR))
	var row := HBoxContainer.new()
	if country.focus_current.is_empty():
		row.add_child(_text(tr("FOCUS_NONE_ACTIVE"), LABEL_COLOR))
	else:
		var node: Dictionary = DecisionSystem.tree_nodes(state, country).get(country.focus_current, {})
		var label := _text(tr(str(node.get("name_key", ""))), ACTIVE_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(180, 0)
		bar.max_value = PERCENT
		bar.value = DecisionSystem.focus_progress(state, country) * PERCENT
		row.add_child(bar)
		row.add_child(_text(tr("DECISIONS_DAYS_LEFT") % maxi(country.focus_end_day - state.date.to_day_number(), 0),
			LABEL_COLOR))
		var cancel := Button.new()
		cancel.text = "FOCUS_CANCEL"
		cancel.tooltip_text = "FOCUS_CANCEL_TOOLTIP"
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.pressed.connect(func() -> void: _submit(FocusCommand.new(state.player_tag, "")))
		row.add_child(cancel)
	_focus_header.add_child(row)


# --- Outils ------------------------------------------------------------------------------------------------------

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


## Graphe de l'arbre : un bouton par nœud placé selon (x, y), traits vers les prérequis (pointillés pour
## « au moins un »).
class FocusTreeView extends Control:
	signal node_pressed(node_id: String)

	const NODE_SIZE := Vector2(132, 58)
	const STEP := Vector2(70, 100)
	const PADDING := 12.0
	const LINE_COLOR := Color(0.45, 0.52, 0.62)
	const LINE_WIDTH := 2.0
	const DASH := 6.0

	var _centers: Dictionary = {}
	var _links: Array = []

	func show_tree(state: SimState, country: CountryState) -> void:
		for child: Node in get_children():
			remove_child(child)
			child.queue_free()
		_centers.clear()
		_links.clear()
		var nodes := DecisionSystem.tree_nodes(state, country)
		var extent := Vector2.ZERO
		var locale := Localization.get_locale()
		var ids: Array = nodes.keys()
		ids.sort()
		for id: String in ids:
			var node: Dictionary = nodes[id]
			var origin := Vector2(PADDING + float(node.get("x", 0.0)) * STEP.x,
				PADDING + float(node.get("y", 0.0)) * STEP.y)
			_centers[id] = origin + NODE_SIZE / 2.0
			extent = extent.max(origin + NODE_SIZE)
			for required: Variant in node.get("requires", []):
				_links.append([str(required), id, false])
			for required: Variant in node.get("requires_any", []):
				_links.append([str(required), id, true])
			add_child(_node_button(state, country, id, node, origin, locale))
		custom_minimum_size = extent + Vector2(PADDING, PADDING)
		queue_redraw()

	func _node_button(state: SimState, country: CountryState, id: String, node: Dictionary, origin: Vector2,
			locale: String) -> Button:
		var button := Button.new()
		button.position = origin
		button.size = NODE_SIZE
		button.custom_minimum_size = NODE_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.clip_text = true
		button.text = "%s\n%s" % [tr(str(node.get("name_key", id))), tr("FOCUS_MONTHS") % int(node.get("months", 0))]
		var refusal := DecisionSystem.focus_refusal(state, country, id)
		var color := HEADER_COLOR
		if country.focus_done.has(id):
			color = DONE_COLOR
		elif country.focus_current == id:
			color = ACTIVE_COLOR
		elif refusal == "FOCUS_EXCLUDED":
			color = EXCLUDED_COLOR
		elif not refusal.is_empty() and refusal != "FOCUS_BUSY":
			color = LOCKED_COLOR
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_disabled_color", color)
		button.disabled = not refusal.is_empty()
		var lines := PackedStringArray([tr(str(node.get("desc_key", "")))])
		var effects := ScriptEffects.describe(node.get("effects", {}), locale)
		if not effects.is_empty():
			lines.append("")
			lines.append_array(effects)
		if not refusal.is_empty() and refusal != "FOCUS_DONE":
			lines.append("")
			lines.append(tr(refusal))
		button.tooltip_text = "\n".join(lines)
		button.pressed.connect(func() -> void: node_pressed.emit(id))
		return button

	func _draw() -> void:
		for link: Array in _links:
			if not _centers.has(link[0]) or not _centers.has(link[1]):
				continue
			var from: Vector2 = _centers[link[0]] + Vector2(0, NODE_SIZE.y / 2.0)
			var to: Vector2 = _centers[link[1]] - Vector2(0, NODE_SIZE.y / 2.0)
			if bool(link[2]):
				draw_dashed_line(from, to, LINE_COLOR, LINE_WIDTH, DASH)
			else:
				draw_line(from, to, LINE_COLOR, LINE_WIDTH)

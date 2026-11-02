class_name EventEditor
extends Control
## Éditeur d'événements pour les moddeurs : à gauche le mod et la liste des événements (ceux du mod, modifiables,
## puis ceux du jeu, en lecture seule et duplicables) ; au centre la fiche de l'événement (réglages, textes FR/EN,
## déclencheur et effets en JSON, choix) ; à droite l'aide (modèles de conditions et d'effets à insérer), les
## erreurs en direct, l'aperçu, l'essai dans une partie de test et l'enregistrement dans le mod.

const TITLE_SCENE := "res://ui/title/title_screen.tscn"
const LEFT_WIDTH := 300.0
const RIGHT_WIDTH := 300.0
const JSON_HEIGHT := 70.0
const DESC_HEIGHT := 60.0
const VALIDATION_DELAY := 0.4
const MOD_MARK := "★ "
const ERROR_COLOR := Color(0.95, 0.45, 0.45)
const OK_COLOR := Color(0.55, 0.85, 0.55)
const LABEL_COLOR := Color(0.62, 0.68, 0.76)
const BACKGROUND := Color(0.06, 0.08, 0.11)
const NEW_ID := "new_event"
const COPY_SUFFIX := "_copy"
const TEST_SEED := 1

var mods_dir: String = ModManager.MODS_DIR
var _mods: Array[Dictionary] = []
var _mod_path: String = ""
var _mod_events: Dictionary = {}
var _mod_texts: Dictionary = {}
var _current_id: String = ""
var _loading: bool = false
var _list_ids: Array[String] = []
var _templates: Dictionary = {}
var _focused_json: TextEdit = null
var _validation_timer: Timer

var _mod_option: OptionButton
var _filter: LineEdit
var _event_list: ItemList
var _form: VBoxContainer
var _id_edit: LineEdit
var _scope_option: OptionButton
var _mtth_spin: SpinBox
var _once_check: CheckBox
var _triggered_check: CheckBox
var _action_option: OptionButton
var _action_scope_option: OptionButton
var _action_chance_spin: SpinBox
var _title_edits: Dictionary = {}
var _desc_edits: Dictionary = {}
var _trigger_edit: TextEdit
var _mtth_modifiers_edit: TextEdit
var _immediate_edit: TextEdit
var _news_edit: TextEdit
var _options_tabs: TabContainer
var _errors_label: RichTextLabel
var _test_tag: LineEdit
var _test_option: SpinBox
var _status_label: Label


func _ready() -> void:
	_templates = DataLoader.get_category("editor")
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	margin.add_child(columns)
	columns.add_child(_build_left())
	columns.add_child(_build_center())
	columns.add_child(_build_right())
	_validation_timer = Timer.new()
	_validation_timer.one_shot = true
	_validation_timer.wait_time = VALIDATION_DELAY
	_validation_timer.timeout.connect(_validate)
	add_child(_validation_timer)
	_refresh_mods()
	_refresh_list()
	_show_event("")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


# --- Construction ------------------------------------------------------------------------------------------------

func _build_left() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	box.add_child(_heading("EDITOR_TITLE"))
	var mod_row := HBoxContainer.new()
	_mod_option = OptionButton.new()
	_mod_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mod_option.item_selected.connect(func(_index: int) -> void: _select_mod())
	mod_row.add_child(_mod_option)
	mod_row.add_child(_button("EDITOR_NEW_MOD", _new_mod))
	box.add_child(mod_row)
	_filter = LineEdit.new()
	_filter.placeholder_text = "EDITOR_FILTER"
	_filter.text_changed.connect(func(_text: String) -> void: _refresh_list())
	box.add_child(_filter)
	_event_list = ItemList.new()
	_event_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_event_list.item_selected.connect(func(index: int) -> void: _show_event(_list_ids[index]))
	box.add_child(_event_list)
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("EDITOR_NEW_EVENT", _new_event))
	buttons.add_child(_button("EDITOR_DUPLICATE", _duplicate_event))
	buttons.add_child(_button("EDITOR_DELETE", _delete_event))
	box.add_child(buttons)
	box.add_child(_button("EDITOR_BACK", _back))
	return box


func _build_center() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)
	var grid := GridContainer.new()
	grid.columns = 4
	_form.add_child(grid)
	_id_edit = LineEdit.new()
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_edit.text_submitted.connect(func(_text: String) -> void: _rename_current())
	_id_edit.focus_exited.connect(_rename_current)
	_add_field(grid, "EDITOR_ID", _id_edit)
	_scope_option = OptionButton.new()
	for scope: String in ["country", "world"]:
		_scope_option.add_item(tr("EDITOR_SCOPE_%s" % scope.to_upper()))
	_scope_option.item_selected.connect(func(_index: int) -> void: _changed())
	_add_field(grid, "EDITOR_SCOPE", _scope_option)
	_mtth_spin = _spin(0.0, 10000.0, 1.0)
	_add_field(grid, "EDITOR_MTTH", _mtth_spin)
	_once_check = _check("EDITOR_ONCE")
	_triggered_check = _check("EDITOR_TRIGGERED_ONLY")
	var checks := HBoxContainer.new()
	checks.add_child(_once_check)
	checks.add_child(_triggered_check)
	_add_field(grid, "EDITOR_FLAGS", checks)
	_action_option = OptionButton.new()
	_action_option.add_item(tr("EDITOR_NO_ACTION"))
	for action: String in EventSystem.ACTION_TYPES:
		_action_option.add_item(action)
	_action_option.item_selected.connect(func(_index: int) -> void: _changed())
	_add_field(grid, "EDITOR_ON_ACTION", _action_option)
	_action_scope_option = OptionButton.new()
	for action_scope: String in [EventSystem.ACTOR, EventSystem.OTHERS]:
		_action_scope_option.add_item(tr("EDITOR_ACTION_SCOPE_%s" % action_scope.to_upper()))
	_action_scope_option.item_selected.connect(func(_index: int) -> void: _changed())
	_add_field(grid, "EDITOR_ACTION_SCOPE", _action_scope_option)
	_action_chance_spin = _spin(0.0, 1.0, 0.05)
	_add_field(grid, "EDITOR_ACTION_CHANCE", _action_chance_spin)
	for locale: String in EventModStore.LOCALES:
		_title_edits[locale] = _line()
		_form.add_child(_labelled("EDITOR_TITLE_%s" % locale.to_upper(), _title_edits[locale]))
		_desc_edits[locale] = _text_edit(DESC_HEIGHT)
		_form.add_child(_labelled("EDITOR_DESC_%s" % locale.to_upper(), _desc_edits[locale]))
	_trigger_edit = _json_edit()
	_form.add_child(_labelled("EDITOR_TRIGGER", _trigger_edit))
	_mtth_modifiers_edit = _json_edit()
	_form.add_child(_labelled("EDITOR_MTTH_MODIFIERS", _mtth_modifiers_edit))
	_immediate_edit = _json_edit()
	_form.add_child(_labelled("EDITOR_IMMEDIATE", _immediate_edit))
	_news_edit = _json_edit()
	_form.add_child(_labelled("EDITOR_NEWS", _news_edit))
	var option_row := HBoxContainer.new()
	option_row.add_child(_heading("EDITOR_OPTIONS"))
	option_row.add_child(_button("EDITOR_ADD_OPTION", _add_option))
	option_row.add_child(_button("EDITOR_REMOVE_OPTION", _remove_option))
	_form.add_child(option_row)
	_options_tabs = TabContainer.new()
	_form.add_child(_options_tabs)
	return scroll


func _build_right() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
	box.add_child(_heading("EDITOR_HELP"))
	box.add_child(_template_list("conditions", "EDITOR_CONDITIONS"))
	box.add_child(_template_list("effects", "EDITOR_EFFECTS"))
	box.add_child(_heading("EDITOR_ERRORS"))
	_errors_label = RichTextLabel.new()
	_errors_label.custom_minimum_size = Vector2(0, 120)
	_errors_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_errors_label.fit_content = false
	box.add_child(_errors_label)
	box.add_child(_button("EDITOR_PREVIEW", _preview))
	var test_row := HBoxContainer.new()
	_test_tag = LineEdit.new()
	_test_tag.text = "FRA"
	_test_tag.custom_minimum_size = Vector2(60, 0)
	_test_tag.tooltip_text = "EDITOR_TEST_COUNTRY"
	test_row.add_child(_test_tag)
	_test_option = _spin(1.0, EventModStore.MAX_OPTIONS, 1.0)
	_test_option.tooltip_text = "EDITOR_TEST_OPTION"
	test_row.add_child(_test_option)
	test_row.add_child(_button("EDITOR_TEST", _test))
	box.add_child(test_row)
	box.add_child(_button("EDITOR_SAVE", _save))
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", LABEL_COLOR)
	box.add_child(_status_label)
	return box


func _template_list(kind: String, title: String) -> Control:
	var box := VBoxContainer.new()
	box.add_child(_small(title))
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 150)
	var templates: Dictionary = _templates.get(kind, {})
	var keys: Array = templates.keys()
	keys.sort()
	for key: Variant in keys:
		var index := list.add_item(str(key))
		list.set_item_tooltip(index, JSON.stringify(templates[key]))
	list.item_activated.connect(func(index: int) -> void:
		var key := list.get_item_text(index)
		_insert_template(key, templates[key]))
	box.add_child(list)
	return box


# --- Mods et liste -----------------------------------------------------------------------------------------------

func _refresh_mods() -> void:
	_mods = EventModStore.list_mods(mods_dir)
	_mod_option.clear()
	for mod: Dictionary in _mods:
		_mod_option.add_item(str(mod["name"]))
	if _mods.is_empty():
		_mod_option.add_item(tr("EDITOR_NO_MOD"))
		_mod_option.disabled = true
	else:
		_mod_option.disabled = false
		_mod_option.select(0)
	_select_mod()


func _select_mod() -> void:
	if _mods.is_empty():
		_mod_path = ""
		_mod_events = {}
		_mod_texts = {}
	else:
		_mod_path = str(_mods[maxi(_mod_option.selected, 0)]["path"])
		_mod_events = EventModStore.load_events(_mod_path)
		_mod_texts = EventModStore.load_texts(_mod_path)
	_refresh_list()


func _new_mod() -> void:
	var index := _mods.size() + 1
	var mod_id := "my_mod_%d" % index
	while DirAccess.dir_exists_absolute(mods_dir.path_join(mod_id)):
		index += 1
		mod_id = "my_mod_%d" % index
	EventModStore.create_mod(mods_dir, mod_id, tr("EDITOR_NEW_MOD_NAME") % index)
	_refresh_mods()
	_mod_option.select(_mods.size() - 1)
	_select_mod()
	_status(tr("EDITOR_MOD_CREATED") % mods_dir.path_join(mod_id))


func _refresh_list() -> void:
	_event_list.clear()
	_list_ids.clear()
	var filter := _filter.text.strip_edges().to_lower()
	var mod_ids: Array = _mod_events.keys()
	mod_ids.sort()
	for id: Variant in mod_ids:
		if filter.is_empty() or str(id).contains(filter):
			_event_list.add_item(MOD_MARK + str(id))
			_list_ids.append(str(id))
	var game_ids: Array = DataLoader.get_category("events").keys()
	game_ids.sort()
	for id: Variant in game_ids:
		if not _mod_events.has(id) and (filter.is_empty() or str(id).contains(filter)):
			_event_list.add_item(str(id))
			_list_ids.append(str(id))


# --- Fiche -------------------------------------------------------------------------------------------------------

func _definition_of(id: String) -> Dictionary:
	if _mod_events.has(id):
		return _mod_events[id]
	return DataLoader.get_category("events").get(id, {})


func _text_of(key: String, locale: String) -> String:
	if _mod_texts.has(key):
		return str((_mod_texts[key] as Dictionary).get(locale, ""))
	var text := Localization.get_message_in(locale, key)
	return text if text != key else ""


func _show_event(id: String) -> void:
	_loading = true
	_current_id = id
	var definition := _definition_of(id)
	var editable := _mod_events.has(id)
	_set_editable(editable)
	_id_edit.text = id
	_scope_option.select(1 if str(definition.get("scope", "country")) == EventSystem.SCOPE_WORLD else 0)
	_mtth_spin.value = float(definition.get("mtth_months", 0.0))
	_once_check.button_pressed = bool(definition.get("once", false))
	_triggered_check.button_pressed = bool(definition.get("triggered_only", false))
	var action := str(definition.get("on_action", ""))
	_action_option.select(EventSystem.ACTION_TYPES.find(action) + 1)
	_action_scope_option.select(1 if str(definition.get("action_scope", EventSystem.ACTOR)) == EventSystem.OTHERS else 0)
	_action_chance_spin.value = float(definition.get("action_chance", 1.0))
	for locale: String in EventModStore.LOCALES:
		(_title_edits[locale] as LineEdit).text = _text_of(str(definition.get("title_key", "")), locale)
		(_desc_edits[locale] as TextEdit).text = _text_of(str(definition.get("desc_key", "")), locale)
	_trigger_edit.text = _to_json(definition.get("trigger", {}))
	_mtth_modifiers_edit.text = _to_json(definition.get("mtth_modifiers", []))
	_immediate_edit.text = _to_json(definition.get("immediate", {}))
	_news_edit.text = _to_json(definition.get("news", null))
	for child: Node in _options_tabs.get_children():
		_options_tabs.remove_child(child)
		child.queue_free()
	var options: Array = definition.get("options", [])
	for index: int in options.size():
		_add_option_tab(options[index], index)
	_set_editable(editable)
	_loading = false
	_validate()


func _add_option_tab(option: Dictionary, index: int) -> void:
	var box := VBoxContainer.new()
	box.name = tr("EDITOR_OPTION") % (index + 1)
	for locale: String in EventModStore.LOCALES:
		var edit := _line()
		edit.name = "Name_" + locale
		edit.text = _text_of(str(option.get("name_key", "")), locale)
		box.add_child(_labelled("EDITOR_OPTION_NAME_%s" % locale.to_upper(), edit))
	var effects := _json_edit()
	effects.name = "Effects"
	effects.text = _to_json(option.get("effects", {}))
	box.add_child(_labelled("EDITOR_OPTION_EFFECTS", effects))
	var weight := _spin(0.0, 100.0, 0.1)
	weight.name = "Weight"
	weight.value = float(option.get("ai_weight", 1.0))
	box.add_child(_labelled("EDITOR_OPTION_AI_WEIGHT", weight))
	var modifiers := _json_edit()
	modifiers.name = "Modifiers"
	modifiers.text = _to_json(option.get("ai_modifiers", []))
	box.add_child(_labelled("EDITOR_OPTION_AI_MODIFIERS", modifiers))
	_options_tabs.add_child(box)


func _set_editable(editable: bool) -> void:
	for control: Control in _form.find_children("*", "Control", true, false):
		if control is LineEdit:
			(control as LineEdit).editable = editable
		elif control is TextEdit:
			(control as TextEdit).editable = editable
		elif control is BaseButton:
			(control as BaseButton).disabled = not editable
		elif control is SpinBox:
			(control as SpinBox).editable = editable
		elif control is OptionButton:
			(control as OptionButton).disabled = not editable


## Relit la fiche dans la définition et les textes du mod.
func _collect() -> void:
	if _loading or not _mod_events.has(_current_id):
		return
	var id := _current_id
	var definition: Dictionary = (_mod_events[id] as Dictionary).duplicate(true)
	var keys := EventModStore.text_keys(id, _options_tabs.get_child_count())
	definition["title_key"] = str(definition.get("title_key", keys[0]))
	definition["desc_key"] = str(definition.get("desc_key", keys[1]))
	definition["scope"] = "world" if _scope_option.selected == 1 else "country"
	_set_or_erase(definition, "mtth_months", _mtth_spin.value if _mtth_spin.value > 0.0 else null)
	_set_or_erase(definition, "once", true if _once_check.button_pressed else null)
	_set_or_erase(definition, "triggered_only", true if _triggered_check.button_pressed else null)
	var action_index := _action_option.selected - 1
	_set_or_erase(definition, "on_action", EventSystem.ACTION_TYPES[action_index] if action_index >= 0 else null)
	_set_or_erase(definition, "action_scope", EventSystem.OTHERS if action_index >= 0 and _action_scope_option.selected == 1
		else null)
	_set_or_erase(definition, "action_chance", _action_chance_spin.value if action_index >= 0
		and _action_chance_spin.value < 1.0 else null)
	_set_or_erase(definition, "trigger", _parse(_trigger_edit.text))
	_set_or_erase(definition, "mtth_modifiers", _parse(_mtth_modifiers_edit.text))
	_set_or_erase(definition, "immediate", _parse(_immediate_edit.text))
	_set_or_erase(definition, "news", _parse(_news_edit.text))
	for locale: String in EventModStore.LOCALES:
		_set_text(str(definition["title_key"]), locale, (_title_edits[locale] as LineEdit).text)
		_set_text(str(definition["desc_key"]), locale, (_desc_edits[locale] as TextEdit).text)
	var options: Array = []
	var old_options: Array = definition.get("options", [])
	for index: int in _options_tabs.get_child_count():
		var box := _options_tabs.get_child(index)
		var name_key := str((old_options[index] as Dictionary).get("name_key", keys[2 + index])) \
			if index < old_options.size() else keys[2 + index]
		var option := {"name_key": name_key, "effects": _parse((box.find_child("Effects", true, false) as TextEdit).text)}
		if option["effects"] == null:
			option["effects"] = {}
		option["ai_weight"] = (box.find_child("Weight", true, false) as SpinBox).value
		var modifiers: Variant = _parse((box.find_child("Modifiers", true, false) as TextEdit).text)
		if modifiers is Array and not (modifiers as Array).is_empty():
			option["ai_modifiers"] = modifiers
		for locale: String in EventModStore.LOCALES:
			_set_text(name_key, locale, (box.find_child("Name_" + locale, true, false) as LineEdit).text)
		options.append(option)
	_set_or_erase(definition, "options", options if not options.is_empty() else null)
	_mod_events[id] = definition


func _changed() -> void:
	if _loading:
		return
	_collect()
	_validation_timer.start()


func _set_text(key: String, locale: String, text: String) -> void:
	if not _mod_texts.has(key):
		_mod_texts[key] = {}
	(_mod_texts[key] as Dictionary)[locale] = text


static func _set_or_erase(definition: Dictionary, key: String, value: Variant) -> void:
	if value == null or (value is Dictionary and (value as Dictionary).is_empty() and key != "trigger") \
			or (value is Array and (value as Array).is_empty()):
		definition.erase(key)
	else:
		definition[key] = value


## JSON d'une zone de texte (null si vide ou illisible : l'erreur est signalée par la validation).
func _parse(text: String) -> Variant:
	if text.strip_edges().is_empty():
		return null
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func _to_json(value: Variant) -> String:
	if value == null or (value is Dictionary and (value as Dictionary).is_empty()) \
			or (value is Array and (value as Array).is_empty()):
		return ""
	return JSON.stringify(value, "  ", false)


# --- Actions -----------------------------------------------------------------------------------------------------

func _new_event() -> void:
	if _mod_path.is_empty():
		_status(tr("EDITOR_NEED_MOD"))
		return
	var id := NEW_ID
	var index := 1
	while _mod_events.has(id) or DataLoader.get_category("events").has(id):
		index += 1
		id = "%s_%d" % [NEW_ID, index]
	_mod_events[id] = EventModStore.new_event(id)
	_refresh_list()
	_select_in_list(id)


func _duplicate_event() -> void:
	if _mod_path.is_empty() or _current_id.is_empty():
		_status(tr("EDITOR_NEED_MOD"))
		return
	var id := _current_id + COPY_SUFFIX
	while _mod_events.has(id):
		id += COPY_SUFFIX
	var definition: Dictionary = _definition_of(_current_id).duplicate(true)
	var keys := EventModStore.text_keys(id, (definition.get("options", []) as Array).size())
	for locale: String in EventModStore.LOCALES:
		_set_text(keys[0], locale, _text_of(str(definition.get("title_key", "")), locale))
		_set_text(keys[1], locale, _text_of(str(definition.get("desc_key", "")), locale))
	definition["title_key"] = keys[0]
	definition["desc_key"] = keys[1]
	var options: Array = definition.get("options", [])
	for index: int in options.size():
		var option: Dictionary = options[index]
		for locale: String in EventModStore.LOCALES:
			_set_text(keys[2 + index], locale, _text_of(str(option.get("name_key", "")), locale))
		option["name_key"] = keys[2 + index]
	_mod_events[id] = definition
	_refresh_list()
	_select_in_list(id)


func _delete_event() -> void:
	if not _mod_events.has(_current_id):
		return
	_mod_events.erase(_current_id)
	_refresh_list()
	_show_event("")


func _rename_current() -> void:
	var new_id := _id_edit.text.strip_edges()
	if _loading or not _mod_events.has(_current_id) or new_id == _current_id or new_id.is_empty() \
			or _mod_events.has(new_id):
		return
	_mod_events[new_id] = _mod_events[_current_id]
	_mod_events.erase(_current_id)
	_current_id = new_id
	_refresh_list()
	_select_in_list(new_id)


func _add_option() -> void:
	if not _mod_events.has(_current_id) or _options_tabs.get_child_count() >= EventModStore.MAX_OPTIONS:
		return
	_add_option_tab({}, _options_tabs.get_child_count())
	_changed()


func _remove_option() -> void:
	if not _mod_events.has(_current_id) or _options_tabs.get_child_count() == 0:
		return
	var last := _options_tabs.get_child(_options_tabs.get_child_count() - 1)
	_options_tabs.remove_child(last)
	last.queue_free()
	_changed()


func _insert_template(key: String, value: Variant) -> void:
	var target := _focused_json if _focused_json != null and is_instance_valid(_focused_json) else _trigger_edit
	if not target.editable:
		return
	var entry := "\"%s\": %s" % [key, JSON.stringify(value)]
	# Champ vide : on crée l'objet complet ; sinon on insère la paire à l'endroit du curseur.
	if target.text.strip_edges().is_empty():
		target.text = "{%s}" % entry
	else:
		target.insert_text_at_caret(entry)
	_changed()


func _validate() -> void:
	if _current_id.is_empty():
		_errors_label.text = ""
		return
	var errors := PackedStringArray()
	if _mod_events.has(_current_id):
		for edit: TextEdit in _json_edits():
			if not edit.text.strip_edges().is_empty() and _parse(edit.text) == null:
				errors.append(tr("EDITOR_ERROR_JSON"))
				break
	var known := DataLoader.get_category("events").duplicate()
	known.merge(_mod_events, true)
	errors.append_array(EventModStore.validate(_current_id, _definition_of(_current_id), known, _mod_texts,
		(DataLoader.get_category("schemas") as Dictionary).get("events", {}), DataLoader.repository))
	_errors_label.clear()
	if errors.is_empty():
		_errors_label.push_color(OK_COLOR)
		_errors_label.add_text(tr("EDITOR_NO_ERROR"))
	else:
		_errors_label.push_color(ERROR_COLOR)
		_errors_label.add_text("\n".join(errors))
	_errors_label.pop()


func _json_edits() -> Array[TextEdit]:
	var edits: Array[TextEdit] = [_trigger_edit, _mtth_modifiers_edit, _immediate_edit, _news_edit]
	for box: Node in _options_tabs.get_children():
		edits.append(box.find_child("Effects", true, false) as TextEdit)
		edits.append(box.find_child("Modifiers", true, false) as TextEdit)
	return edits


func _preview() -> void:
	if _current_id.is_empty():
		return
	var definition := _definition_of(_current_id)
	var locale := Localization.get_locale().substr(0, 2)
	var dialog := AcceptDialog.new()
	dialog.title = _text_of(str(definition.get("title_key", "")), locale)
	var lines := PackedStringArray([_text_of(str(definition.get("desc_key", "")), locale), ""])
	for option: Variant in definition.get("options", []):
		lines.append("▸ " + _text_of(str((option as Dictionary).get("name_key", "")), locale))
		for effect: String in ScriptEffects.describe((option as Dictionary).get("effects", {}), Localization.get_locale()):
			lines.append("      " + effect)
	dialog.dialog_text = "\n".join(lines)
	add_child(dialog)
	dialog.popup_centered(Vector2i(560, 0))


## Essai dans une partie de test (créée une fois) : le pays et le choix sont pris dans les champs.
func _test() -> void:
	if _current_id.is_empty():
		return
	_status(tr("EDITOR_TEST_PREPARING"))
	await get_tree().process_frame
	if GameState.sim.countries.is_empty() or not GameState.sim.player_tag.is_empty():
		GameState.new_game(TEST_SEED, &"")
	var tag := _test_tag.text.strip_edges().to_upper()
	var report := EventTester.run(GameState.sim, _current_id, _definition_of(_current_id), tag, int(_test_option.value) - 1)
	var lines := PackedStringArray()
	if not str(report["error"]).is_empty():
		lines.append(tr(str(report["error"])))
	else:
		lines.append(tr("EDITOR_TEST_TRIGGER_TRUE" if bool(report["trigger"]) else "EDITOR_TEST_TRIGGER_FALSE") % tag)
		lines.append(tr("EDITOR_TEST_CHANCE") % NumberFormat.decimal(float(report["chance"]), 2, Localization.get_locale()))
		var before: Dictionary = report["before"]
		var after: Dictionary = report["after"]
		for key: String in EventTester.WATCHED:
			var delta := float(after.get(key, 0.0)) - float(before.get(key, 0.0))
			if not is_zero_approx(delta):
				lines.append("%s : %s → %s" % [tr("EDITOR_VALUE_%s" % key.to_upper()),
					NumberFormat.decimal(float(before[key]), 1, Localization.get_locale()),
					NumberFormat.decimal(float(after[key]), 1, Localization.get_locale())])
		if (report["events"] as Array).size() > 0:
			lines.append(tr("EDITOR_TEST_EVENTS") % ", ".join(PackedStringArray(report["events"])))
	var dialog := AcceptDialog.new()
	dialog.title = tr("EDITOR_TEST_TITLE")
	dialog.dialog_text = "\n".join(lines)
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 0))
	_status("")


func _save() -> void:
	if _mod_path.is_empty():
		_status(tr("EDITOR_NEED_MOD"))
		return
	_collect()
	EventModStore.save(_mod_path, _mod_events, _mod_texts)
	_status(tr("EDITOR_SAVED") % _mod_path)


func _back() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _select_in_list(id: String) -> void:
	var index := _list_ids.find(id)
	if index >= 0:
		_event_list.select(index)
	_show_event(id)


func _status(text: String) -> void:
	_status_label.text = text


# --- Petits outils -----------------------------------------------------------------------------------------------

func _heading(key: String) -> Label:
	var label := Label.new()
	label.text = key
	label.add_theme_font_size_override("font_size", 18)
	return label


func _small(key: String) -> Label:
	var label := Label.new()
	label.text = key
	label.add_theme_color_override("font_color", LABEL_COLOR)
	return label


func _button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = key
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _spin(min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value_changed.connect(func(_value: float) -> void: _changed())
	return spin


func _check(key: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = key
	check.toggled.connect(func(_pressed: bool) -> void: _changed())
	return check


func _line() -> LineEdit:
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(_text: String) -> void: _changed())
	return edit


func _text_edit(height: float) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, height)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.text_changed.connect(_changed)
	return edit


func _json_edit() -> TextEdit:
	var edit := _text_edit(JSON_HEIGHT)
	edit.focus_entered.connect(func() -> void: _focused_json = edit)
	return edit


func _labelled(key: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_child(_small(key))
	box.add_child(control)
	return box


func _add_field(grid: GridContainer, key: String, control: Control) -> void:
	grid.add_child(_small(key))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)

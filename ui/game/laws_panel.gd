class_name LawsPanel
extends InfoPanel
## Panneau Lois du pays joué : lois par catégorie, option en vigueur, proposition d'une autre option avec
## aperçu du vote de la chambre et des effets attendus.

const LAW_COLUMNS := 3
const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const PASS_COLOR := Color(0.55, 0.85, 0.55)
const FAIL_COLOR := Color(0.95, 0.5, 0.45)
const COOLDOWN_COLOR := Color(0.45, 0.51, 0.6)
const EFFECT_KEYS := ["stability", "growth", "legitimacy", "corruption", "budget"]
## Effets dont une hausse est mauvaise.
const INVERTED_EFFECTS := ["corruption", "budget"]
const CATEGORIES := ["justice", "society", "freedoms", "security", "immigration", "labour", "economy",
	"health_education", "environment", "governance"]

## Loi choisie et option proposée.
var _law_id: String = ""
var _option_ids: Array[String] = []

@onready var _category_option: OptionButton = %CategoryOption
@onready var _laws_grid: GridContainer = %LawsGrid
@onready var _law_title: Label = %LawTitle
@onready var _proposal_option: OptionButton = %ProposalOption
@onready var _propose_button: Button = %ProposeButton
@onready var _preview_label: Label = %PreviewLabel
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_laws_grid.columns = LAW_COLUMNS
	for category: String in CATEGORIES:
		_category_option.add_item("LAW_CATEGORY_%s" % category.to_upper())
	_category_option.item_selected.connect(func(_index: int) -> void:
		_law_id = ""
		refresh())
	_proposal_option.item_selected.connect(func(_index: int) -> void: _update_preview())
	_propose_button.pressed.connect(_on_propose_pressed)
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
	_clear_rows(_laws_grid)
	var state := GameState.sim
	var country := state.get_country(str(state.player_tag))
	if country == null or country.laws.is_empty():
		return
	var laws: Dictionary = state.politics_definitions.get("laws", {})
	var category: String = CATEGORIES[maxi(_category_option.selected, 0)]
	for key: String in ["LAWS_LAW", "LAWS_CURRENT", ""]:
		var header := Label.new()
		header.text = key
		header.add_theme_color_override("font_color", HEADER_COLOR)
		_laws_grid.add_child(header)
	for law_id: String in laws.keys():
		var definition: Dictionary = laws[law_id]
		if str(definition["category"]) != category:
			continue
		if _law_id.is_empty():
			_law_id = law_id
		var name_label := Label.new()
		name_label.text = str(definition["name_key"])
		name_label.add_theme_color_override("font_color", LABEL_COLOR)
		_laws_grid.add_child(name_label)
		var current := Label.new()
		current.text = str(LawModel.option_of(definition, str(country.laws[law_id])).get("name_key", ""))
		var cooldown := int(country.law_cooldowns.get(law_id, 0))
		if cooldown > 0:
			current.add_theme_color_override("font_color", COOLDOWN_COLOR)
			current.tooltip_text = tr("LAWS_COOLDOWN_VALUE") % cooldown
			current.mouse_filter = Control.MOUSE_FILTER_STOP
		_laws_grid.add_child(current)
		var select := Button.new()
		select.text = "LAWS_CHANGE"
		select.focus_mode = Control.FOCUS_NONE
		select.disabled = law_id == _law_id
		select.pressed.connect(func() -> void:
			_law_id = law_id
			refresh())
		_laws_grid.add_child(select)
	_fill_proposal(country, laws)


func _fill_proposal(country: CountryState, laws: Dictionary) -> void:
	var definition: Dictionary = laws.get(_law_id, {})
	_law_title.text = str(definition.get("name_key", ""))
	var previous := _option_ids[_proposal_option.selected] if _proposal_option.selected >= 0 \
		and _proposal_option.selected < _option_ids.size() else ""
	_proposal_option.clear()
	_option_ids.clear()
	for option: Dictionary in definition.get("options", []):
		if str(option["id"]) == str(country.laws.get(_law_id, "")):
			continue
		_option_ids.append(str(option["id"]))
		_proposal_option.add_item(tr(str(option["name_key"])))
	var index := _option_ids.find(previous)
	_proposal_option.select(index if index >= 0 else 0)
	_update_preview()


## Vote attendu et effets du changement par rapport à l'option en vigueur.
func _update_preview() -> void:
	var state := GameState.sim
	var country := state.get_country(str(state.player_tag))
	if country == null or _proposal_option.selected < 0 or _option_ids.is_empty():
		_preview_label.text = ""
		_propose_button.disabled = true
		return
	var option_id := _option_ids[_proposal_option.selected]
	var command := ChangeLawCommand.new(state.player_tag, _law_id, option_id)
	var refusal := command.refusal_reason(state)
	_propose_button.disabled = not refusal.is_empty()
	_propose_button.tooltip_text = tr(refusal) if not refusal.is_empty() else ""
	var lines: PackedStringArray = []
	var result: Variant = ChangeLawCommand.expected_vote(state, country, _law_id, option_id)
	if result == null:
		lines.append(tr("LAWS_DECREE"))
		_preview_label.remove_theme_color_override("font_color")
	else:
		var vote: Dictionary = result
		lines.append(tr("LAWS_VOTE_VALUE") % [vote["yes"], vote["no"], vote["required"]])
		lines.append(tr("LAWS_PASSES" if bool(vote["passed"]) else "LAWS_FAILS"))
		_preview_label.add_theme_color_override("font_color", PASS_COLOR if bool(vote["passed"]) else FAIL_COLOR)
	var definition: Dictionary = (state.politics_definitions.get("laws", {}) as Dictionary).get(_law_id, {})
	var effects := LawModel.aggregate({_law_id: definition}, {_law_id: option_id}, {_law_id: country.laws[_law_id]})
	lines.append(_effects_text(effects))
	_preview_label.text = "\n".join(lines)


func _effects_text(effects: Dictionary) -> String:
	var locale := Localization.get_locale()
	var parts: PackedStringArray = []
	for key: String in EFFECT_KEYS:
		var value := float(effects.get(key, 0.0))
		if not is_zero_approx(value):
			parts.append("%s %s%s" % [tr("LAWS_EFFECT_%s" % key.to_upper()), "+" if value > 0.0 else "",
				NumberFormat.decimal(value, 2, locale)])
	var groups := DataLoader.get_category("social_groups")
	var law_groups: Dictionary = effects.get(LawModel.GROUPS, {})
	for group_id: String in groups.keys():
		var value := float(law_groups.get(group_id, 0.0))
		if not is_zero_approx(value):
			parts.append("%s %s%s" % [tr(str(groups[group_id]["name_key"])), "+" if value > 0.0 else "",
				NumberFormat.decimal(value, 0, locale)])
	return tr("LAWS_EFFECTS_VALUE") % (", ".join(parts) if not parts.is_empty() else tr("LAWS_NO_EFFECT"))


func _on_propose_pressed() -> void:
	if _proposal_option.selected < 0 or _option_ids.is_empty():
		return
	var command := ChangeLawCommand.new(GameState.sim.player_tag, _law_id, _option_ids[_proposal_option.selected])
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()

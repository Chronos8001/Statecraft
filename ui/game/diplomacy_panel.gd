class_name DiplomacyPanel
extends InfoPanel
## Panneau Diplomatie avec un pays : relations, traités en vigueur (rupture possible), actions
## diplomatiques, proposition de traité avec l'avis probable du pays, et guerre (section WarSection).

const GOOD_COLOR := Color(0.55, 0.85, 0.55)
const BAD_COLOR := Color(0.95, 0.5, 0.45)

var _tag: String = ""
var _treaty_ids: Array[String] = []
var _aid_kinds: Array[String] = []
var _party_ids: Array[String] = []
var _claimable: Array[String] = []
var _war_section: WarSection

@onready var _title_label: Label = %TitleLabel
@onready var _flag_rect: TextureRect = %FlagRect
@onready var _summary_grid: GridContainer = %SummaryGrid
@onready var _treaties_box: VBoxContainer = %TreatiesBox
@onready var _actions_grid: GridContainer = %ActionsGrid
@onready var _sanctions_grid: GridContainer = %SanctionsGrid
@onready var _sanctions_label: Label = %SanctionsLabel
@onready var _aid_programs: Label = %AidPrograms
@onready var _aid_kind_option: OptionButton = %AidKindOption
@onready var _aid_amount: SpinBox = %AidAmount
@onready var _aid_duration: OptionButton = %AidDurationOption
@onready var _aid_button: Button = %AidButton
@onready var _aid_label: Label = %AidLabel
@onready var _influence_label: Label = %InfluenceLabel
@onready var _party_option: OptionButton = %PartyOption
@onready var _support_button: Button = %SupportButton
@onready var _influence_grid: GridContainer = %InfluenceGrid
@onready var _claims_box: VBoxContainer = %ClaimsBox
@onready var _claim_row: HBoxContainer = %ClaimRow
@onready var _province_option: OptionButton = %ProvinceOption
@onready var _claim_button: Button = %ClaimButton
@onready var _treaty_option: OptionButton = %TreatyOption
@onready var _propose_button: Button = %ProposeButton
@onready var _opinion_label: Label = %OpinionLabel
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_war_section = WarSection.new()
	_claim_row.get_parent().add_child(_war_section)
	_claim_row.get_parent().move_child(_war_section, _claim_row.get_index() + 1)
	_war_section.command_requested.connect(_submit)
	_treaty_option.item_selected.connect(func(_index: int) -> void: _update_proposal())
	_propose_button.pressed.connect(func() -> void:
		if _treaty_option.selected >= 0 and _treaty_option.selected < _treaty_ids.size():
			_submit(ProposeTreatyCommand.new(GameState.sim.player_tag, _tag, _treaty_ids[_treaty_option.selected])))
	_aid_kind_option.item_selected.connect(func(_index: int) -> void: _update_aid())
	_aid_button.pressed.connect(_on_aid_pressed)
	_party_option.item_selected.connect(func(_index: int) -> void: _update_support())
	_province_option.item_selected.connect(func(_index: int) -> void: _update_claim())
	_claim_button.pressed.connect(func() -> void:
		if _province_option.selected >= 0 and _province_option.selected < _claimable.size():
			_submit(ClaimCommand.new(GameState.sim.player_tag, ClaimCommand.ADD, -1, _tag, _claimable[_province_option.selected])))
	_support_button.pressed.connect(func() -> void:
		if _party_option.selected >= 0 and _party_option.selected < _party_ids.size():
			_submit(InfluenceCommand.new(GameState.sim.player_tag, _tag, "support_party", _party_ids[_party_option.selected])))
	EventBus.locale_changed.connect(func(_locale: String) -> void: refresh())
	EventBus.month_passed.connect(func(_date: GameDate) -> void: refresh())
	EventBus.command_executed.connect(func(_command: Command) -> void: refresh())
	visible = false


func show_country(tag: String) -> void:
	_tag = tag
	visible = true
	refresh()


func refresh() -> void:
	if not visible:
		return
	var state := GameState.sim
	var player := str(state.player_tag)
	var data := DataLoader.get_entry("countries", _tag)
	_title_label.text = tr("DIPLOMACY_TITLE_VALUE") % tr(str(data.get("name_key", _tag)))
	_flag_rect.texture = CountryFlags.texture_for(CountryFlags.path_for(_tag, data), Color.html(str(data.get("color", "#808080"))))
	_clear_rows(_summary_grid)
	_clear_rows(_actions_grid)
	_clear_rows(_sanctions_grid)
	for child: Node in _treaties_box.get_children():
		_treaties_box.remove_child(child)
		child.queue_free()
	_war_section.show_country(_tag)
	if player.is_empty() or player == _tag or state.diplomacy_settings.is_empty():
		return
	var diplomacy := state.diplomacy
	_add_row(_summary_grid, "DIPLOMACY_RELATION", _signed(diplomacy.relation(player, _tag)))
	_add_row(_summary_grid, "DIPLOMACY_TRUST", tr("SOCIETY_SCORE_VALUE") % roundi(diplomacy.trust(player, _tag)))
	_add_row(_summary_grid, "DIPLOMACY_OPINION_OF_US", _signed(diplomacy.opinion(_tag, player)))
	_add_row(_summary_grid, "DIPLOMACY_OUR_OPINION", _signed(diplomacy.opinion(player, _tag)))
	_add_row(_summary_grid, "DIPLOMACY_EMBASSY", tr("COMMON_YES" if diplomacy.has_embassy(player, _tag) else "COMMON_NO"))
	if not DiplomacySystem.recognition_of(state, _tag).is_empty():
		_add_row(_summary_grid, "DIPLOMACY_RECOGNITION",
			tr("COMMON_YES" if diplomacy.recognizes(player, _tag) else "COMMON_NO"))
	if diplomacy.guarantees_independence(player, _tag):
		_add_row(_summary_grid, "DIPLOMACY_GUARANTEED", tr("COMMON_YES"))
	_fill_treaties(state, player)
	_fill_sanctions(state, player)
	_fill_aid(state, player)
	_fill_influence(state, player)
	_fill_claims(state, player)
	_fill_actions(state)
	_fill_proposal(state, player)


func _fill_treaties(state: SimState, player: String) -> void:
	var treaties := state.diplomacy.treaties_between(player, _tag)
	if treaties.is_empty():
		var none := Label.new()
		none.text = "DIPLOMACY_NO_TREATY"
		none.add_theme_color_override("font_color", LABEL_COLOR)
		_treaties_box.add_child(none)
	for treaty_id: int in treaties:
		var treaty: Dictionary = state.diplomacy.treaties[treaty_id]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str((state.treaty_definitions.get(treaty["type"], {}) as Dictionary).get("name_key", treaty["type"]))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var cancel := Button.new()
		cancel.text = "DIPLOMACY_CANCEL_TREATY"
		cancel.tooltip_text = "DIPLOMACY_CANCEL_TREATY_TOOLTIP"
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.pressed.connect(func() -> void: _submit(CancelTreatyCommand.new(state.player_tag, treaty_id)))
		row.add_child(cancel)
		_treaties_box.add_child(row)


## Mesures : celles que nous imposons (bouton imposer / lever) et celles qu'il nous impose.
func _fill_sanctions(state: SimState, player: String) -> void:
	for measure: String in state.sanction_definitions.keys():
		var definition: Dictionary = state.sanction_definitions[measure]
		var name_label := Label.new()
		name_label.text = str(definition["name_key"])
		name_label.add_theme_color_override("font_color", LABEL_COLOR)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sanctions_grid.add_child(name_label)
		var theirs := Label.new()
		theirs.text = "DIPLOMACY_SANCTIONED_BY_THEM" if SanctionSystem.has_measure(state, _tag, player, measure) else ""
		theirs.add_theme_color_override("font_color", BAD_COLOR)
		_sanctions_grid.add_child(theirs)
		var active := SanctionSystem.has_measure(state, player, _tag, measure)
		var button := Button.new()
		button.text = "DIPLOMACY_LIFT" if active else "DIPLOMACY_IMPOSE"
		button.focus_mode = Control.FOCUS_NONE
		var exposure := SanctionSystem.exposure(state, player, _tag)
		button.tooltip_text = tr("DIPLOMACY_SANCTION_TOOLTIP") % [
			NumberFormat.decimal(float(definition.get("growth", 0.0)) * exposure, 2, Localization.get_locale()),
			roundi(float(definition.get("relation", 0.0)))]
		button.pressed.connect(func() -> void: _submit(SanctionCommand.new(state.player_tag, _tag, measure, not active)))
		_sanctions_grid.add_child(button)
	var count := SanctionSystem.sanctioners_of(state, _tag).size()
	_sanctions_label.text = tr("DIPLOMACY_SANCTIONED_COUNT") % [count, NumberFormat.decimal(
		state.get_country(_tag).economy.sanction_growth, 2, Localization.get_locale())]


## Programmes d'aide en cours entre les deux pays et proposition d'une nouvelle aide.
func _fill_aid(state: SimState, player: String) -> void:
	var lines: PackedStringArray = []
	var locale := Localization.get_locale()
	for program: Dictionary in AidSystem.programs_between(state, player, _tag):
		var key := "DIPLOMACY_AID_GIVEN" if program["donor"] == player else "DIPLOMACY_AID_RECEIVED"
		lines.append(tr(key) % [tr(str((state.aid_definitions.get(program["kind"], {}) as Dictionary).get("name_key", ""))),
			NumberFormat.decimal(float(program["amount"]), 1, locale), int(program["months_left"])])
	_aid_programs.text = "\n".join(lines) if not lines.is_empty() else tr("DIPLOMACY_NO_AID")
	if _aid_kind_option.item_count == 0:
		for kind: String in state.aid_definitions.keys():
			_aid_kinds.append(kind)
			_aid_kind_option.add_item(tr(str((state.aid_definitions[kind] as Dictionary)["name_key"])))
		for months: Variant in AidSystem.settings_of(state).get("durations", []):
			_aid_duration.add_item(tr("DIPLOMACY_AID_DURATION_%d" % int(months)))
	_update_aid()


func _update_aid() -> void:
	var state := GameState.sim
	if _aid_kind_option.selected < 0 or _aid_kinds.is_empty():
		return
	var kind := _aid_kinds[_aid_kind_option.selected]
	var accepts := AidSystem.accepts(state, str(state.player_tag), _tag, kind)
	_aid_label.text = tr("DIPLOMACY_AID_LIKELY_YES" if accepts else "DIPLOMACY_AID_LIKELY_NO")
	_aid_label.add_theme_color_override("font_color", GOOD_COLOR if accepts else BAD_COLOR)
	_aid_button.tooltip_text = tr("%s_TOOLTIP" % str((state.aid_definitions[kind] as Dictionary)["name_key"]))


func _on_aid_pressed() -> void:
	var state := GameState.sim
	var durations: Array = AidSystem.settings_of(state).get("durations", [])
	if _aid_kind_option.selected < 0 or _aid_duration.selected < 0 or _aid_duration.selected >= durations.size():
		return
	_submit(AidCommand.new(state.player_tag, _tag, _aid_kinds[_aid_kind_option.selected], _aid_amount.value,
		int(durations[_aid_duration.selected])))


## Influence des deux pays l'un chez l'autre, partis à soutenir et actions payées en points.
func _fill_influence(state: SimState, player: String) -> void:
	_clear_rows(_influence_grid)
	var locale := Localization.get_locale()
	var lines: PackedStringArray = [
		tr("DIPLOMACY_INFLUENCE_VALUE") % [roundi(InfluenceSystem.influence(state, player, _tag)),
			roundi(InfluenceSystem.influence(state, _tag, player))],
		tr("DIPLOMACY_INFLUENCE_POINTS") % NumberFormat.decimal(float(state.diplomacy.influence_points.get(player, 0.0)),
			0, locale)]
	if state.diplomacy.bases.has(DiplomacyState.opinion_key(player, _tag)):
		lines.append(tr("DIPLOMACY_OUR_BASE"))
	if state.diplomacy.bases.has(DiplomacyState.opinion_key(_tag, player)):
		lines.append(tr("DIPLOMACY_THEIR_BASE"))
	_influence_label.text = "\n".join(lines)
	var parties := DataLoader.repository.resolve_ref("names#parties")
	var previous := _party_ids[_party_option.selected] if _party_option.selected >= 0 \
		and _party_option.selected < _party_ids.size() else ""
	_party_ids.clear()
	_party_option.clear()
	var country := state.get_country(_tag)
	for party: PartyState in country.politics.parties.values():
		_party_ids.append(party.id)
		_party_option.add_item("%s (%s %%)" % [str((parties.get(party.id, {}) as Dictionary).get("abbreviation", party.id)),
			NumberFormat.decimal(party.poll, 0, locale)])
	var index := _party_ids.find(previous)
	_party_option.select(index if index >= 0 else (0 if not _party_ids.is_empty() else -1))
	_party_option.get_parent().visible = not _party_ids.is_empty()
	_update_support()
	var costs: Dictionary = InfluenceSystem.settings_of(state).get("actions", {})
	for action: String in ["fund_opposition", "soft_power", "open_base", "close_base"]:
		var refusal := InfluenceCommand.new(state.player_tag, _tag, action).refusal_reason(state)
		if refusal == "DIPLOMACY_ALREADY":
			continue
		var button := Button.new()
		button.text = tr("DIPLOMACY_INFLUENCE_%s" % action.to_upper()) % roundi(float((costs.get(action, {}) as Dictionary).get(
			"cost", 0.0)))
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = not refusal.is_empty()
		button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("DIPLOMACY_INFLUENCE_%s_TOOLTIP" % action.to_upper())
		button.pressed.connect(func() -> void: _submit(InfluenceCommand.new(state.player_tag, _tag, action)))
		_influence_grid.add_child(button)


func _update_support() -> void:
	var state := GameState.sim
	var party := _party_ids[_party_option.selected] if _party_option.selected >= 0 \
		and _party_option.selected < _party_ids.size() else ""
	var refusal := InfluenceCommand.new(state.player_tag, _tag, "support_party", party).refusal_reason(state)
	_support_button.disabled = not refusal.is_empty()
	_support_button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("DIPLOMACY_SUPPORT_PARTY_TOOLTIP")


## Revendications entre les deux pays (les nôtres : faire valoir, abandonner) et nouvelle revendication.
func _fill_claims(state: SimState, player: String) -> void:
	for child: Node in _claims_box.get_children():
		_claims_box.remove_child(child)
		child.queue_free()
	var claims := TensionSystem.claims_between(state, player, _tag)
	if claims.is_empty():
		var none := Label.new()
		none.text = "DIPLOMACY_NO_CLAIM"
		none.add_theme_color_override("font_color", LABEL_COLOR)
		_claims_box.add_child(none)
	for claim_id: int in claims:
		var claim: Dictionary = state.diplomacy.claims[claim_id]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = tr("DIPLOMACY_CLAIM_OURS" if claim["claimant"] == player else "DIPLOMACY_CLAIM_THEIRS") \
			% _claim_text(state, claim)
		if not bool(claim.get("active", true)):
			label.text += " " + tr("DIPLOMACY_CLAIM_FROZEN")
			label.tooltip_text = tr("DIPLOMACY_CLAIM_FROZEN_TOOLTIP")
			label.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(label)
		if claim["claimant"] == player:
			for action: String in [ClaimCommand.PRESS, ClaimCommand.RENOUNCE]:
				var button := Button.new()
				button.text = "DIPLOMACY_CLAIM_%s" % action.to_upper()
				button.tooltip_text = "DIPLOMACY_CLAIM_%s_TOOLTIP" % action.to_upper()
				button.focus_mode = Control.FOCUS_NONE
				var refusal := ClaimCommand.new(state.player_tag, action, claim_id).refusal_reason(state)
				button.disabled = not refusal.is_empty()
				if not refusal.is_empty():
					button.tooltip_text = tr(refusal)
				button.pressed.connect(func() -> void: _submit(ClaimCommand.new(state.player_tag, action, claim_id)))
				row.add_child(button)
		_claims_box.add_child(row)
	_claimable.clear()
	_province_option.clear()
	var provinces: Dictionary = state.energy_definitions.get("provinces", {})
	for province_id: String in TensionSystem.adjacent_provinces(state, player, _tag, provinces):
		if not TensionSystem.is_claimed_by(state, player, province_id):
			_claimable.append(province_id)
			_province_option.add_item(tr(str((provinces[province_id] as Dictionary).get("name_key", province_id))))
	_claim_row.visible = not _claimable.is_empty()
	_update_claim()


func _claim_text(state: SimState, claim: Dictionary) -> String:
	var provinces: Array = claim.get("provinces", [])
	if provinces.is_empty():
		return tr("DIPLOMACY_CLAIM_WHOLE")
	var names: PackedStringArray = []
	for province_id: Variant in provinces:
		names.append(tr(str(DataLoader.get_entry("provinces", str(province_id)).get("name_key", province_id))))
	return ", ".join(names)


func _update_claim() -> void:
	var state := GameState.sim
	var province := _claimable[_province_option.selected] if _province_option.selected >= 0 \
		and _province_option.selected < _claimable.size() else ""
	var refusal := ClaimCommand.new(state.player_tag, ClaimCommand.ADD, -1, _tag, province).refusal_reason(state)
	_claim_button.disabled = not refusal.is_empty()
	_claim_button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("DIPLOMACY_ADD_CLAIM_TOOLTIP")


## Boutons d'action ; une action impossible est grisée avec la raison en info-bulle.
func _fill_actions(state: SimState) -> void:
	for action: String in DiplomaticActionCommand.ACTIONS:
		var command := DiplomaticActionCommand.new(state.player_tag, _tag, action)
		var refusal := command.refusal_reason(state)
		if refusal == "DIPLOMACY_ALREADY" or refusal == "DIPLOMACY_NOT_DISPUTED":
			continue
		var button := Button.new()
		button.text = "DIPLOMACY_ACTION_%s" % action.to_upper()
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = not refusal.is_empty()
		button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("DIPLOMACY_ACTION_%s_TOOLTIP" % action.to_upper())
		button.pressed.connect(func() -> void: _submit(DiplomaticActionCommand.new(state.player_tag, _tag, action)))
		_actions_grid.add_child(button)


func _fill_proposal(state: SimState, player: String) -> void:
	var previous := _treaty_ids[_treaty_option.selected] if _treaty_option.selected >= 0 \
		and _treaty_option.selected < _treaty_ids.size() else ""
	_treaty_ids.clear()
	_treaty_option.clear()
	for treaty_type: String in state.treaty_definitions.keys():
		if not state.diplomacy.has_treaty(player, _tag, treaty_type):
			_treaty_ids.append(treaty_type)
			_treaty_option.add_item(tr(str((state.treaty_definitions[treaty_type] as Dictionary)["name_key"])))
	var index := _treaty_ids.find(previous)
	_treaty_option.select(index if index >= 0 else 0)
	_update_proposal()


## Avis probable du pays sur le traité choisi.
func _update_proposal() -> void:
	var state := GameState.sim
	if _treaty_option.selected < 0 or _treaty_ids.is_empty():
		_propose_button.disabled = true
		_opinion_label.text = ""
		return
	var treaty_type := _treaty_ids[_treaty_option.selected]
	var refusal := ProposeTreatyCommand.new(state.player_tag, _tag, treaty_type).refusal_reason(state)
	_propose_button.disabled = not refusal.is_empty()
	_propose_button.tooltip_text = tr(refusal) if not refusal.is_empty() else ""
	var score := DiplomacyModel.treaty_score(state, str(state.player_tag), _tag, state.treaty_definitions[treaty_type])
	_opinion_label.text = tr("DIPLOMACY_LIKELY_YES" if score > 0.0 else "DIPLOMACY_LIKELY_NO") % roundi(score)
	_opinion_label.add_theme_color_override("font_color", GOOD_COLOR if score > 0.0 else BAD_COLOR)


func _signed(value: float) -> String:
	return ("+" if roundi(value) > 0 else "") + str(roundi(value))


func _submit(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()

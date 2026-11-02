class_name WorldPanel
extends InfoPanel
## Panneau Monde : organisations internationales (adhésion, départ, exclusion, invitation, création) et ONU
## (Conseil de sécurité, résolutions de condamnation).

const GOOD_COLOR := Color(0.55, 0.85, 0.55)
const BAD_COLOR := Color(0.95, 0.5, 0.45)
const MEMBER_MARK := "✓ "

var _org_ids: Array[String] = []
var _member_targets: Array[String] = []
var _other_targets: Array[String] = []
var _resolution_targets: Array[String] = []

@onready var _tension_label: Label = %TensionLabel
@onready var _tension_bar: ProgressBar = %TensionBar
@onready var _unlocks_label: Label = %UnlocksLabel
@onready var _org_option: OptionButton = %OrganizationOption
@onready var _summary_grid: GridContainer = %SummaryGrid
@onready var _members_label: Label = %MembersLabel
@onready var _membership_button: Button = %MembershipButton
@onready var _membership_label: Label = %MembershipLabel
@onready var _member_option: OptionButton = %MemberOption
@onready var _expel_button: Button = %ExpelButton
@onready var _invite_row: HBoxContainer = %InviteRow
@onready var _other_option: OptionButton = %OtherOption
@onready var _invite_button: Button = %InviteButton
@onready var _action_label: Label = %ActionLabel
@onready var _un_box: VBoxContainer = %UnBox
@onready var _council_label: Label = %CouncilLabel
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _resolution_kind: OptionButton = %ResolutionKindOption
@onready var _assembly_button: Button = %AssemblyButton
@onready var _council_button: Button = %CouncilButton
@onready var _resolution_label: Label = %ResolutionLabel
@onready var _name_edit: LineEdit = %NameEdit
@onready var _kind_option: OptionButton = %KindOption
@onready var _create_button: Button = %CreateButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_org_option.item_selected.connect(func(_index: int) -> void: refresh())
	_member_option.item_selected.connect(func(_index: int) -> void: _update_actions())
	_other_option.item_selected.connect(func(_index: int) -> void: _update_actions())
	_resolution_option.item_selected.connect(func(_index: int) -> void: _update_resolution())
	_resolution_kind.add_item("WORLD_RESOLUTION_CONDEMN")
	_resolution_kind.add_item("WORLD_RESOLUTION_SANCTIONS")
	_resolution_kind.item_selected.connect(func(_index: int) -> void: _update_resolution())
	_membership_button.pressed.connect(func() -> void:
		var org := _current()
		var leaving := OrganizationSystem.is_member(GameState.sim, org, str(GameState.sim.player_tag))
		_submit(OrganizationCommand.new(GameState.sim.player_tag,
			OrganizationCommand.LEAVE if leaving else OrganizationCommand.JOIN, org)))
	_expel_button.pressed.connect(func() -> void:
		_submit(OrganizationCommand.new(GameState.sim.player_tag, OrganizationCommand.EXPEL, _current(), _selected(
			_member_option, _member_targets))))
	_invite_button.pressed.connect(func() -> void:
		_submit(OrganizationCommand.new(GameState.sim.player_tag, OrganizationCommand.INVITE, _current(), _selected(
			_other_option, _other_targets))))
	_assembly_button.pressed.connect(func() -> void: _resolution(OrganizationSystem.GENERAL_ASSEMBLY))
	_council_button.pressed.connect(func() -> void: _resolution(OrganizationSystem.SECURITY_COUNCIL))
	_create_button.pressed.connect(_on_create_pressed)
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
	var player := str(state.player_tag)
	if player.is_empty() or state.diplomacy.organizations.is_empty():
		return
	_fill_tension(state)
	_fill_organizations(state, player)
	var org := _current()
	var data: Dictionary = state.diplomacy.organizations.get(org, {})
	_clear_rows(_summary_grid)
	_add_row(_summary_grid, "WORLD_KIND", tr("WORLD_KIND_%s" % str(data.get("kind", "")).to_upper()))
	var members := OrganizationSystem.members(state, org)
	_add_row(_summary_grid, "WORLD_MEMBERS", str(members.size()))
	if not OrganizationSystem.is_custom(state, org):
		_add_row(_summary_grid, "WORLD_DECISION", tr("WORLD_DECISION_%s" % str(OrganizationSystem.rules_of(state, org).get(
			"decision", "majority")).to_upper()))
	var names: PackedStringArray = []
	for tag: Variant in members:
		names.append(_country_name(str(tag)))
	_members_label.text = ", ".join(names)
	var member := OrganizationSystem.is_member(state, org, player)
	_membership_button.text = tr("WORLD_LEAVE" if member else "WORLD_JOIN")
	var action := OrganizationCommand.LEAVE if member else OrganizationCommand.JOIN
	var refusal := OrganizationCommand.new(state.player_tag, action, org).refusal_reason(state)
	_membership_button.disabled = not refusal.is_empty()
	_membership_button.tooltip_text = tr(refusal) if not refusal.is_empty() else tr("WORLD_%s_TOOLTIP" % action.to_upper())
	if not member and refusal.is_empty():
		var vote := OrganizationSystem.expected_join(state, org, player)
		_show_vote(_membership_label, vote)
	else:
		_membership_label.text = ""
	_fill_targets(state, org, player)
	_fill_un(state, org, player)


## Jauge de tension mondiale et actions qu'elle débloque.
func _fill_tension(state: SimState) -> void:
	var tension := state.diplomacy.world_tension
	_tension_label.text = tr("WORLD_TENSION_VALUE") % roundi(tension)
	_tension_bar.value = tension
	var lines: PackedStringArray = []
	var thresholds: Dictionary = TensionSystem.settings_of(state).get("thresholds", {})
	var actions: Array = thresholds.keys()
	actions.sort_custom(func(a: Variant, b: Variant) -> bool: return float(thresholds[a]) < float(thresholds[b]))
	for action: Variant in actions:
		var key := "WORLD_UNLOCKED" if TensionSystem.unlocked(state, str(action)) else "WORLD_LOCKED"
		lines.append(tr(key) % [tr("WORLD_ACTION_%s" % str(action).to_upper()), roundi(float(thresholds[action]))])
	_unlocks_label.text = "\n".join(lines)


func _fill_organizations(state: SimState, player: String) -> void:
	var previous := _current()
	var ids: Array = state.diplomacy.organizations.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var member_a := OrganizationSystem.is_member(state, a, player)
		var member_b := OrganizationSystem.is_member(state, b, player)
		return member_a and not member_b if member_a != member_b else a < b)
	_org_ids.clear()
	_org_option.clear()
	for org_id: String in ids:
		var data: Dictionary = state.diplomacy.organizations[org_id]
		_org_ids.append(org_id)
		_org_option.add_item("%s%s — %s" % [MEMBER_MARK if OrganizationSystem.is_member(state, org_id, player) else "",
			Localization.pick_text(data.get("abbreviation", org_id)), Localization.pick_text(data.get("name", org_id))])
	var index := _org_ids.find(previous)
	_org_option.select(index if index >= 0 else 0)
	if _kind_option.item_count == 0:
		for kind: Variant in OrganizationSystem.settings_of(state).get("creatable_kinds", []):
			_kind_option.add_item(tr("WORLD_KIND_%s" % str(kind).to_upper()))


func _fill_targets(state: SimState, org: String, player: String) -> void:
	var member := OrganizationSystem.is_member(state, org, player)
	_member_targets = _sorted_tags(state, func(tag: String) -> bool:
		return tag != player and OrganizationSystem.is_member(state, org, tag))
	_fill_option(_member_option, _member_targets)
	_other_targets = _sorted_tags(state, func(tag: String) -> bool:
		return tag != player and not OrganizationSystem.is_member(state, org, tag))
	_fill_option(_other_option, _other_targets)
	_expel_button.get_parent().visible = member
	_invite_row.visible = member and OrganizationSystem.is_custom(state, org)
	_update_actions()


func _update_actions() -> void:
	var state := GameState.sim
	var org := _current()
	var expel := OrganizationCommand.new(state.player_tag, OrganizationCommand.EXPEL, org,
		_selected(_member_option, _member_targets))
	_set_button(_expel_button, expel.refusal_reason(state))
	var invite := OrganizationCommand.new(state.player_tag, OrganizationCommand.INVITE, org,
		_selected(_other_option, _other_targets))
	_set_button(_invite_button, invite.refusal_reason(state))
	_action_label.text = ""
	if _expel_button.get_parent().visible and not _member_targets.is_empty():
		var vote := OrganizationSystem.expected_expulsion(state, org, _selected(_member_option, _member_targets))
		_show_vote(_action_label, vote)
	if _invite_row.visible and not _other_targets.is_empty():
		var score := OrganizationSystem.invite_score(state, org, str(state.player_tag), _selected(_other_option, _other_targets))
		_action_label.text = tr("DIPLOMACY_LIKELY_YES" if score > 0.0 else "DIPLOMACY_LIKELY_NO") % roundi(score)
		_action_label.add_theme_color_override("font_color", GOOD_COLOR if score > 0.0 else BAD_COLOR)


func _fill_un(state: SimState, org: String, player: String) -> void:
	_un_box.visible = org == OrganizationSystem.UN
	if not _un_box.visible:
		return
	var council: PackedStringArray = []
	var seats: Array = state.diplomacy.security_council.keys()
	seats.sort_custom(func(a: String, b: String) -> bool:
		return int(state.diplomacy.security_council[a]) < int(state.diplomacy.security_council[b]))
	for tag: String in seats:
		var end := int(state.diplomacy.security_council[tag])
		council.append("%s %s" % [_country_name(tag), tr("WORLD_PERMANENT") if end == 0 else tr("WORLD_UNTIL") % end])
	_council_label.text = tr("WORLD_COUNCIL_VALUE") % ", ".join(council)
	_resolution_targets = _sorted_tags(state, func(tag: String) -> bool: return tag != player)
	_fill_option(_resolution_option, _resolution_targets)
	_update_resolution()


func _update_resolution() -> void:
	var state := GameState.sim
	var target := _selected(_resolution_option, _resolution_targets)
	for pair: Array in [[_assembly_button, OrganizationSystem.GENERAL_ASSEMBLY],
			[_council_button, OrganizationSystem.SECURITY_COUNCIL]]:
		var command := OrganizationCommand.new(state.player_tag, OrganizationCommand.RESOLUTION, OrganizationSystem.UN,
			target, str(pair[1]), _resolution_type())
		_set_button(pair[0], command.refusal_reason(state))
	if target.is_empty():
		_resolution_label.text = ""
		return
	var assembly := OrganizationSystem.expected_resolution(state, OrganizationSystem.GENERAL_ASSEMBLY,
		str(state.player_tag), target)
	var council := OrganizationSystem.expected_resolution(state, OrganizationSystem.SECURITY_COUNCIL,
		str(state.player_tag), target)
	_resolution_label.text = tr("WORLD_RESOLUTION_PREVIEW") % [assembly["yes"], assembly["no"], assembly["abstain"],
		council["yes"], council["no"], tr("WORLD_VETO") if bool(council["vetoed"]) else ""]


func _resolution(body: String) -> void:
	_submit(OrganizationCommand.new(GameState.sim.player_tag, OrganizationCommand.RESOLUTION, OrganizationSystem.UN,
		_selected(_resolution_option, _resolution_targets), body, _resolution_type()))


func _resolution_type() -> String:
	return OrganizationSystem.RESOLUTION_SANCTIONS if _resolution_kind.selected == 1 \
		else OrganizationSystem.RESOLUTION_CONDEMN


func _on_create_pressed() -> void:
	var kinds: Array = OrganizationSystem.settings_of(GameState.sim).get("creatable_kinds", [])
	if _kind_option.selected < 0 or _kind_option.selected >= kinds.size():
		return
	_submit(OrganizationCommand.new(GameState.sim.player_tag, OrganizationCommand.CREATE, "", "", _name_edit.text,
		str(kinds[_kind_option.selected])))
	_name_edit.clear()


func _show_vote(label: Label, vote: Dictionary) -> void:
	var key := "WORLD_VOTE_VETO" if bool(vote["vetoed"]) else "WORLD_VOTE_PASS" if bool(vote["passed"]) else "WORLD_VOTE_FAIL"
	label.text = tr(key) % [vote["yes"], vote["no"]]
	label.add_theme_color_override("font_color", GOOD_COLOR if bool(vote["passed"]) else BAD_COLOR)


func _set_button(button: Button, refusal: String) -> void:
	button.disabled = not refusal.is_empty()
	button.tooltip_text = tr(refusal) if not refusal.is_empty() else ""


func _current() -> String:
	return _org_ids[_org_option.selected] if _org_option.selected >= 0 and _org_option.selected < _org_ids.size() else ""


func _selected(option: OptionButton, tags: Array[String]) -> String:
	return tags[option.selected] if option.selected >= 0 and option.selected < tags.size() else ""


func _fill_option(option: OptionButton, tags: Array[String]) -> void:
	var previous: Variant = option.get_item_metadata(option.selected) if option.selected >= 0 else null
	option.clear()
	for index: int in tags.size():
		option.add_item(_country_name(tags[index]))
		option.set_item_metadata(index, tags[index])
	var found := tags.find(str(previous)) if previous != null else -1
	option.select(found if found >= 0 else (0 if not tags.is_empty() else -1))


func _sorted_tags(state: SimState, keep: Callable) -> Array[String]:
	var entries: Array = []
	for tag: String in state.countries.keys():
		if keep.call(tag):
			entries.append([_country_name(tag), tag])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]).naturalnocasecmp_to(str(b[0])) < 0)
	var result: Array[String] = []
	for entry: Array in entries:
		result.append(str(entry[1]))
	return result


func _country_name(tag: String) -> String:
	return tr(str(CountryRegistry.entry(tag).get("name_key", tag)))


func _submit(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()

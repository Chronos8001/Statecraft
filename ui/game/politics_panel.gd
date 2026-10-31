class_name PoliticsPanel
extends InfoPanel
## Panneau Politique du pays joué : chambre basse en hémicycle, gouvernement, partis et sondages.

const PARTY_COLUMNS := 5
const HEADER_COLOR := Color(0.92, 0.95, 0.98)
const UP_COLOR := Color(0.55, 0.85, 0.55)
const DOWN_COLOR := Color(0.95, 0.5, 0.45)
const OTHERS_COLOR := Color(0.55, 0.57, 0.6)
const SWATCH_SIZE := Vector2(12, 12)
## Variation mensuelle en dessous de laquelle aucune flèche n'est affichée.
const TREND_THRESHOLD := 0.1
const PARTY_HEADERS := ["POLITICS_PARTY", "POLITICS_LEADER", "POLITICS_SEATS", "POLITICS_VOTE", "POLITICS_POLL"]
## Ordre des familles politiques dans l'hémicycle, de gauche à droite.
## Provinces les plus peuplées proposées pour un meeting.
const RALLY_CHOICES := 15
const GROUP_ORDER := ["left", "green", "social_democrat", "liberal", "conservative", "religious", "national", "power"]

@onready var _summary_grid: GridContainer = %SummaryGrid
@onready var _hemicycle: Hemicycle = %HemicycleView
@onready var _parties_grid: GridContainer = %PartiesGrid
@onready var _polls_hint: Label = %PollsHint
@onready var _early_button: Button = %EarlyElectionButton
@onready var _campaign_box: VBoxContainer = %CampaignBox
@onready var _campaign_grid: GridContainer = %CampaignGrid
@onready var _fund_spin: SpinBox = %FundSpin
@onready var _fund_button: Button = %FundButton
@onready var _rally_option: OptionButton = %RallyOption
@onready var _rally_button: Button = %RallyButton
@onready var _promise_option: OptionButton = %PromiseOption
@onready var _promise_button: Button = %PromiseButton
@onready var _fraud_option: OptionButton = %FraudOption
@onready var _fraud_button: Button = %FraudButton
## Provinces proposées pour un meeting et groupes proposés pour une promesse, dans l'ordre des listes.
var _rally_ids: Array[String] = []
var _promise_ids: Array[String] = []
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_parties_grid.columns = PARTY_COLUMNS
	_early_button.pressed.connect(_on_early_pressed)
	_fund_button.pressed.connect(func() -> void: _submit(CampaignFundCommand.new(GameState.sim.player_tag, _fund_spin.value)))
	_rally_button.pressed.connect(func() -> void:
		if _rally_option.selected >= 0:
			_submit(RallyCommand.new(GameState.sim.player_tag, _rally_ids[_rally_option.selected])))
	_promise_button.pressed.connect(func() -> void:
		if _promise_option.selected >= 0:
			_submit(PromiseCommand.new(GameState.sim.player_tag, _promise_ids[_promise_option.selected])))
	_fraud_button.pressed.connect(func() -> void:
		_submit(SetFraudCommand.new(GameState.sim.player_tag, maxi(_fraud_option.selected, 0))))
	EventBus.command_executed.connect(func(_command: Command) -> void: refresh())
	EventBus.locale_changed.connect(func(_locale: String) -> void: refresh())
	EventBus.month_passed.connect(func(_date: GameDate) -> void: refresh())
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
	_clear_rows(_summary_grid)
	_clear_rows(_parties_grid)
	_hemicycle.set_blocks([])
	var country := GameState.sim.get_country(str(GameState.sim.player_tag))
	if country == null or country.politics.seats <= 0:
		return
	var politics := country.politics
	var parties := DataLoader.repository.resolve_ref("names#parties")
	var ordered := _ordered_parties(politics)
	_fill_summary(politics)
	_fill_campaign(country, GameState.sim)
	var blocks: Array = []
	for party: PartyState in ordered:
		blocks.append([Color.html(str((parties.get(party.id, {}) as Dictionary).get("color", "#808080"))), party.seats])
	blocks.append([OTHERS_COLOR, politics.other_seats])
	_hemicycle.set_blocks(blocks)
	_fill_parties(politics, ordered, parties)
	_polls_hint.text = "POLITICS_POLLS_HINT" if politics.polls_published else "POLITICS_POLLS_HIDDEN"


## Partis rangés par famille politique, puis par sièges.
func _ordered_parties(politics: PoliticsState) -> Array:
	var result: Array = politics.parties.values()
	result.sort_custom(func(a: PartyState, b: PartyState) -> bool:
		var rank_a := GROUP_ORDER.find(a.party_group)
		var rank_b := GROUP_ORDER.find(b.party_group)
		return rank_a < rank_b if rank_a != rank_b else a.seats > b.seats)
	return result


func _fill_summary(politics: PoliticsState) -> void:
	var locale := Localization.get_locale()
	_add_row(_summary_grid, "POLITICS_CHAMBER", tr("POLITICS_SEATS_VALUE") % NumberFormat.integer(politics.seats, locale))
	if politics.dissolved:
		_add_row(_summary_grid, "POLITICS_STATUS", tr("POLITICS_DISSOLVED"))
	if not politics.government.is_empty():
		var key := "POLITICS_MAJORITY_VALUE" if politics.has_majority() else "POLITICS_MINORITY_VALUE"
		_add_row(_summary_grid, "POLITICS_GOVERNMENT", tr(key) % [NumberFormat.integer(politics.government_seats(), locale),
			NumberFormat.integer(politics.seats, locale)])
		_add_row(_summary_grid, "POLITICS_GOVERNMENT_POLL", tr("ECONOMY_PERCENT_VALUE")
			% NumberFormat.decimal(politics.government_poll(), 1, locale))
	var characters := DataLoader.repository.resolve_ref("names#characters")
	var cultures := DataLoader.get_category("names/cultures")
	_add_row(_summary_grid, "POLITICS_HEAD_OF_STATE", NameGenerator.full_name(characters.get(politics.head_of_state, {}),
		cultures))
	if politics.head_of_government != politics.head_of_state:
		_add_row(_summary_grid, "POLITICS_HEAD_OF_GOVERNMENT", NameGenerator.full_name(
			characters.get(politics.head_of_government, {}), cultures))
	_add_row(_summary_grid, "POLITICS_SYSTEM", _system_text(politics, locale))
	_add_row(_summary_grid, "POLITICS_LAST_ELECTION", _date_text(politics.election_year, politics.election_month))
	if politics.suspended:
		_add_row(_summary_grid, "POLITICS_NEXT_ELECTION", tr("POLITICS_SUSPENDED"))
	else:
		_add_row(_summary_grid, "POLITICS_NEXT_ELECTION", _date_text(politics.next_election_year,
			politics.next_election_month))
		if politics.has_presidency:
			_add_row(_summary_grid, "POLITICS_NEXT_PRESIDENTIAL", _date_text(politics.next_presidential_year,
				politics.next_presidential_month))
	if not politics.last_result.is_empty():
		_add_row(_summary_grid, "POLITICS_LAST_RESULT", _result_text(politics.last_result))
	var refusal := CallEarlyElectionCommand.new(GameState.sim.player_tag).refusal_reason(GameState.sim)
	_early_button.disabled = not refusal.is_empty()
	_early_button.tooltip_text = tr(refusal if not refusal.is_empty() else "POLITICS_EARLY_TOOLTIP")


func _date_text(year: int, month: int) -> String:
	return "%s %d" % [tr(DateFormat.month_key(month)), year]


func _system_text(politics: PoliticsState, locale: String) -> String:
	var text := tr("POLITICS_SYSTEM_%s" % politics.system_type.to_upper())
	if politics.system_type != PoliticsState.SYSTEM_MAJORITARIAN and politics.threshold > 0.0:
		text += " (%s)" % (tr("POLITICS_THRESHOLD_VALUE") % NumberFormat.decimal(politics.threshold, 1, locale))
	return text


## « Présidentielle, mars 2027 : UC (2 tours) » ou « Législatives, juin 2029 : PRD en tête, alternance ».
func _result_text(result: Dictionary) -> String:
	var parties := DataLoader.repository.resolve_ref("names#parties")
	var winner := str((parties.get(str(result.get("winner", "")), {}) as Dictionary).get("abbreviation", ""))
	var kind := "POLITICS_RESULT_PRESIDENTIAL" if str(result.get("kind", "")) == ElectionSystem.KIND_PRESIDENTIAL \
		else "POLITICS_RESULT_LEGISLATIVE"
	var text := tr(kind) % [_date_text(int(result["year"]), int(result["month"])), winner]
	if bool(result.get("government_changed", false)):
		text += ", " + tr("POLITICS_RESULT_CHANGE")
	return text


func _on_early_pressed() -> void:
	_submit(CallEarlyElectionCommand.new(GameState.sim.player_tag))


func _submit(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


## Campagne : visible pendant les mois qui précèdent un scrutin, ou tant que des promesses courent.
func _fill_campaign(country: CountryState, state: SimState) -> void:
	_clear_rows(_campaign_grid)
	var politics := country.politics
	var settings := ElectionSystem.campaign_settings(state)
	var election := CampaignModel.campaign_election(politics, state.date.year, state.date.month, settings)
	_campaign_box.visible = not election.is_empty() or not politics.promises.is_empty()
	if not _campaign_box.visible:
		return
	var locale := Localization.get_locale()
	var groups := DataLoader.get_category("social_groups")
	if not election.is_empty():
		_add_row(_campaign_grid, "CAMPAIGN_ELECTION", _date_text(int(election[0]), int(election[1])))
		_add_row(_campaign_grid, "CAMPAIGN_SPENT", tr("COUNTRY_INFO_GDP_VALUE") % NumberFormat.decimal(
			politics.campaign_spent, 1, locale))
		_add_row(_campaign_grid, "CAMPAIGN_BONUS", tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(
			(exp(politics.campaign_bonus) - 1.0) * CampaignModel.PERCENT, 1, locale))
		_add_row(_campaign_grid, "CAMPAIGN_RALLIES", str(politics.rallies.size()))
	for promise: Dictionary in politics.promises:
		var name_key := str((groups.get(promise["group"], {}) as Dictionary).get("name_key", promise["group"]))
		var status := tr("CAMPAIGN_PROMISE_PENDING") if bool(promise.get("pending", true)) \
			else tr("CAMPAIGN_PROMISE_DEADLINE") % _date_text(int(promise["deadline_year"]), int(promise["deadline_month"]))
		_add_row(_campaign_grid, tr("CAMPAIGN_PROMISE_TO") % tr(name_key), status)
	var limit := float(settings.get("max_spending_share", 0.0)) / CampaignModel.PERCENT \
		* TradeSystem.current_gdp(state, country.tag)
	_fund_spin.max_value = maxf(limit - politics.campaign_spent, 0.0)
	_fund_spin.step = maxf(snappedf(limit / 50.0, 0.1), 0.1)
	_set_action(_fund_button, CampaignFundCommand.new(state.player_tag, maxf(_fund_spin.value, 0.0001)), state)
	_rally_ids.clear()
	_rally_option.clear()
	var provinces: Array = ((state.politics_definitions.get("provinces", {}) as Dictionary).get(country.tag, []) as Array).duplicate()
	provinces.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	for entry: Array in provinces.slice(0, RALLY_CHOICES):
		if not politics.rallies.has(str(entry[0])):
			_rally_ids.append(str(entry[0]))
			_rally_option.add_item(tr(str(DataLoader.get_entry("provinces", str(entry[0])).get("name_key", entry[0]))))
	_set_action(_rally_button, RallyCommand.new(state.player_tag, _rally_ids[0] if not _rally_ids.is_empty() else ""), state)
	_promise_ids.clear()
	_promise_option.clear()
	for group_id: String in groups.keys():
		if country.society.satisfaction.has(group_id) and not politics.has_promise(group_id):
			_promise_ids.append(group_id)
			_promise_option.add_item(tr(str((groups[group_id] as Dictionary).get("name_key", group_id))))
	_set_action(_promise_button, PromiseCommand.new(state.player_tag, _promise_ids[0] if not _promise_ids.is_empty() else ""),
		state)
	_fraud_option.clear()
	for level: int in SetFraudCommand.MAX_LEVEL + 1:
		_fraud_option.add_item(tr("CAMPAIGN_FRAUD_%d" % level))
	_fraud_option.select(politics.fraud_level)
	_fraud_button.disabled = not politics.democratic or election.is_empty()
	_fraud_button.tooltip_text = tr("CAMPAIGN_FRAUD_USELESS") if not politics.democratic else ""


func _set_action(button: Button, command: CampaignCommand, state: SimState) -> void:
	var refusal := command.refusal_reason(state)
	button.disabled = not refusal.is_empty() and refusal != "CAMPAIGN_INVALID_AMOUNT"
	button.tooltip_text = tr(refusal) if not refusal.is_empty() else ""


func _fill_parties(politics: PoliticsState, ordered: Array, parties: Dictionary) -> void:
	for key: String in PARTY_HEADERS:
		var header := Label.new()
		header.text = key
		header.add_theme_color_override("font_color", HEADER_COLOR)
		_parties_grid.add_child(header)
	var characters := DataLoader.repository.resolve_ref("names#characters")
	var cultures := DataLoader.get_category("names/cultures")
	var locale := Localization.get_locale()
	var by_poll := ordered.duplicate()
	by_poll.sort_custom(func(a: PartyState, b: PartyState) -> bool: return a.poll > b.poll)
	for party: PartyState in by_poll:
		var data: Dictionary = parties.get(party.id, {})
		_parties_grid.add_child(_party_cell(party, data, politics.is_in_government(party.id)))
		var leader: Dictionary = characters.get(str(data.get("leader", "")), {})
		_parties_grid.add_child(_value(NameGenerator.full_name(leader, cultures) if not leader.is_empty() else ""))
		_parties_grid.add_child(_value(NumberFormat.integer(party.seats, locale)))
		_parties_grid.add_child(_value(tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(party.vote, 1, locale)))
		_parties_grid.add_child(_poll_label(party, locale))
	if politics.other_seats > 0 or politics.other_vote > 0.0:
		var others := Label.new()
		others.text = "POLITICS_OTHERS"
		others.add_theme_color_override("font_color", LABEL_COLOR)
		_parties_grid.add_child(others)
		_parties_grid.add_child(_value(""))
		_parties_grid.add_child(_value(NumberFormat.integer(politics.other_seats, locale)))
		_parties_grid.add_child(_value(tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(politics.other_vote, 1, locale)))
		_parties_grid.add_child(_value(tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(politics.other_poll, 1, locale)))


## Pastille de couleur, sigle et nom du parti ; ★ pour les partis au gouvernement.
func _party_cell(party: PartyState, data: Dictionary, in_government: bool) -> Control:
	var row := HBoxContainer.new()
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.color = Color.html(str(data.get("color", "#808080")))
	row.add_child(swatch)
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var star := tr("POLITICS_GOVERNMENT_MARK") + " " if in_government else ""
	label.text = "%s%s" % [star, str(data.get("abbreviation", party.id))]
	label.tooltip_text = "%s\n%s" % [Localization.pick_text(data.get("name", "")),
		tr(str((DataLoader.get_entry("ideologies", party.ideology)).get("name_key", party.ideology)))]
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(label)
	return row


func _poll_label(party: PartyState, locale: String) -> Label:
	var label := _value(tr("ECONOMY_PERCENT_VALUE") % NumberFormat.decimal(party.poll, 1, locale))
	var change := party.poll - party.previous_poll
	if absf(change) >= TREND_THRESHOLD:
		label.text += " ▲" if change > 0.0 else " ▼"
		label.add_theme_color_override("font_color", UP_COLOR if change > 0.0 else DOWN_COLOR)
	label.tooltip_text = tr("POLITICS_POLL_TOOLTIP") % NumberFormat.decimal(party.start_poll, 1, locale)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	return label


func _value(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

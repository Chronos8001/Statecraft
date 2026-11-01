class_name PeaceDialog
extends ConfirmationDialog
## Négociation de la paix : le joueur coche ses exigences (provinces visées et tenues, réparations), voit leur
## coût en score de guerre, la marge de l'adversaire et sa réponse probable, puis propose le traité.

signal command_requested(command: Command)

const GOOD_COLOR := Color(0.55, 0.85, 0.55)
const BAD_COLOR := Color(0.95, 0.5, 0.45)

var _war_id: int = -1
var _demands: Array[Dictionary] = []
var _checks: Array[CheckBox] = []
var _summary: Label


func setup(war_id: int) -> void:
	_war_id = war_id
	var state := GameState.sim
	var war: War = state.wars.get(war_id)
	var player := str(state.player_tag)
	var receiver := war.defender_leader() if player == war.attacker_leader() else war.attacker_leader()
	title = tr("PEACE_DIALOG_TITLE") % MilitaryUI.war_name(state, war)
	ok_button_text = tr("PEACE_DIALOG_PROPOSE")
	cancel_button_text = tr("NUCLEAR_CONFIRM_CANCEL")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	add_child(box)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = tr("PEACE_DIALOG_INTRO") % [roundi(WarEnd.score_for(state, war, player)),
		roundi(WarEnd.support(war, receiver))]
	box.add_child(intro)
	_demands = WarEnd.available_demands(state, war, player)
	if _demands.is_empty():
		var none := Label.new()
		none.text = tr("PEACE_DIALOG_NO_DEMAND")
		box.add_child(none)
	for demand: Dictionary in _demands:
		var check := CheckBox.new()
		check.text = tr("PEACE_DEMAND_COST") % [MilitaryUI.demand_text(state, demand), roundi(WarEnd.demand_cost(state, war,
			demand, receiver))]
		check.toggled.connect(func(_on: bool) -> void: _update())
		_checks.append(check)
		box.add_child(check)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)
	confirmed.connect(func() -> void: command_requested.emit(NegotiatePeaceCommand.new(state.player_tag, _war_id, _selected())))
	visibility_changed.connect(func() -> void:
		if not visible:
			queue_free())
	_update()


func _selected() -> Array:
	var result: Array = []
	for index: int in _checks.size():
		if _checks[index].button_pressed:
			result.append(_demands[index])
	return result


## Coût total, marge de l'adversaire et réponse probable ; proposition impossible : bouton grisé.
func _update() -> void:
	var state := GameState.sim
	var war: War = state.wars.get(_war_id)
	if war == null:
		return
	var player := str(state.player_tag)
	var receiver := war.defender_leader() if player == war.attacker_leader() else war.attacker_leader()
	var demands := _selected()
	var cost := WarEnd.total_cost(state, war, demands, receiver)
	var room := WarEnd.allowance(state, war, receiver)
	var likely := cost <= room
	_summary.text = tr("PEACE_DIALOG_SUMMARY") % [roundi(cost), roundi(room),
		tr("PEACE_DIALOG_LIKELY_YES" if likely else "PEACE_DIALOG_LIKELY_NO")]
	_summary.add_theme_color_override("font_color", GOOD_COLOR if likely else BAD_COLOR)
	var refusal := WarEnd.peace_refusal(state, player, _war_id, demands)
	get_ok_button().disabled = demands.is_empty() or not refusal.is_empty()
	get_ok_button().tooltip_text = tr(refusal) if not refusal.is_empty() else ""

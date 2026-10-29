extends GutTest

const GameStateScript := preload("res://core/game_state.gd")


class SetPlayerCommand extends Command:
	var tag: StringName

	func _init(p_tag: StringName) -> void:
		tag = p_tag

	func get_type() -> StringName:
		return &"set_player"

	func can_execute(_state: SimState) -> bool:
		return not tag.is_empty()

	func execute(state: SimState) -> void:
		state.player_tag = tag


var _game_state: Node


func before_each() -> void:
	_game_state = autofree(GameStateScript.new())


func test_new_game_uses_start_date_and_seed() -> void:
	_game_state.new_game(42, &"FRA")
	var sim: SimState = _game_state.sim
	assert_eq(sim.date.format_iso(), "2026-01-01 00:00")
	assert_eq(sim.game_seed, 42)
	assert_eq(sim.player_tag, &"FRA")


func test_same_seed_gives_same_random_sequence() -> void:
	var a := SimState.new()
	var b := SimState.new()
	a.setup(1234, GameDate.new(2026, 1, 1))
	b.setup(1234, GameDate.new(2026, 1, 1))
	for i: int in 5:
		assert_eq(a.rng.randi(), b.rng.randi())


func test_commands_wait_in_queue_until_processed() -> void:
	_game_state.new_game(1)
	assert_true(_game_state.submit_command(SetPlayerCommand.new(&"DEU")))
	assert_eq(_game_state.get_pending_count(), 1)
	assert_eq(_game_state.sim.player_tag, &"")
	assert_eq(_game_state.process_commands(), 1)
	assert_eq(_game_state.sim.player_tag, &"DEU")
	assert_eq(_game_state.get_pending_count(), 0)


func test_commands_run_in_submission_order() -> void:
	_game_state.new_game(1)
	_game_state.submit_command(SetPlayerCommand.new(&"USA"))
	_game_state.submit_command(SetPlayerCommand.new(&"BRA"))
	_game_state.process_commands()
	assert_eq(_game_state.sim.player_tag, &"BRA")


func test_invalid_command_is_refused() -> void:
	_game_state.new_game(1)
	assert_false(_game_state.submit_command(SetPlayerCommand.new(&"")))
	assert_eq(_game_state.get_pending_count(), 0)


func test_command_serializes_type() -> void:
	var command := SetPlayerCommand.new(&"CHN")
	command.issuer = &"CHN"
	assert_eq(command.to_dict(), {"type": &"set_player", "issuer": &"CHN"})

extends Node
## Horloge de jeu : pause, vitesses et écoulement du temps. Chaque heure de jeu écoulée
## déclenche GameState.advance_hour(). La date elle-même vit dans GameState.sim.date.
## L'horloge ne tourne que pendant une partie affichée (set_running).

const SOURCE := "GameClock"

var speed: int = 1
var is_paused: bool = true
var is_running: bool = false
var _accumulator: float = 0.0


func _ready() -> void:
	InputActions.register_defaults()
	reset()
	EventBus.game_started.connect(func(_player_tag: StringName) -> void: reset())


func reset() -> void:
	speed = clampi(int(DataLoader.get_define("time.default_speed", 1)), 1, get_speed_count())
	is_paused = true
	_accumulator = 0.0


func get_speed_count() -> int:
	return maxi(1, (DataLoader.get_define("time.speeds_hours_per_second", []) as Array).size())


func get_hours_per_second() -> float:
	var speeds: Array = DataLoader.get_define("time.speeds_hours_per_second", [])
	return float(speeds[speed - 1]) if speed - 1 < speeds.size() else 0.0


func get_date() -> GameDate:
	return GameState.sim.date


func set_running(running: bool) -> void:
	is_running = running
	_accumulator = 0.0


func set_speed(value: int) -> void:
	var clamped := clampi(value, 1, get_speed_count())
	if clamped == speed:
		return
	speed = clamped
	EventBus.game_speed_changed.emit(speed)


func set_paused(paused: bool) -> void:
	if paused == is_paused:
		return
	is_paused = paused
	EventBus.game_pause_changed.emit(is_paused)


func toggle_pause() -> void:
	set_paused(not is_paused)


## Convertit du temps réel en ticks (heures de jeu), au plus max_ticks_per_frame par appel.
## Le retard au-delà de ce plafond est abandonné pour ne pas faire ramer le jeu.
func consume(delta: float) -> int:
	_accumulator += delta * get_hours_per_second()
	var max_ticks := int(DataLoader.get_define("time.max_ticks_per_frame", 1))
	var ticks := mini(floori(_accumulator), max_ticks)
	_accumulator -= ticks
	_accumulator = minf(_accumulator, 1.0)
	return ticks


func _process(delta: float) -> void:
	if not is_running or is_paused:
		return
	for i: int in consume(delta):
		GameState.advance_hour()


func _unhandled_input(event: InputEvent) -> void:
	if not is_running:
		return
	if event.is_action_pressed(InputActions.TIME_TOGGLE_PAUSE):
		toggle_pause()
	elif event.is_action_pressed(InputActions.TIME_SPEED_UP, true):
		set_speed(speed + 1)
	elif event.is_action_pressed(InputActions.TIME_SLOW_DOWN, true):
		set_speed(speed - 1)
	else:
		return
	get_viewport().set_input_as_handled()

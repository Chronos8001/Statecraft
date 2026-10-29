extends Node
## Horloge de jeu : pause et vitesse. La date elle-même vit dans GameState.sim.date.
## L'écoulement du temps et l'ordonnanceur (hourly, daily…) arrivent avec la boucle de simulation.

var speed: int = 1
var is_paused: bool = true


func _ready() -> void:
	speed = clampi(int(DataLoader.get_define("time.default_speed", 1)), 1, get_speed_count())


func get_speed_count() -> int:
	return maxi(1, int(DataLoader.get_define("time.speed_count", 1)))


func get_date() -> GameDate:
	return GameState.sim.date


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

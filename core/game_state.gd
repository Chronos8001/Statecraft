extends Node
## Détient l'état de la partie en cours (SimState) et la file des commandes à exécuter.

const SOURCE := "GameState"

var sim: SimState = SimState.new()
var is_game_running: bool = false
var _pending_commands: Array[Command] = []


func new_game(p_seed: int, player_tag: StringName = &"") -> void:
	sim = SimState.new()
	sim.setup(p_seed, get_start_date(), player_tag)
	_pending_commands.clear()
	is_game_running = true
	GameLog.info(SOURCE, "Nouvelle partie : graine %d, date %s." % [p_seed, sim.date.format_iso()])
	EventBus.game_started.emit(player_tag)


func get_start_date() -> GameDate:
	var data: Variant = DataLoader.get_define("game.start_date", {})
	return GameDate.from_dict(data if data is Dictionary else {})


## Met une commande en file. Renvoie false si elle est refusée d'emblée.
func submit_command(command: Command) -> bool:
	if not command.can_execute(sim):
		GameLog.warn(SOURCE, "Commande refusée : %s" % command.get_type())
		return false
	_pending_commands.append(command)
	return true


## Exécute les commandes en file, dans l'ordre de soumission. Renvoie le nombre exécuté.
func process_commands() -> int:
	var batch: Array[Command] = _pending_commands
	_pending_commands = []
	var executed: int = 0
	for command: Command in batch:
		if not command.can_execute(sim):
			continue
		command.execute(sim)
		executed += 1
		EventBus.command_executed.emit(command)
	return executed


func get_pending_count() -> int:
	return _pending_commands.size()

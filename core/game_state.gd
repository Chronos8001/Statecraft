extends Node
## Détient l'état de la partie en cours (SimState), l'ordonnanceur des systèmes de simulation
## et la file des commandes à exécuter. GameClock appelle advance_hour() à chaque heure de jeu.

const SOURCE := "GameState"

var sim: SimState = SimState.new()
var scheduler: SimScheduler = SimScheduler.new()
var is_game_running: bool = false
var _pending_commands: Array[Command] = []


func new_game(p_seed: int, player_tag: StringName = &"") -> void:
	sim = SimState.new()
	sim.setup(p_seed, get_start_date(), player_tag)
	WorldSetup.populate(sim, DataLoader.get_category("countries"), DataLoader.get_category("currencies"),
		DataLoader.get_define("economy", {}), budget_definitions())
	scheduler = SimScheduler.new()
	scheduler.add_system(BudgetSystem.new())
	scheduler.add_system(EconomySystem.new(DataLoader.get_category("economy_sectors")))
	_pending_commands.clear()
	is_game_running = true
	GameLog.info(SOURCE, "Nouvelle partie : graine %d, date %s." % [p_seed, sim.date.format_iso()])
	EventBus.game_started.emit(player_tag)


## Une heure de jeu : commandes en attente, systèmes de simulation, puis signaux globaux.
func advance_hour() -> void:
	process_commands()
	var flags := scheduler.tick(sim)
	var date := sim.date
	EventBus.hour_passed.emit(date)
	var events := sim.events
	sim.events = []
	for event: Dictionary in events:
		EventBus.sim_event_raised.emit(event)
	if flags & GameDate.CHANGED_DAY:
		EventBus.day_passed.emit(date)
	if flags & GameDate.CHANGED_WEEK:
		EventBus.week_passed.emit(date)
	if flags & GameDate.CHANGED_MONTH:
		GameLog.info(SOURCE, "Nouveau mois : %04d-%02d." % [date.year, date.month])
		EventBus.month_passed.emit(date)
	if flags & GameDate.CHANGED_YEAR:
		EventBus.year_passed.emit(date)


func budget_definitions() -> Dictionary:
	return {
		"taxes": DataLoader.get_category("budget_taxes"),
		"spending": DataLoader.get_category("budget_spending"),
		"settings": DataLoader.get_define("budget", {}),
	}


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

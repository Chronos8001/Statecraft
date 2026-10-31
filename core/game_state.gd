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
		DataLoader.get_define("economy", {}), budget_definitions(), DataLoader.get_category("resources"),
		resource_definitions(), trade_definitions(), energy_definitions(), DataLoader.get_define("investment", {}),
		society_definitions(), politics_definitions(),
		{"settings": DataLoader.get_define("diplomacy", {}), "treaties": DataLoader.get_category("treaties"),
			"start": DataLoader.get_category("diplomacy")})
	scheduler = SimScheduler.new()
	scheduler.add_system(LawSystem.new())
	scheduler.add_system(ConstitutionSystem.new())
	scheduler.add_system(InvestmentSystem.new())
	scheduler.add_system(EnergySystem.new())
	scheduler.add_system(ResourceSystem.new())
	scheduler.add_system(TradeSystem.new())
	scheduler.add_system(BudgetSystem.new())
	scheduler.add_system(EconomySystem.new(DataLoader.get_category("economy_sectors")))
	scheduler.add_system(GovernmentSystem.new())
	scheduler.add_system(CrisisSystem.new())
	scheduler.add_system(MediaSystem.new())
	scheduler.add_system(SocietySystem.new())
	scheduler.add_system(PoliticsSystem.new())
	scheduler.add_system(ElectionSystem.new())
	scheduler.add_system(DiplomacySystem.new())
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


func resource_definitions() -> Dictionary:
	return {
		"straits": DataLoader.get_category("straits"),
		"sectors": DataLoader.get_category("economy_sectors"),
		"settings": DataLoader.get_define("resources", {}),
	}


func trade_definitions() -> Dictionary:
	return {
		"agreements": DataLoader.get_category("trade_agreements"),
		"settings": DataLoader.get_define("trade", {}),
	}


func energy_definitions() -> Dictionary:
	var mine_outputs: Dictionary = {}
	var resources := DataLoader.get_category("resources")
	for resource_id: String in resources.keys():
		if (resources[resource_id] as Dictionary).has("mine_output"):
			mine_outputs[resource_id] = float(resources[resource_id]["mine_output"])
	return {
		"sources": DataLoader.get_category("energy_sources"),
		"buildings": DataLoader.get_category("buildings"),
		"provinces": DataLoader.get_category("provinces"),
		"mine_outputs": mine_outputs,
		"settings": DataLoader.get_define("energy", {}),
	}


func society_definitions() -> Dictionary:
	return {
		"groups": DataLoader.get_category("social_groups"),
		"regimes": DataLoader.get_category("regimes"),
		"ideologies": DataLoader.get_category("ideologies"),
		"settings": DataLoader.get_define("society", {}),
	}


func politics_definitions() -> Dictionary:
	return {
		"parties": DataLoader.repository.resolve_ref("names#parties"),
		"characters": DataLoader.repository.resolve_ref("names#characters"),
		"provinces": country_provinces(DataLoader.get_category("provinces")),
		"laws": DataLoader.get_category("laws"),
		"constitution": DataLoader.get_category("constitution"),
		"portfolios": DataLoader.get_category("portfolios"),
		"crises": DataLoader.get_category("crises"),
		"names": {"cultures": DataLoader.get_category("names/cultures"),
			"party_styles": DataLoader.get_category("names/party_styles"),
			"ideologies": DataLoader.get_category("ideologies"), "traits": DataLoader.get_category("traits"),
			"settings": DataLoader.get_define("characters", {})},
		"settings": DataLoader.get_define("politics", {}),
	}


## Provinces de chaque pays pour les résultats régionaux : tag → [[id, population, superficie], …], triées.
static func country_provinces(provinces: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var ids: Array = provinces.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for province_id: String in ids:
		var province: Dictionary = provinces[province_id]
		var owner := str(province.get("owner", ""))
		if owner.is_empty():
			continue
		if not result.has(owner):
			result[owner] = []
		(result[owner] as Array).append([province_id, int(province.get("population", 0)),
			float(province.get("area_km2", 1.0))])
	return result


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

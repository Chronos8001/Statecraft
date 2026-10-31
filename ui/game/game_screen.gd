extends Control
## Écran de jeu : charge la carte dans un thread puis l'affiche. Sans pays joué, commence par
## la sélection du pays (temps arrêté). Échap revient à l'écran titre.

const SOURCE := "GameScreen"
const TITLE_SCENE := "res://ui/title/title_screen.tscn"
const DEGREES_PER_TURN := 360.0
const DEGREES_HALF_TURN := 180.0
const BYTES_PER_MEGABYTE := 1048576.0
const DEFAULT_MAP_MODE := "political"
const LIVE_MAP_MODES := ["trade", "stability", "support", "vote", "ideology", "unrest", "relations"]

var _thread: Thread
var _load_started_ms: int = 0
var _map_modes: MapModeRegistry
var _mode_context: MapModeContext
var _current_mode_id: String = DEFAULT_MAP_MODE
var _notification_timer: SceneTreeTimer

@onready var _map_view: MapView = %MapView
@onready var _loading_label: Label = %LoadingLabel
@onready var _debug_label: Label = %DebugLabel
@onready var _info_panel: ProvinceInfoPanel = %ProvinceInfoPanel
@onready var _country_panel: CountryInfoPanel = %CountryInfoPanel
@onready var _top_bar: TopBar = %TopBar
@onready var _notification_label: Label = %NotificationLabel

@onready var _mode_bar: MapModeBar = %MapModeBar
@onready var _legend: MapLegend = %MapLegend
@onready var _selection_panel: CountrySelectionPanel = %CountrySelectionPanel
@onready var _economy_panel: EconomyPanel = %EconomyPanel
@onready var _budget_panel: BudgetPanel = %BudgetPanel
@onready var _markets_panel: MarketsPanel = %MarketsPanel
@onready var _trade_panel: TradePanel = %TradePanel
@onready var _energy_panel: EnergyPanel = %EnergyPanel
@onready var _investment_panel: InvestmentPanel = %InvestmentPanel
@onready var _society_panel: SocietyPanel = %SocietyPanel
@onready var _politics_panel: PoliticsPanel = %PoliticsPanel
@onready var _laws_panel: LawsPanel = %LawsPanel
@onready var _government_panel: GovernmentPanel = %GovernmentPanel


func _ready() -> void:
	var map_info: Dictionary = DataLoader.get_category("map").get("map", {})
	var image_path := str(map_info.get("provinces_image", ""))
	_loading_label.text = "MAP_LOADING"
	_load_started_ms = Time.get_ticks_msec()
	_map_view.province_clicked.connect(_on_province_clicked)
	_map_view.province_double_clicked.connect(_show_province)
	_info_panel.closed.connect(func() -> void: _map_view.set_selected_province(MapView.NO_SELECTION))
	_country_panel.closed.connect(func() -> void: _map_view.set_selected_country(""))
	_map_modes = MapModeRegistry.from_definitions(DataLoader.get_category("map_modes"))
	_mode_context = MapModeContext.from_game_data()
	_mode_bar.set_modes(_map_modes.modes)
	_mode_bar.mode_selected.connect(set_map_mode)
	_mode_bar.visible = false
	_legend.visible = false
	_selection_panel.visible = false
	_selection_panel.country_selected.connect(_on_country_selected)
	_selection_panel.play_requested.connect(_on_play_requested)
	_top_bar.economy_requested.connect(_economy_panel.toggle)
	_top_bar.budget_requested.connect(_budget_panel.toggle)
	_top_bar.markets_requested.connect(_markets_panel.toggle)
	_top_bar.trade_requested.connect(_trade_panel.toggle)
	_top_bar.energy_requested.connect(_energy_panel.toggle)
	_top_bar.investment_requested.connect(_investment_panel.toggle)
	_top_bar.society_requested.connect(_society_panel.toggle)
	_top_bar.politics_requested.connect(_politics_panel.toggle)
	_top_bar.laws_requested.connect(_laws_panel.toggle)
	_top_bar.government_requested.connect(_government_panel.toggle)
	EventBus.sim_event_raised.connect(_on_sim_event)
	EventBus.month_passed.connect(_on_month_passed)
	EventBus.command_executed.connect(func(_command: Command) -> void: _refresh_live_map_mode())
	EventBus.year_passed.connect(_on_year_passed)
	_thread = Thread.new()
	_thread.start(func() -> ProvinceMapData: return ProvinceMapData.from_png_file(image_path))


func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		_finish_loading()
	_update_debug()


func _unhandled_input(event: InputEvent) -> void:
	if _is_selecting():
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			get_tree().change_scene_to_file(TITLE_SCENE)
		return
	if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		get_viewport().set_input_as_handled()
		_cycle_map_mode(-1 if event.is_action_pressed("ui_focus_prev") else 1)
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		var panels: Array[InfoPanel] = [_info_panel, _country_panel, _economy_panel, _budget_panel, _markets_panel,
			_trade_panel, _energy_panel, _investment_panel, _society_panel,
			_politics_panel, _laws_panel, _government_panel]
		if panels.any(func(panel: InfoPanel) -> bool: return panel.visible):
			for panel: InfoPanel in panels:
				panel.close()
		else:
			get_tree().change_scene_to_file(TITLE_SCENE)


func _exit_tree() -> void:
	GameClock.set_running(false)
	GameClock.set_paused(true)
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _finish_loading() -> void:
	var data: ProvinceMapData = _thread.wait_to_finish()
	_thread = null
	if data == null:
		GameLog.error(SOURCE, "Impossible de charger l'image des provinces.")
		_loading_label.text = "MAP_LOAD_ERROR"
		return
	_map_view.setup(data, _mode_context.new_colors())
	set_map_mode(_current_mode_id)
	_loading_label.visible = false
	if GameState.sim.player_tag.is_empty():
		_enter_selection()
	else:
		_start_playing()
	GameLog.info(SOURCE, "Carte %d × %d chargée en %d ms." % [data.width, data.height,
		Time.get_ticks_msec() - _load_started_ms])
	# Les textures partent vers la carte graphique au rendu suivant.
	await get_tree().process_frame
	await get_tree().process_frame
	GameLog.info(SOURCE, "Mémoire graphique des textures : %d Mo." % roundi(
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / BYTES_PER_MEGABYTE))


func _is_selecting() -> bool:
	return _selection_panel.visible


## Sélection du pays : le temps reste arrêté, seuls la carte et les panneaux de choix sont affichés.
func _enter_selection() -> void:
	GameClock.set_running(false)
	_top_bar.visible = false
	_mode_bar.visible = false
	_legend.visible = false
	_debug_label.visible = false
	_selection_panel.visible = true


func _start_playing() -> void:
	_selection_panel.visible = false
	_debug_label.visible = true
	_mode_bar.visible = true
	set_map_mode(_current_mode_id)
	_top_bar.visible = true
	_top_bar.refresh()
	GameClock.set_running(true)


## Démarre la partie sur le pays choisi, caméra centrée sur sa capitale.
func _on_play_requested(tag: String) -> void:
	GameState.new_game(GameState.sim.game_seed, StringName(tag))
	_map_view.set_selected_country("")
	_focus_capital(tag, float(DataLoader.get_define("camera.capital_zoom")))
	_start_playing()


## Pays choisi dans la liste ou sur la carte : mis en évidence ; depuis la liste, la carte se centre dessus.
func _on_country_selected(tag: String, from_list: bool) -> void:
	_map_view.set_selected_country(tag)
	if from_list and _map_view.camera != null:
		_focus_capital(tag, _map_view.camera.zoom)


func _focus_capital(tag: String, zoom: float) -> void:
	var capital := int(DataLoader.get_entry("countries", tag).get("capital", 0))
	var center: Array = DataLoader.get_entry("provinces", str(capital)).get("center", [])
	if center.size() >= 2:
		_map_view.focus_on(Vector2(float(center[0]), float(center[1])), zoom)


## Les modes qui dépendent de la partie (commerce) suivent les décisions et les mois.
func _refresh_live_map_mode() -> void:
	if LIVE_MAP_MODES.has(_current_mode_id):
		set_map_mode(_current_mode_id)


func _on_month_passed(date: GameDate) -> void:
	_refresh_live_map_mode()
	if date.month != 1:
		_notify(tr("NOTIFY_NEW_MONTH") % [tr(DateFormat.month_key(date.month)), date.year])


## Événements économiques du pays joué : changement de note, défaut de paiement, FMI.
func _on_sim_event(event: Dictionary) -> void:
	# Événements mondiaux : visibles quel que soit le pays joué.
	match event.get("type"):
		ResourceSystem.EVENT_STRAIT_CLOSED:
			_notify(tr("NOTIFY_STRAIT_CLOSED") % tr(_strait_name_key(str(event.get("strait", "")))))
			return
		ResourceSystem.EVENT_STRAIT_OPENED:
			_notify(tr("NOTIFY_STRAIT_OPENED") % tr(_strait_name_key(str(event.get("strait", "")))))
			return
	if event.get("type") == CrisisSystem.EVENT_COUP or (event.get("type") == CrisisSystem.EVENT_STARTED
			and str(event.get("crisis", "")) == CrisisSystem.CIVIL_WAR):
		var country := DataLoader.get_entry("countries", str(event.get("tag", "")))
		var key := "NOTIFY_CIVIL_WAR" if event.get("type") == CrisisSystem.EVENT_STARTED \
			else "NOTIFY_COUP_SUCCESS" if bool(event.get("success", false)) else "NOTIFY_COUP_FAILED"
		_notify(tr(key) % tr(str(country.get("name_key", ""))))
		return
	if event.get("type") == ElectionSystem.EVENT_FRAUD_DETECTED:
		var country := DataLoader.get_entry("countries", str(event.get("tag", "")))
		_notify(tr("NOTIFY_FRAUD_DETECTED") % tr(str(country.get("name_key", ""))))
		return
	if str(event.get("tag", "")) != str(GameState.sim.player_tag):
		return
	match event.get("type"):
		EconomySystem.EVENT_RATING_CHANGED:
			var key := "NOTIFY_RATING_UP" if bool(event.get("upgrade", false)) else "NOTIFY_RATING_DOWN"
			_notify(tr(key) % [event.get("old", ""), event.get("new", "")])
		EconomySystem.EVENT_DEBT_CRISIS:
			_notify(tr("NOTIFY_DEBT_CRISIS"))
		EconomySystem.EVENT_CRISIS_ENDED:
			_notify(tr("NOTIFY_CRISIS_ENDED") % event.get("new", ""))
		EconomySystem.EVENT_IMF_PROGRAM:
			_notify(tr("NOTIFY_IMF_PROGRAM"))
		EconomySystem.EVENT_IMF_ENDED:
			_notify(tr("NOTIFY_IMF_ENDED"))
		EnergySystem.EVENT_PROJECT_DONE:
			var building := DataLoader.get_entry("buildings", str(event.get("building", "")))
			var province := DataLoader.get_entry("provinces", str(event.get("province", "")))
			_notify(tr("NOTIFY_PROJECT_DONE") % [tr(str(building.get("name_key", ""))), tr(str(province.get("name_key", "")))])
		InvestmentSystem.EVENT_NATIONALIZED, InvestmentSystem.EVENT_EXPROPRIATED, InvestmentSystem.EVENT_PRIVATIZED:
			var sector := DataLoader.get_entry("economy_sectors", str(event.get("sector", "")))
			_notify(tr("NOTIFY_%s" % str(event.get("type")).to_upper()) % tr(str(sector.get("name_key", ""))))
		EnergySystem.EVENT_BLACKOUT:
			_notify(tr("NOTIFY_BLACKOUT"))
		ElectionSystem.EVENT_ELECTION:
			_notify(_election_text(event))
		ConstitutionSystem.EVENT_REFORM_ADOPTED, ConstitutionSystem.EVENT_REFORM_REJECTED:
			var reform := ConstitutionSystem.definition_of(GameState.sim, str(event.get("reform", "")))
			var key := "NOTIFY_REFORM_ADOPTED" if event.get("type") == ConstitutionSystem.EVENT_REFORM_ADOPTED \
				else "NOTIFY_REFORM_REJECTED"
			_notify(tr(key) % tr(str(reform.get("name_key", ""))))
		ConstitutionSystem.EVENT_REFERENDUM_CALLED:
			_notify(tr("NOTIFY_REFERENDUM_CALLED"))
		ConstitutionSystem.EVENT_REFERENDUM_HELD:
			var key := "NOTIFY_REFERENDUM_YES" if bool(event.get("passed", false)) else "NOTIFY_REFERENDUM_NO"
			_notify(tr(key) % NumberFormat.decimal(float(event.get("yes", 0.0)), 1, Localization.get_locale()))
		ConstitutionSystem.EVENT_EMERGENCY:
			_notify(tr("NOTIFY_EMERGENCY_ON" if bool(event.get("active", false)) else "NOTIFY_EMERGENCY_OFF"))
		ChangeLawCommand.EVENT_LAW_PASSED, ChangeLawCommand.EVENT_LAW_REJECTED:
			var law: Dictionary = (GameState.sim.politics_definitions.get("laws", {}) as Dictionary).get(str(event.get("law", "")), {})
			var key := "NOTIFY_LAW_PASSED" if event.get("type") == ChangeLawCommand.EVENT_LAW_PASSED else "NOTIFY_LAW_REJECTED"
			_notify(tr(key) % tr(str(law.get("name_key", ""))))
		GovernmentSystem.EVENT_SCANDAL, GovernmentSystem.EVENT_RESIGNATION:
			var portfolio: Dictionary = (GameState.sim.politics_definitions.get("portfolios", {}) as Dictionary).get(
				str(event.get("portfolio", "")), {})
			var key := "NOTIFY_MINISTER_SCANDAL" if event.get("type") == GovernmentSystem.EVENT_SCANDAL \
				else "NOTIFY_MINISTER_RESIGNED"
			_notify(tr(key) % tr(str(portfolio.get("name_key", ""))))
		MediaSystem.EVENT_DISINFORMATION:
			_notify(tr("NOTIFY_DISINFORMATION_EXPOSED" if bool(event.get("exposed", false)) else "NOTIFY_DISINFORMATION_DONE"))
		CrisisSystem.EVENT_STARTED:
			var definition: Dictionary = (GameState.sim.politics_definitions.get("crises", {}) as Dictionary).get(
				str(event.get("crisis", "")), {})
			var group := DataLoader.get_entry("social_groups", str(event.get("group", "")))
			_notify(tr("NOTIFY_UNREST") % [tr(str(definition.get("name_key", ""))), tr(str(group.get("name_key", "")))])
		PoliticsSystem.EVENT_PROMISE:
			var group := DataLoader.get_entry("social_groups", str(event.get("group", "")))
			var key := "NOTIFY_PROMISE_KEPT" if str(event.get("outcome", "")) == "kept" else "NOTIFY_PROMISE_BROKEN"
			_notify(tr(key) % tr(str(group.get("name_key", ""))))
		TradeSystem.EVENT_AGREEMENT_LEFT:
			var agreement := DataLoader.get_entry("trade_agreements", str(event.get("agreement", "")))
			_notify(tr("NOTIFY_AGREEMENT_LEFT") % tr(str(agreement.get("name_key", ""))))


## « Législatives : le PRD arrive en tête. Nouveau gouvernement dirigé par l'UC. »
func _election_text(event: Dictionary) -> String:
	var parties := DataLoader.repository.resolve_ref("names#parties")
	var winner := str((parties.get(str(event.get("winner", "")), {}) as Dictionary).get("abbreviation", ""))
	var presidential := str(event.get("kind", "")) == ElectionSystem.KIND_PRESIDENTIAL
	var text := tr("NOTIFY_PRESIDENTIAL_WON" if presidential else "NOTIFY_LEGISLATIVE_WON") % winner
	if bool(event.get("managed", false)) or winner.is_empty():
		return tr("NOTIFY_ELECTION_MANAGED")
	var politics := GameState.sim.get_country(str(event.get("tag", ""))).politics
	if bool(event.get("government_changed", false)):
		var ruling := str((parties.get(politics.ruling_party(), {}) as Dictionary).get("abbreviation", ""))
		text += " " + tr("NOTIFY_NEW_GOVERNMENT") % ruling
	elif not presidential:
		text += " " + tr("NOTIFY_GOVERNMENT_STAYS")
	return text


func _strait_name_key(strait_id: String) -> String:
	return str(DataLoader.get_entry("straits", strait_id).get("name_key", strait_id))


func _on_year_passed(date: GameDate) -> void:
	_notify(tr("NOTIFY_NEW_YEAR") % date.year)


## Message temporaire sous la barre supérieure.
func _notify(text: String) -> void:
	_notification_label.text = text
	_notification_label.visible = true
	_notification_timer = get_tree().create_timer(float(DataLoader.get_define("time.notification_seconds")))
	var timer := _notification_timer
	timer.timeout.connect(func() -> void:
		if _notification_timer == timer:
			_notification_label.visible = false)


func set_map_mode(mode_id: String) -> void:
	var mode := _map_modes.get_mode(mode_id)
	if mode == null or _map_view.camera == null:
		return
	_current_mode_id = mode_id
	_mode_context.refresh_from_simulation(GameState.sim)
	_map_view.set_province_colors(mode.compute_colors(_mode_context))
	_mode_bar.set_current(mode_id)
	_legend.show_mode(mode, _mode_context)


func _cycle_map_mode(step: int) -> void:
	var count := _map_modes.modes.size()
	if count == 0:
		return
	var index := posmod(_map_modes.index_of(_current_mode_id) + step, count)
	set_map_mode(_map_modes.modes[index].id)


## Clic simple : fiche du pays propriétaire ; mers et terres sans propriétaire ouvrent leur propre fiche.
func _on_province_clicked(province_id: int) -> void:
	var province: Dictionary = DataLoader.get_entry("provinces", str(province_id))
	var owner := str(province.get("owner", ""))
	if _is_selecting():
		_selection_panel.select_country(owner)
		return
	var info := CountryInfo.build(owner, DataLoader.get_category("countries"),
		DataLoader.get_category("provinces"), DataLoader.get_category("names"),
		DataLoader.get_category("regimes"), DataLoader.get_category("ideologies"),
		DataLoader.get_category("names/cultures"), GameState.sim.date.year)
	if info == null:
		_show_province(province_id)
		return
	info.apply_economy(GameState.sim)
	info.apply_politics(GameState.sim, DataLoader.get_category("names"), DataLoader.get_category("ideologies"),
		DataLoader.get_category("names/cultures"))
	info.apply_diplomacy(GameState.sim)
	_info_panel.close()
	_map_view.set_selected_province(MapView.NO_SELECTION)
	_map_view.set_selected_country(owner)
	_country_panel.show_country(info)


## Double-clic (ou clic sur une mer ou une terre sans propriétaire) : fiche de la province ou de la zone.
func _show_province(province_id: int) -> void:
	if _is_selecting():
		return
	var info := ProvinceInfo.build(province_id, DataLoader.get_category("provinces"),
		DataLoader.get_category("countries"), DataLoader.get_category("terrains"),
		DataLoader.get_category("resources"), DataLoader.get_category("sea_zones"),
		DataLoader.get_category("straits"))
	_country_panel.close()
	if info == null:
		_map_view.set_selected_province(MapView.NO_SELECTION)
		_info_panel.close()
		return
	_map_view.set_selected_province(province_id)
	_info_panel.show_province(info)


func _update_debug() -> void:
	var camera := _map_view.camera
	if camera == null:
		_debug_label.text = ""
		return
	var map_position := camera.screen_to_map(_map_view.get_local_mouse_position())
	var longitude := map_position.x / camera.map_size.x * DEGREES_PER_TURN - DEGREES_HALF_TURN
	var latitude := DEGREES_HALF_TURN * 0.5 - map_position.y / camera.map_size.y * DEGREES_HALF_TURN
	_debug_label.text = tr("DEBUG_MAP_INFO") % [Engine.get_frames_per_second(), camera.zoom, latitude, longitude]

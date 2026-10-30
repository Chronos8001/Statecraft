extends Control
## Écran de jeu : charge la carte dans un thread puis l'affiche. Sans pays joué, commence par
## la sélection du pays (temps arrêté). Échap revient à l'écran titre.

const SOURCE := "GameScreen"
const TITLE_SCENE := "res://ui/title/title_screen.tscn"
const DEGREES_PER_TURN := 360.0
const DEGREES_HALF_TURN := 180.0
const BYTES_PER_MEGABYTE := 1048576.0
const DEFAULT_MAP_MODE := "political"

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
	EventBus.month_passed.connect(_on_month_passed)
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
		if _info_panel.visible or _country_panel.visible:
			_info_panel.close()
			_country_panel.close()
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


func _on_month_passed(date: GameDate) -> void:
	if date.month != 1:
		_notify(tr("NOTIFY_NEW_MONTH") % [tr(DateFormat.month_key(date.month)), date.year])


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

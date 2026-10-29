extends Control
## Écran de jeu : charge la carte dans un thread puis l'affiche. Échap revient à l'écran titre.

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

@onready var _map_view: MapView = %MapView
@onready var _loading_label: Label = %LoadingLabel
@onready var _debug_label: Label = %DebugLabel
@onready var _info_panel: ProvinceInfoPanel = %ProvinceInfoPanel
@onready var _mode_bar: MapModeBar = %MapModeBar
@onready var _legend: MapLegend = %MapLegend


func _ready() -> void:
	var map_info: Dictionary = DataLoader.get_category("map").get("map", {})
	var image_path := str(map_info.get("provinces_image", ""))
	_loading_label.text = "MAP_LOADING"
	_load_started_ms = Time.get_ticks_msec()
	_map_view.province_clicked.connect(_on_province_clicked)
	_info_panel.closed.connect(func() -> void: _map_view.set_selected_province(MapView.NO_SELECTION))
	_map_modes = MapModeRegistry.from_definitions(DataLoader.get_category("map_modes"))
	_mode_context = MapModeContext.from_game_data()
	_mode_bar.set_modes(_map_modes.modes)
	_mode_bar.mode_selected.connect(set_map_mode)
	_mode_bar.visible = false
	_legend.visible = false
	_thread = Thread.new()
	_thread.start(func() -> ProvinceMapData: return ProvinceMapData.from_png_file(image_path))


func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		_finish_loading()
	_update_debug()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		get_viewport().set_input_as_handled()
		_cycle_map_mode(-1 if event.is_action_pressed("ui_focus_prev") else 1)
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _info_panel.visible:
			_info_panel.close()
		else:
			get_tree().change_scene_to_file(TITLE_SCENE)


func _exit_tree() -> void:
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
	_mode_bar.visible = true
	_loading_label.visible = false
	GameLog.info(SOURCE, "Carte %d × %d chargée en %d ms." % [data.width, data.height,
		Time.get_ticks_msec() - _load_started_ms])
	# Les textures partent vers la carte graphique au rendu suivant.
	await get_tree().process_frame
	await get_tree().process_frame
	GameLog.info(SOURCE, "Mémoire graphique des textures : %d Mo." % roundi(
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / BYTES_PER_MEGABYTE))


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


func _on_province_clicked(province_id: int) -> void:
	var info := ProvinceInfo.build(province_id, DataLoader.get_category("provinces"),
		DataLoader.get_category("countries"), DataLoader.get_category("terrains"),
		DataLoader.get_category("resources"))
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

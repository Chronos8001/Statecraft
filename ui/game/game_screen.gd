extends Control
## Écran de jeu : charge la carte dans un thread puis l'affiche. Échap revient à l'écran titre.

const SOURCE := "GameScreen"
const TITLE_SCENE := "res://ui/title/title_screen.tscn"
const DEGREES_PER_TURN := 360.0
const DEGREES_HALF_TURN := 180.0
const BYTES_PER_MEGABYTE := 1048576.0

var _thread: Thread
var _load_started_ms: int = 0

@onready var _map_view: MapView = %MapView
@onready var _loading_label: Label = %LoadingLabel
@onready var _debug_label: Label = %DebugLabel


func _ready() -> void:
	var map_info: Dictionary = DataLoader.get_category("map").get("map", {})
	var image_path := str(map_info.get("provinces_image", ""))
	_loading_label.text = "MAP_LOADING"
	_load_started_ms = Time.get_ticks_msec()
	_thread = Thread.new()
	_thread.start(func() -> ProvinceMapData: return ProvinceMapData.from_png_file(image_path))


func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		_finish_loading()
	_update_debug()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
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
	var provinces := DataLoader.get_category("provinces")
	var countries := DataLoader.get_category("countries")
	var max_id := int(DataLoader.get_category("map")["map"]["province_count"])
	var colors := ProvinceLookup.political_colors(provinces, countries, max_id,
		Color.html(str(DataLoader.get_define("map_colors.sea"))),
		Color.html(str(DataLoader.get_define("map_colors.unowned"))))
	_map_view.setup(data, colors)
	_map_view.grab_focus()
	_loading_label.visible = false
	GameLog.info(SOURCE, "Carte %d × %d chargée en %d ms." % [data.width, data.height,
		Time.get_ticks_msec() - _load_started_ms])
	# Les textures partent vers la carte graphique au rendu suivant.
	await get_tree().process_frame
	await get_tree().process_frame
	GameLog.info(SOURCE, "Mémoire graphique des textures : %d Mo." % roundi(
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / BYTES_PER_MEGABYTE))


func _update_debug() -> void:
	var camera := _map_view.camera
	if camera == null:
		_debug_label.text = ""
		return
	var map_position := camera.screen_to_map(_map_view.get_local_mouse_position())
	var longitude := map_position.x / camera.map_size.x * DEGREES_PER_TURN - DEGREES_HALF_TURN
	var latitude := DEGREES_HALF_TURN * 0.5 - map_position.y / camera.map_size.y * DEGREES_HALF_TURN
	_debug_label.text = tr("DEBUG_MAP_INFO") % [Engine.get_frames_per_second(), camera.zoom, latitude, longitude]

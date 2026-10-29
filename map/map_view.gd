class_name MapView
extends Control
## Affiche la carte des provinces (shader) et pilote la caméra : molette, clavier, glisser
## (clic droit ou molette enfoncée) et bord de l'écran.

signal camera_changed
## Clic gauche sur la carte : identifiant de la province (0 = eau).
signal province_clicked(province_id: int)

const NO_SELECTION := -1

var camera: MapCameraState
var selected_province: int = NO_SELECTION
var map_data: ProvinceMapData
var _material: ShaderMaterial
var _dragging: bool = false
var _zoom_step: float = 1.0
var _key_zoom_rate: float = 0.0
var _key_pan_speed: float = 0.0
var _edge_margin: float = 0.0
var _edge_speed: float = 0.0

var _province_border_min_zoom: float = 0.0
var _province_border_full_zoom: float = 0.0

@onready var _surface: ColorRect = $Surface
@onready var _labels: CountryLabelLayer = $Labels
@onready var _straits: StraitLayer = $Straits


func _ready() -> void:
	InputActions.register_defaults()
	_material = _surface.material as ShaderMaterial
	_zoom_step = float(DataLoader.get_define("camera.zoom_step"))
	_key_zoom_rate = float(DataLoader.get_define("camera.key_zoom_steps_per_second"))
	_key_pan_speed = float(DataLoader.get_define("camera.key_pan_speed"))
	_edge_margin = float(DataLoader.get_define("camera.edge_scroll_margin"))
	_edge_speed = float(DataLoader.get_define("camera.edge_scroll_speed"))
	resized.connect(_on_resized)
	set_process(false)


func setup(data: ProvinceMapData, colors: PackedColorArray) -> void:
	map_data = data
	var map_size := Vector2(data.width, data.height)
	camera = MapCameraState.new(map_size, size, float(DataLoader.get_define("camera.max_zoom")))
	var start: Array = DataLoader.get_define("camera.start_center")
	camera.look_at(Vector2(float(start[0]), float(start[1])), float(DataLoader.get_define("camera.start_zoom")))
	_material.set_shader_parameter("province_ids", ImageTexture.create_from_image(data.id_image))
	_material.set_shader_parameter("map_size", map_size)
	_material.set_shader_parameter("background_color", Color.html(str(DataLoader.get_define("map_colors.background"))))
	_material.set_shader_parameter("selection_color", Color.html(str(DataLoader.get_define("map_style.selection_color"))))
	_material.set_shader_parameter("selection_strength", float(DataLoader.get_define("map_style.selection_strength")))
	_apply_border_style()
	set_selected_province(NO_SELECTION)
	set_province_colors(colors)
	set_province_owners(DataLoader.get_category("provinces"), DataLoader.get_category("countries"))
	var provinces := DataLoader.get_category("provinces")
	var owner_at := func(map_position: Vector2) -> String:
		var province: Dictionary = provinces.get(str(data.get_province_at(map_position)), {})
		return str(province.get("owner", ""))
	_labels.setup(CountryLabelLayout.compute_all(provinces, data.width,
		float(DataLoader.get_define("map_style.label_max_bend")), owner_at),
		DataLoader.get_category("countries"), camera)
	_straits.setup(DataLoader.get_category("straits"), camera)
	_update_camera()
	set_process(true)


## Remplace les couleurs affichées (une couleur par id de province).
func set_province_colors(colors: PackedColorArray) -> void:
	var lookup := ImageTexture.create_from_image(ProvinceLookup.build_image(colors))
	_material.set_shader_parameter("province_colors", lookup)


## Recalcule les frontières de pays (à appeler quand un propriétaire change).
func set_province_owners(provinces: Dictionary, countries: Dictionary) -> void:
	var owners := ProvinceLookup.owner_indices(provinces, countries, DataLoader.get_category("sea_zones"),
		int(DataLoader.get_category("map")["map"]["max_id"]))
	_material.set_shader_parameter("province_owners", ImageTexture.create_from_image(ProvinceLookup.build_image(owners)))


func set_selected_province(province_id: int) -> void:
	selected_province = province_id
	_material.set_shader_parameter("selected_province", province_id)


## Province sous un point de l'écran (0 = eau ou carte non chargée).
func province_at_screen(screen_position: Vector2) -> int:
	if camera == null or map_data == null:
		return 0
	return map_data.get_province_at(camera.screen_to_map(screen_position))


func _gui_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					province_clicked.emit(province_at_screen(button.position))
				accept_event()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					var steps := button.factor if button.factor > 0.0 else 1.0
					var direction := 1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
					camera.zoom_at(button.position, pow(_zoom_step, steps * direction))
					_update_camera()
				accept_event()
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = button.pressed
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		camera.pan_screen((event as InputEventMouseMotion).relative)
		_update_camera()
		accept_event()


func _process(delta: float) -> void:
	var direction := Input.get_vector(InputActions.MAP_PAN_LEFT, InputActions.MAP_PAN_RIGHT,
		InputActions.MAP_PAN_UP, InputActions.MAP_PAN_DOWN)
	var moved := false
	if direction != Vector2.ZERO:
		camera.pan_screen(-direction * _key_pan_speed * delta)
		moved = true
	var edge := _edge_direction()
	if edge != Vector2.ZERO:
		camera.pan_screen(-edge * _edge_speed * delta)
		moved = true
	var zoom_input := Input.get_axis(InputActions.MAP_ZOOM_OUT, InputActions.MAP_ZOOM_IN)
	if zoom_input != 0.0:
		camera.zoom_at(size * 0.5, pow(_zoom_step, zoom_input * _key_zoom_rate * delta))
		moved = true
	if moved:
		_update_camera()


func _edge_direction() -> Vector2:
	if _dragging or not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var mouse := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(mouse):
		return Vector2.ZERO
	var direction := Vector2.ZERO
	if mouse.x <= _edge_margin:
		direction.x = -1.0
	elif mouse.x >= size.x - _edge_margin:
		direction.x = 1.0
	if mouse.y <= _edge_margin:
		direction.y = -1.0
	elif mouse.y >= size.y - _edge_margin:
		direction.y = 1.0
	return direction


func _on_resized() -> void:
	if camera != null:
		camera.set_viewport_size(size)
		_update_camera()


func _apply_border_style() -> void:
	var province_color := Color.html(str(DataLoader.get_define("map_style.province_border_color")))
	province_color.a = float(DataLoader.get_define("map_style.province_border_opacity"))
	var country_color := Color.html(str(DataLoader.get_define("map_style.country_border_color")))
	country_color.a = float(DataLoader.get_define("map_style.country_border_opacity"))
	_material.set_shader_parameter("province_border_color", province_color)
	_material.set_shader_parameter("country_border_color", country_color)
	var sea_color := Color.html(str(DataLoader.get_define("map_style.sea_border_color")))
	sea_color.a = float(DataLoader.get_define("map_style.sea_border_opacity"))
	_material.set_shader_parameter("sea_border_color", sea_color)
	_material.set_shader_parameter("province_border_width", float(DataLoader.get_define("map_style.province_border_width")))
	_material.set_shader_parameter("country_border_width", float(DataLoader.get_define("map_style.country_border_width")))
	_material.set_shader_parameter("smooth_min_zoom", float(DataLoader.get_define("map_style.smooth_min_zoom")))
	_province_border_min_zoom = float(DataLoader.get_define("map_style.province_border_min_zoom"))
	_province_border_full_zoom = float(DataLoader.get_define("map_style.province_border_full_zoom"))


func _update_camera() -> void:
	_material.set_shader_parameter("viewport_size", size)
	_material.set_shader_parameter("camera_center", camera.center)
	_material.set_shader_parameter("zoom", camera.zoom)
	_material.set_shader_parameter("province_border_alpha",
		smoothstep(_province_border_min_zoom, _province_border_full_zoom, camera.zoom))
	_labels.queue_redraw()
	_straits.queue_redraw()
	camera_changed.emit()

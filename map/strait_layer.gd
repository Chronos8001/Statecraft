class_name StraitLayer
extends Control
## Détroits et canaux : trait entre leurs deux extrémités, losange au milieu, nom en zoom rapproché.

const KIND_CANAL := "canal"
const OUTLINE_COLOR := Color(0.04, 0.05, 0.07, 0.85)
const OUTLINE_WIDTH := 2.0
const LABEL_OUTLINE_SIZE := 4
const LABEL_GAP := 6.0

var _straits: Dictionary = {}
var _camera: MapCameraState
var _font: Font
var _strait_color: Color
var _canal_color: Color
var _line_width: float = 0.0
var _marker_size: float = 0.0
var _label_min_zoom: float = 0.0
var _label_size: int = 0


func _ready() -> void:
	_font = get_theme_default_font()
	EventBus.locale_changed.connect(func(_locale: String) -> void: queue_redraw())


func setup(straits: Dictionary, camera: MapCameraState) -> void:
	_straits = straits
	_camera = camera
	_strait_color = Color.html(str(DataLoader.get_define("map_style.strait_color")))
	_canal_color = Color.html(str(DataLoader.get_define("map_style.canal_color")))
	_line_width = float(DataLoader.get_define("map_style.strait_line_width"))
	_marker_size = float(DataLoader.get_define("map_style.strait_marker_size"))
	_label_min_zoom = float(DataLoader.get_define("map_style.strait_label_min_zoom"))
	_label_size = int(DataLoader.get_define("map_style.strait_label_size"))
	queue_redraw()


func _draw() -> void:
	if _camera == null:
		return
	var screen := Rect2(Vector2.ZERO, size).grow(_marker_size * 4.0)
	for strait_id: String in _straits.keys():
		var strait: Dictionary = _straits[strait_id]
		var ends: Array = strait["ends"]
		var start_map := Vector2(float(ends[0][0]), float(ends[0][1]))
		var end_map := Vector2(float(ends[1][0]), float(ends[1][1]))
		var delta := end_map - start_map
		delta.x = wrapf(delta.x, -_camera.map_size.x * 0.5, _camera.map_size.x * 0.5)
		var start := _camera.map_to_screen(start_map)
		var end := start + delta * _camera.zoom
		var middle := (start + end) * 0.5
		if not screen.has_point(middle):
			continue
		var color := _canal_color if strait.get("kind", "") == KIND_CANAL else _strait_color
		draw_line(start, end, OUTLINE_COLOR, _line_width + OUTLINE_WIDTH, true)
		draw_line(start, end, color, _line_width, true)
		var marker := PackedVector2Array([
			middle + Vector2(0, -_marker_size), middle + Vector2(_marker_size, 0),
			middle + Vector2(0, _marker_size), middle + Vector2(-_marker_size, 0)])
		draw_colored_polygon(marker, color)
		marker.append(marker[0])
		draw_polyline(marker, OUTLINE_COLOR, OUTLINE_WIDTH / 2.0, true)
		if _camera.zoom >= _label_min_zoom:
			var text := tr(str(strait.get("name_key", "")))
			var position := middle + Vector2(_marker_size + LABEL_GAP, _label_size * 0.35)
			draw_string_outline(_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size,
				LABEL_OUTLINE_SIZE, OUTLINE_COLOR)
			draw_string(_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size, color)

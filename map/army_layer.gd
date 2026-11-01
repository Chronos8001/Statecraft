class_name ArmyLayer
extends Control
## Pions des groupes d'armées et des flottes sur la carte : symbole OTAN (cadre selon l'appartenance au pays joué
## et le milieu), effectifs ou état dessous, trajet en pointillés pour un pion en mouvement. Les pions sont
## fournis par l'écran de jeu : [{id, kind (army, fleet), position (carte), affiliation, label, selected,
## path (positions de carte)}].

const OUTLINE_COLOR := Color(0.04, 0.05, 0.07, 0.85)
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)
const LABEL_OUTLINE_SIZE := 4
const DASH := 6.0
const SELECTION_MARGIN := 3.0
const ARMY := "army"
const FLEET := "fleet"

var _camera: MapCameraState
var _tokens: Array[Dictionary] = []
var _font: Font
var _colors: Dictionary = {}
var _token_size: Vector2 = Vector2.ZERO
var _min_zoom: float = 0.0
var _label_size: int = 0
var _path_color: Color


func _ready() -> void:
	_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(camera: MapCameraState) -> void:
	_camera = camera
	_colors = DataLoader.get_define("military_symbols", {})
	var size_values: Array = DataLoader.get_define("map_style.army_token_size", [40, 32])
	_token_size = Vector2(float(size_values[0]), float(size_values[1]))
	_min_zoom = float(DataLoader.get_define("map_style.army_min_zoom", 0.0))
	_label_size = int(DataLoader.get_define("map_style.army_label_size", 12))
	_path_color = Color.html(str(DataLoader.get_define("map_style.army_path_color", "#FFE070")))
	queue_redraw()


func set_tokens(tokens: Array[Dictionary]) -> void:
	_tokens = tokens
	queue_redraw()


## Pion sous un point de l'écran ({} : aucun). Les pions dessinés en dernier sont testés d'abord.
func token_at(screen_position: Vector2) -> Dictionary:
	if _camera == null:
		return {}
	for index: int in range(_tokens.size() - 1, -1, -1):
		var token: Dictionary = _tokens[index]
		if _visible(token) and _rect(token).has_point(screen_position):
			return token
	return {}


func _visible(token: Dictionary) -> bool:
	return _camera.zoom >= _min_zoom or str(token.get("affiliation", "")) == NatoSymbol.FRIEND


func _rect(token: Dictionary) -> Rect2:
	var center := _camera.map_to_screen(token["position"])
	return Rect2(center - _token_size / 2.0, _token_size)


func _draw() -> void:
	if _camera == null:
		return
	var screen := Rect2(Vector2.ZERO, size).grow(_token_size.x)
	for token: Dictionary in _tokens:
		if not _visible(token):
			continue
		var rect := _rect(token)
		var path: Array = token.get("path", [])
		if not path.is_empty():
			var points := PackedVector2Array([rect.get_center()])
			for map_position: Vector2 in path:
				points.append(_camera.map_to_screen(map_position))
			for index: int in points.size() - 1:
				_dashed(points[index], points[index + 1])
		if not screen.intersects(rect):
			continue
		if bool(token.get("selected", false)):
			draw_rect(rect.grow(SELECTION_MARGIN), SELECTED_COLOR, false, 2.0)
		var fleet := str(token.get("kind", "")) == FLEET
		NatoSymbol.draw_symbol(self, rect, NatoSymbol.SEA if fleet else NatoSymbol.LAND, str(token["affiliation"]),
			NatoSymbol.INFANTRY, NatoSymbol.FLEET if fleet else NatoSymbol.ARMY_GROUP, _colors, _font, 1.5)
		var text := str(token.get("label", ""))
		if not text.is_empty():
			var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size)
			var position := Vector2(rect.get_center().x - text_size.x / 2.0, rect.end.y + _label_size)
			draw_string_outline(_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size, LABEL_OUTLINE_SIZE,
				OUTLINE_COLOR)
			draw_string(_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size, Color.WHITE)


func _dashed(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var direction := (to - from) / length
	var travelled := 0.0
	while travelled < length:
		var end := minf(travelled + DASH, length)
		draw_line(from + direction * travelled, from + direction * end, _path_color, 2.0, true)
		travelled += DASH * 2.0

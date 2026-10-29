class_name CountryLabelLayer
extends Control
## Dessine les noms de pays le long de leur courbe, par-dessus la carte.
## Un nom n'est affiché que si sa taille à l'écran est lisible (ni trop petite, ni trop grande).

## Taille de référence pour mesurer la largeur du texte.
const MEASURE_SIZE := 100
## Fondu près des tailles limites (part de la plage).
const FADE_RATIO := 0.25

var _layouts: Dictionary = {}
var _countries: Dictionary = {}
var _camera: MapCameraState
var _font: Font
var _texts: Dictionary = {}
var _unit_widths: Dictionary = {}
var _color: Color
var _outline_color: Color
var _outline_size: int = 0
var _min_size: float = 0.0
var _max_size: float = 0.0
var _fill_ratio: float = 0.0
var _thickness_ratio: float = 0.0
var _letter_spacing: float = 0.0


func _ready() -> void:
	_font = get_theme_default_font()
	EventBus.locale_changed.connect(func(_locale: String) -> void:
		_texts.clear()
		_unit_widths.clear()
		queue_redraw())


func setup(layouts: Dictionary, countries: Dictionary, camera: MapCameraState) -> void:
	_layouts = layouts
	_countries = countries
	_camera = camera
	_color = Color.html(str(DataLoader.get_define("map_style.label_color")))
	_color.a = float(DataLoader.get_define("map_style.label_opacity"))
	_outline_color = Color.html(str(DataLoader.get_define("map_style.label_outline_color")))
	_outline_color.a = float(DataLoader.get_define("map_style.label_outline_opacity"))
	_outline_size = int(DataLoader.get_define("map_style.label_outline_size"))
	_min_size = float(DataLoader.get_define("map_style.label_min_screen_size"))
	_max_size = float(DataLoader.get_define("map_style.label_max_screen_size"))
	_fill_ratio = float(DataLoader.get_define("map_style.label_fill_ratio"))
	_thickness_ratio = float(DataLoader.get_define("map_style.label_thickness_ratio"))
	_letter_spacing = float(DataLoader.get_define("map_style.label_letter_spacing"))
	queue_redraw()


func _draw() -> void:
	if _camera == null:
		return
	var screen := Rect2(Vector2.ZERO, size)
	for tag: String in _layouts.keys():
		var layout: CountryLabelLayout = _layouts[tag]
		var text := _text_for(tag)
		if text.is_empty():
			continue
		var map_size := minf(layout.length * _fill_ratio / _unit_width(tag, text),
			layout.thickness * _thickness_ratio)
		var font_size := map_size * _camera.zoom
		if font_size < _min_size or font_size > _max_size:
			continue
		var points := _screen_points(layout)
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point: Vector2 in points:
			bounds = bounds.expand(point)
		if not screen.intersects(bounds.grow(font_size)):
			continue
		_draw_along(points, text, roundi(font_size), _fade(font_size))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _fade(font_size: float) -> float:
	var fade_width := (_max_size - _min_size) * FADE_RATIO
	var low := clampf((font_size - _min_size) / maxf(fade_width * 0.2, 0.001), 0.0, 1.0)
	var high := clampf((_max_size - font_size) / maxf(fade_width, 0.001), 0.0, 1.0)
	return minf(low, high)


func _screen_points(layout: CountryLabelLayout) -> PackedVector2Array:
	var middle := layout.points[layout.points.size() >> 1]
	var anchor := _camera.map_to_screen(middle)
	var result := PackedVector2Array()
	for point: Vector2 in layout.points:
		result.append(anchor + (point - middle) * _camera.zoom)
	return result


func _draw_along(points: PackedVector2Array, text: String, font_size: int, alpha: float) -> void:
	var cumulative := PackedFloat64Array([0.0])
	for i: int in range(1, points.size()):
		cumulative.append(cumulative[i - 1] + points[i].distance_to(points[i - 1]))
	var total := cumulative[cumulative.size() - 1]
	var spacing := _letter_spacing * font_size
	var advances := PackedFloat64Array()
	var text_width := 0.0
	for i: int in text.length():
		var advance := _font.get_char_size(text.unicode_at(i), font_size).x
		advances.append(advance)
		text_width += advance + (spacing if i < text.length() - 1 else 0.0)
	var baseline := (_font.get_ascent(font_size) - _font.get_descent(font_size)) * 0.5
	var color := Color(_color, _color.a * alpha)
	var outline := Color(_outline_color, _outline_color.a * alpha)
	var position_along := (total - text_width) * 0.5
	var segment := 1
	for i: int in text.length():
		var center := position_along + advances[i] * 0.5
		while segment < cumulative.size() - 1 and cumulative[segment] < center:
			segment += 1
		var start := points[segment - 1]
		var end := points[segment]
		var length := cumulative[segment] - cumulative[segment - 1]
		var weight := 0.0 if length <= 0.0 else clampf((center - cumulative[segment - 1]) / length, -1.0, 2.0)
		var point := start.lerp(end, weight)
		draw_set_transform(point, (end - start).angle())
		var glyph_origin := Vector2(-advances[i] * 0.5, baseline)
		var code := text.unicode_at(i)
		if _outline_size > 0:
			_font.draw_char_outline(get_canvas_item(), glyph_origin, code, font_size, _outline_size, outline)
		_font.draw_char(get_canvas_item(), glyph_origin, code, font_size, color)
		position_along += advances[i] + spacing


func _text_for(tag: String) -> String:
	if not _texts.has(tag):
		var country: Dictionary = _countries.get(tag, {})
		_texts[tag] = tr(str(country.get("name_key", ""))).to_upper() if country.has("name_key") else ""
	return _texts[tag]


## Largeur du texte pour une taille de police de 1 (espacement des lettres compris).
func _unit_width(tag: String, text: String) -> float:
	if not _unit_widths.has(tag):
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MEASURE_SIZE).x / MEASURE_SIZE
		_unit_widths[tag] = maxf(width + _letter_spacing * maxi(text.length() - 1, 0), 0.001)
	return _unit_widths[tag]

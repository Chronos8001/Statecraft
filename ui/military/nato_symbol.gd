class_name NatoSymbol
extends Control
## Symbole d'unité au standard OTAN (APP-6) : cadre selon l'appartenance et le milieu, icône de l'arme et
## marque de taille (échelon) au-dessus du cadre. Couleurs dans les données (defines.military_symbols).
## Milieux : « land » (terre), « air », « sea » (surface). Appartenances : ami, hostile, neutre, inconnu.

const LAND := "land"
const AIR := "air"
const SEA := "sea"
const FRIEND := "friend"
const HOSTILE := "hostile"
const NEUTRAL := "neutral"
const UNKNOWN := "unknown"
## Icônes terrestres : infanterie (croix), blindé (ellipse), mécanisé (croix + ellipse).
const INFANTRY := "infantry"
const ARMOUR := "armour"
const MECHANIZED := "mechanized"
## Proportions du cadre (APP-6 : rectangle ami 3:2, carré neutre, losange hostile).
const FRIEND_RATIO := 1.5
const ECHELON_SPACE := 0.28
const LINE_WIDTH := 2.0
const ICON_INSET := 0.0
const ARC_POINTS := 24

var domain: String = LAND:
	set(value):
		domain = value
		queue_redraw()
var affiliation: String = FRIEND:
	set(value):
		affiliation = value
		queue_redraw()
var icon: String = INFANTRY:
	set(value):
		icon = value
		queue_redraw()
## Marque de taille : « II » bataillon, « III » régiment, « X » brigade, « XX » division, « XXX » corps,
## « XXXX » armée, « XXXXX » groupe d'armées. Vide : pas de marque.
var echelon: String = "":
	set(value):
		echelon = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(48, 36)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var colors: Dictionary = DataLoader.get_define("military_symbols", {})
	var fill := Color.html(str(colors.get(affiliation, "#80E0FF")))
	var line := Color.html(str(colors.get("line", "#000000")))
	var top := size.y * ECHELON_SPACE if not echelon.is_empty() else 0.0
	var area := Rect2(Vector2(LINE_WIDTH, top + LINE_WIDTH), size - Vector2(LINE_WIDTH * 2.0, top + LINE_WIDTH * 2.0))
	var frame := _frame(area)
	draw_colored_polygon(frame, fill)
	var outline := frame.duplicate()
	outline.append(frame[0])
	draw_polyline(outline, line, LINE_WIDTH, true)
	_draw_icon(_icon_box(area), line)
	if not echelon.is_empty():
		var font := get_theme_default_font()
		var font_size := int(maxf(top * 0.9, 8.0))
		var text_size := font.get_string_size(echelon, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2((size.x - text_size.x) / 2.0, top * 0.85), echelon, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, line)


## Contour du cadre selon le milieu et l'appartenance.
func _frame(area: Rect2) -> PackedVector2Array:
	var center := area.get_center()
	if affiliation == HOSTILE:
		var half := minf(area.size.x, area.size.y) / 2.0
		return PackedVector2Array([center + Vector2(0, -half), center + Vector2(half, 0), center + Vector2(0, half),
			center + Vector2(-half, 0)])
	if affiliation == NEUTRAL or affiliation == UNKNOWN:
		var side := minf(area.size.x, area.size.y)
		return _rect_points(Rect2(center - Vector2(side, side) / 2.0, Vector2(side, side)))
	match domain:
		AIR:
			# Ami, aérien : arc ouvert vers le bas.
			var radius := minf(area.size.x / 2.0, area.size.y)
			var base := Vector2(center.x, area.end.y)
			var points := PackedVector2Array()
			for index: int in ARC_POINTS + 1:
				var angle := PI + PI * float(index) / ARC_POINTS
				points.append(base + Vector2(cos(angle), sin(angle)) * radius)
			return points
		SEA:
			var radius := minf(area.size.x, area.size.y) / 2.0
			var points := PackedVector2Array()
			for index: int in ARC_POINTS * 2:
				var angle := TAU * float(index) / (ARC_POINTS * 2)
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
			return points
	var height := minf(area.size.y, area.size.x / FRIEND_RATIO)
	var width := height * FRIEND_RATIO
	return _rect_points(Rect2(center - Vector2(width, height) / 2.0, Vector2(width, height)))


## Zone de l'icône à l'intérieur du cadre.
func _icon_box(area: Rect2) -> Rect2:
	var center := area.get_center()
	if domain == AIR and affiliation == FRIEND:
		var radius := minf(area.size.x / 2.0, area.size.y)
		return Rect2(Vector2(center.x - radius * 0.6, area.end.y - radius * 0.7), Vector2(radius * 1.2, radius * 0.5))
	var side := minf(area.size.x, area.size.y)
	var width := side * (FRIEND_RATIO if domain == LAND and affiliation == FRIEND else 1.0)
	var box := Rect2(center - Vector2(width, side) / 2.0, Vector2(width, side))
	return box.grow(-side * 0.18) if affiliation != HOSTILE else box.grow(-side * 0.3)


func _draw_icon(box: Rect2, color: Color) -> void:
	match domain:
		AIR:
			# Aéronef à voilure fixe : deux boucles reliées (forme d'hélice).
			var radius := Vector2(box.size.x / 4.0, box.size.y / 2.0)
			_draw_ellipse(box.position + Vector2(radius.x, radius.y), radius, color)
			_draw_ellipse(box.position + Vector2(radius.x * 3.0, radius.y), radius, color)
		SEA:
			# Bâtiment de surface : coque stylisée.
			var y := box.position.y + box.size.y * 0.55
			draw_polyline(PackedVector2Array([box.position + Vector2(0, box.size.y * 0.35),
				Vector2(box.position.x + box.size.x * 0.2, y), Vector2(box.end.x - box.size.x * 0.2, y),
				Vector2(box.end.x, box.position.y + box.size.y * 0.35)]), color, LINE_WIDTH, true)
			draw_line(Vector2(box.get_center().x, y), Vector2(box.get_center().x, box.position.y), color, LINE_WIDTH, true)
		_:
			if icon == INFANTRY or icon == MECHANIZED:
				draw_line(box.position, box.end, color, LINE_WIDTH, true)
				draw_line(Vector2(box.position.x, box.end.y), Vector2(box.end.x, box.position.y), color, LINE_WIDTH, true)
			if icon == ARMOUR or icon == MECHANIZED:
				var inner := box.grow_individual(-box.size.x * 0.1, -box.size.y * 0.25, -box.size.x * 0.1, -box.size.y * 0.25)
				_draw_ellipse(inner.get_center(), inner.size / 2.0, color)


func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in ARC_POINTS * 2 + 1:
		var angle := TAU * float(index) / (ARC_POINTS * 2)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_polyline(points, color, LINE_WIDTH, true)


static func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)])

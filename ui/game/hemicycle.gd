class_name Hemicycle
extends Control
## Dessin d'une chambre en hémicycle : un point par siège, les partis rangés de gauche à droite.
## Au-delà de MAX_DOTS sièges, chaque point représente plusieurs sièges.

const MAX_DOTS := 700
const MIN_ROWS := 3
const MAX_ROWS := 16
## Rayon intérieur, en part du rayon extérieur.
const INNER_RATIO := 0.4
const DOT_FILL := 0.8
const ASPECT := 2.0

## [[couleur, sièges], …] dans l'ordre d'affichage.
var _blocks: Array = []


func set_blocks(blocks: Array) -> void:
	_blocks = blocks
	queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2(0.0, 150.0)


func _draw() -> void:
	var seats := 0
	for block: Array in _blocks:
		seats += int(block[1])
	if seats <= 0:
		return
	var per_dot := ceili(float(seats) / MAX_DOTS)
	var dots := ceili(float(seats) / per_dot)
	var outer := minf(size.x / ASPECT, size.y) - 2.0
	var center := Vector2(size.x / 2.0, size.y - 1.0)
	var rows := clampi(ceili(sqrt(dots / PI)), MIN_ROWS, MAX_ROWS)
	var inner := outer * INNER_RATIO
	var step := (outer - inner) / rows
	# Places de chaque rangée au prorata de son rayon, puis tri par angle pour ranger les partis.
	var radii: Array[float] = []
	var radius_sum := 0.0
	for row: int in rows:
		var radius := inner + step * (row + 0.5)
		radii.append(radius)
		radius_sum += radius
	var places: Array = []
	var placed := 0
	for row: int in rows:
		var count := dots - placed if row == rows - 1 else roundi(dots * radii[row] / radius_sum)
		placed += count
		for i: int in count:
			var angle := PI * (1.0 - (i + 0.5) / count) if count > 0 else PI / 2.0
			places.append([angle, radii[row]])
	places.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var dot_radius := minf(step, outer * PI / maxf(dots / float(rows), 1.0)) * DOT_FILL / 2.0
	var index := 0
	for block: Array in _blocks:
		var count := ceili(float(block[1]) / per_dot)
		for _i: int in count:
			if index >= places.size():
				return
			var place: Array = places[index]
			draw_circle(center + Vector2(cos(place[0]), -sin(place[0])) * float(place[1]), dot_radius, block[0])
			index += 1

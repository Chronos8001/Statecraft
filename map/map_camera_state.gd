class_name MapCameraState
extends RefCounted
## État de la caméra de carte, sans nœud : centre (en pixels de carte) et zoom (pixels d'écran par
## pixel de carte). Bouclage est-ouest ; verticalement, la vue reste dans la carte.

var map_size: Vector2
var viewport_size: Vector2
var center: Vector2
var zoom: float = 1.0
var max_zoom: float = 1.0


func _init(p_map_size: Vector2, p_viewport_size: Vector2, p_max_zoom: float) -> void:
	map_size = p_map_size
	viewport_size = p_viewport_size
	max_zoom = p_max_zoom
	center = map_size * 0.5
	zoom = get_min_zoom()


## Zoom minimal : la carte occupe toute la hauteur de l'écran.
func get_min_zoom() -> float:
	return viewport_size.y / map_size.y


func set_viewport_size(size: Vector2) -> void:
	viewport_size = size
	clamp_view()


func look_at(map_position: Vector2, p_zoom: float) -> void:
	center = map_position
	zoom = p_zoom
	clamp_view()


## Position de carte sous un point de l'écran (x ramené dans 0..largeur).
func screen_to_map(screen_position: Vector2) -> Vector2:
	var position := _screen_to_map_unwrapped(screen_position)
	position.x = fposmod(position.x, map_size.x)
	return position


## Position d'écran d'un point de carte (copie la plus proche du centre de l'écran).
func map_to_screen(map_position: Vector2) -> Vector2:
	var dx := fposmod(map_position.x - center.x + map_size.x * 0.5, map_size.x) - map_size.x * 0.5
	return viewport_size * 0.5 + Vector2(dx, map_position.y - center.y) * zoom


## Déplace la vue d'un décalage en pixels d'écran (glisser la carte vers la droite = delta.x > 0).
func pan_screen(delta: Vector2) -> void:
	center -= delta / zoom
	clamp_view()


## Multiplie le zoom en gardant fixe le point de carte situé sous screen_position.
func zoom_at(screen_position: Vector2, factor: float) -> void:
	var before := _screen_to_map_unwrapped(screen_position)
	zoom = clampf(zoom * factor, get_min_zoom(), max_zoom)
	var after := _screen_to_map_unwrapped(screen_position)
	center += before - after
	clamp_view()


func clamp_view() -> void:
	zoom = clampf(zoom, get_min_zoom(), max_zoom)
	var half_height := viewport_size.y * 0.5 / zoom
	if half_height * 2.0 >= map_size.y:
		center.y = map_size.y * 0.5
	else:
		center.y = clampf(center.y, half_height, map_size.y - half_height)
	center.x = fposmod(center.x, map_size.x)


func _screen_to_map_unwrapped(screen_position: Vector2) -> Vector2:
	return center + (screen_position - viewport_size * 0.5) / zoom

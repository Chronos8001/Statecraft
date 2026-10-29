extends GutTest

const MAP_SIZE := Vector2(16384, 8192)
const VIEWPORT := Vector2(1920, 1080)
const MAX_ZOOM := 8.0

var _camera: MapCameraState


func before_each() -> void:
	_camera = MapCameraState.new(MAP_SIZE, VIEWPORT, MAX_ZOOM)


func test_starts_with_full_map_height() -> void:
	assert_almost_eq(_camera.zoom, VIEWPORT.y / MAP_SIZE.y, 0.0001)
	assert_eq(_camera.center, MAP_SIZE * 0.5)


func test_screen_center_maps_to_camera_center() -> void:
	_camera.look_at(Vector2(5000, 3000), 1.0)
	assert_eq(_camera.screen_to_map(VIEWPORT * 0.5), Vector2(5000, 3000))
	assert_eq(_camera.map_to_screen(Vector2(5000, 3000)), VIEWPORT * 0.5)


func test_zoom_is_clamped() -> void:
	_camera.look_at(Vector2(5000, 3000), 100.0)
	assert_eq(_camera.zoom, MAX_ZOOM)
	_camera.zoom_at(VIEWPORT * 0.5, 0.0001)
	assert_almost_eq(_camera.zoom, _camera.get_min_zoom(), 0.0001)


func test_zoom_keeps_point_under_cursor() -> void:
	_camera.look_at(Vector2(5000, 3000), 1.0)
	var cursor := Vector2(300, 200)
	var before := _camera.screen_to_map(cursor)
	_camera.zoom_at(cursor, 2.0)
	assert_almost_eq(_camera.screen_to_map(cursor).x, before.x, 0.01)
	assert_almost_eq(_camera.screen_to_map(cursor).y, before.y, 0.01)


func test_horizontal_wrap() -> void:
	_camera.look_at(Vector2(100, 3000), 1.0)
	_camera.pan_screen(Vector2(500, 0))
	assert_almost_eq(_camera.center.x, MAP_SIZE.x - 400.0, 0.01)
	var left_of_screen := _camera.screen_to_map(Vector2.ZERO)
	assert_true(left_of_screen.x >= 0.0 and left_of_screen.x < MAP_SIZE.x)


func test_point_across_the_seam_is_drawn_nearby() -> void:
	_camera.look_at(Vector2(MAP_SIZE.x - 10.0, 3000), 1.0)
	var screen := _camera.map_to_screen(Vector2(10, 3000))
	assert_almost_eq(screen.x, VIEWPORT.x * 0.5 + 20.0, 0.01)


func test_view_stays_inside_map_vertically() -> void:
	_camera.look_at(Vector2(5000, -500), 1.0)
	assert_eq(_camera.center.y, VIEWPORT.y * 0.5)
	_camera.pan_screen(Vector2(0, -100000))
	assert_eq(_camera.center.y, MAP_SIZE.y - VIEWPORT.y * 0.5)

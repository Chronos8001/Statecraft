extends GutTest
## Décodage de l'image des provinces et texture de correspondance des couleurs.

const PROVINCES_IMAGE := "res://data/map/provinces.png"


func _small_map() -> ProvinceMapData:
	var image := Image.create_empty(4, 2, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	image.set_pixel(0, 0, ProvinceMapData.id_to_color(1))
	image.set_pixel(3, 0, ProvinceMapData.id_to_color(300))
	image.set_pixel(2, 1, ProvinceMapData.id_to_color(4596))
	return ProvinceMapData.from_image(image)


func test_id_color_round_trip() -> void:
	for province_id: int in [0, 1, 255, 256, 4596, 65535]:
		assert_eq(ProvinceMapData.color_to_id(ProvinceMapData.id_to_color(province_id)), province_id)


func test_province_at_position() -> void:
	var data := _small_map()
	assert_eq(data.id_image.get_format(), Image.FORMAT_RG8)
	assert_eq(data.get_province_at(Vector2(0.5, 0.5)), 1)
	assert_eq(data.get_province_at(Vector2(3.9, 0.2)), 300)
	assert_eq(data.get_province_at(Vector2(2.0, 1.0)), 4596)
	assert_eq(data.get_province_at(Vector2(1.0, 1.0)), 0, "eau")


func test_province_at_wraps_and_clamps() -> void:
	var data := _small_map()
	assert_eq(data.get_province_at(Vector2(4.2, 0.0)), 1, "bouclage est-ouest")
	assert_eq(data.get_province_at(Vector2(-0.5, 0.0)), 300)
	assert_eq(data.get_province_at(Vector2(0.0, -1.0)), 0, "hors carte")
	assert_eq(data.get_province_at(Vector2(0.0, 2.0)), 0)


func test_lookup_image_layout() -> void:
	var colors := PackedColorArray()
	colors.resize(300)
	colors.fill(Color.RED)
	colors[0] = Color.BLUE
	colors[257] = Color.GREEN
	var image := ProvinceLookup.build_image(colors)
	assert_eq(image.get_size(), Vector2i(ProvinceLookup.WIDTH, 2))
	assert_eq(image.get_pixel(0, 0), Color.BLUE)
	assert_eq(image.get_pixel(1, 1), Color.GREEN)


func test_political_colors() -> void:
	var provinces := {"1": {"owner": "AAA"}, "2": {}, "3": {"owner": "ZZZ"}}
	var countries := {"AAA": {"color": "#FF0000"}}
	var colors := ProvinceLookup.political_colors(provinces, countries, 3, Color.BLUE, Color.GRAY)
	assert_eq(colors.size(), 4)
	assert_eq(colors[0], Color.BLUE, "mer")
	assert_eq(colors[1], Color.RED)
	assert_eq(colors[2], Color.GRAY, "sans propriétaire")
	assert_eq(colors[3], Color.GRAY, "propriétaire inconnu")


func test_real_map_matches_province_data() -> void:
	var data := ProvinceMapData.from_png_file(PROVINCES_IMAGE)
	assert_not_null(data)
	var info: Dictionary = DataLoader.get_category("map")["map"]
	assert_eq(data.width, int(info["width"]))
	assert_eq(data.height, int(info["height"]))
	var provinces := DataLoader.get_category("provinces")
	var countries := DataLoader.get_category("countries")
	for tag: String in ["FRA", "USA", "CHN", "DEU", "BRA"]:
		var capital := str(int(countries[tag]["capital"]))
		var center: Array = provinces[capital]["center"]
		var size := int(provinces[capital]["size"])
		var found := data.get_province_at(Vector2(float(center[0]), float(center[1])))
		if size > 100:
			assert_eq(found, int(capital), "centre de la capitale de %s" % tag)

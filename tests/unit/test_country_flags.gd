extends GutTest
## Chemins et textures des drapeaux.

const COLOR := Color(0.2, 0.4, 0.6)


func after_each() -> void:
	CountryFlags.clear_cache()


func test_default_path_uses_tag() -> void:
	assert_eq(CountryFlags.path_for("FRA", {}), "res://assets/flags/FRA.svg")
	assert_eq(CountryFlags.path_for("FRA", {"flag": ""}), "res://assets/flags/FRA.svg")


func test_custom_path_wins() -> void:
	assert_eq(CountryFlags.path_for("FRA", {"flag": "res://mods/flags/fra.png"}), "res://mods/flags/fra.png")


func test_existing_flag_is_loaded() -> void:
	var texture := CountryFlags.texture_for(CountryFlags.path_for("FRA", {}), COLOR)
	assert_true(texture is CompressedTexture2D)


func test_missing_flag_falls_back_to_country_color() -> void:
	var texture := CountryFlags.texture_for("res://assets/flags/ZZZ.svg", COLOR)
	assert_eq(texture.get_size(), Vector2(CountryFlags.ASPECT))
	assert_true(texture.get_image().get_pixel(0, 0).is_equal_approx(COLOR))


func test_textures_are_cached() -> void:
	var path := CountryFlags.path_for("FRA", {})
	assert_same(CountryFlags.texture_for(path, COLOR), CountryFlags.texture_for(path, COLOR))

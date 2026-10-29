extends GutTest

const MAP_WIDTH := 1000.0


func _province(x: float, y: float, neighbors: Array, owner: String = "AAA", size: int = 100) -> Dictionary:
	return {"owner": owner, "center": [x, y], "size": size, "neighbors": neighbors}


func test_horizontal_country_gives_horizontal_label() -> void:
	var provinces := {
		"1": _province(100, 200, [2]), "2": _province(200, 200, [1, 3]), "3": _province(300, 200, [2]),
	}
	var layout: CountryLabelLayout = CountryLabelLayout.compute_all(provinces, MAP_WIDTH)["AAA"]
	var first := layout.points[0]
	var last := layout.points[layout.points.size() - 1]
	assert_lt(first.x, last.x, "lecture de gauche à droite")
	assert_almost_eq(first.y, 200.0, 1.0)
	assert_almost_eq(last.y, 200.0, 1.0)
	assert_gt(layout.length, 150.0)


func test_label_uses_largest_connected_territory() -> void:
	var provinces := {
		"1": _province(100, 100, [2]), "2": _province(160, 100, [1]),
		"3": _province(800, 500, [], "AAA", 10),
	}
	var layout: CountryLabelLayout = CountryLabelLayout.compute_all(provinces, MAP_WIDTH)["AAA"]
	for point: Vector2 in layout.points:
		assert_lt(point.x, 300.0, "l'île isolée est ignorée")


func test_country_across_the_seam_stays_together() -> void:
	var provinces := {"1": _province(980, 300, [2]), "2": _province(20, 300, [1])}
	var layout: CountryLabelLayout = CountryLabelLayout.compute_all(provinces, MAP_WIDTH)["AAA"]
	assert_lt(layout.length, 200.0, "pas de courbe traversant toute la carte")


func test_single_province_country() -> void:
	var layout: CountryLabelLayout = CountryLabelLayout.compute_all({"1": _province(50, 50, [], "MCO", 12)}, MAP_WIDTH)["MCO"]
	assert_eq(layout.points.size(), CountryLabelLayout.SAMPLE_COUNT)
	assert_gt(layout.thickness, 0.0)


func test_curve_follows_an_arc() -> void:
	var provinces := {}
	for i: int in 7:
		var x := 100.0 + i * 50.0
		var y := 300.0 - 0.004 * pow(x - 250.0, 2.0)
		var neighbors := []
		if i > 0:
			neighbors.append(i)
		if i < 6:
			neighbors.append(i + 2)
		provinces[str(i + 1)] = _province(x, y, neighbors)
	var layout: CountryLabelLayout = CountryLabelLayout.compute_all(provinces, MAP_WIDTH, 1.0)["AAA"]
	var middle := layout.points[layout.points.size() >> 1]
	assert_gt(middle.y, layout.points[0].y + 20.0, "la courbe suit l'arc (y vers le bas)")


func test_curve_is_clipped_to_the_country() -> void:
	var provinces := {
		"1": _province(100, 200, [2]), "2": _province(200, 200, [1, 3]), "3": _province(300, 200, [2]),
	}
	var owner_at := func(position: Vector2) -> String: return "AAA" if position.x < 180.0 else "BBB"
	var layout: CountryLabelLayout = CountryLabelLayout.compute_all(provinces, MAP_WIDTH, 0.3, owner_at)["AAA"]
	for point: Vector2 in layout.points:
		assert_lt(point.x, 181.0)
	assert_eq(layout.points.size(), CountryLabelLayout.SAMPLE_COUNT)


func test_owner_indices() -> void:
	var provinces := {"1": {"owner": "BBB"}, "2": {"owner": "AAA"}, "3": {}}
	var owners := ProvinceLookup.owner_indices(provinces, {"AAA": {}, "BBB": {}}, 3)
	assert_eq(ProvinceMapData.color_to_id(owners[0]), ProvinceLookup.SEA_INDEX)
	assert_eq(ProvinceMapData.color_to_id(owners[1]), ProvinceLookup.FIRST_COUNTRY_INDEX + 1)
	assert_eq(ProvinceMapData.color_to_id(owners[2]), ProvinceLookup.FIRST_COUNTRY_INDEX)
	assert_eq(ProvinceMapData.color_to_id(owners[3]), ProvinceLookup.UNOWNED_INDEX)


func test_all_game_countries_get_a_label() -> void:
	var provinces := DataLoader.get_category("provinces")
	var started := Time.get_ticks_msec()
	var layouts := CountryLabelLayout.compute_all(provinces, 16384.0)
	gut.p("Calcul des noms : %d ms" % (Time.get_ticks_msec() - started))
	assert_eq(layouts.size(), DataLoader.get_category("countries").size())
	var russia: CountryLabelLayout = layouts["RUS"]
	assert_gt(russia.length, 3000.0, "la Russie a un long nom")

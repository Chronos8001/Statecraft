extends GutTest

const PROVINCES := {
	"10": {"name_key": "PROV_10", "owner": "UKR", "controller": "RUS", "terrain": "plains",
		"population": 1500000, "area_km2": 26000.4, "infrastructure": 5, "coastal": true,
		"resources": {"coal": 2, "steel": 4}, "neighbors": [11, 12, 13]},
	"11": {"name_key": "PROV_11", "owner": "UKR", "controller": "UKR", "terrain": "urban",
		"population": 2900000, "area_km2": 840.0, "infrastructure": 7, "coastal": false,
		"resources": {}, "neighbors": [10]},
	"12": {"name_key": "PROV_12", "terrain": "tundra", "population": 0, "area_km2": 5.0,
		"infrastructure": 0, "coastal": true, "resources": {}, "neighbors": []},
}
const COUNTRIES := {
	"UKR": {"name_key": "COUNTRY_UKR", "color": "#4C8FD6", "capital": 11},
	"RUS": {"name_key": "COUNTRY_RUS", "color": "#C2759A", "capital": 99},
}
const TERRAINS := {"plains": {"name_key": "TERRAIN_PLAINS"}, "urban": {"name_key": "TERRAIN_URBAN"}}
const RESOURCES := {"coal": {"name_key": "RESOURCE_COAL"}, "steel": {"name_key": "RESOURCE_STEEL"}}


func _build(province_id: int) -> ProvinceInfo:
	return ProvinceInfo.build(province_id, PROVINCES, COUNTRIES, TERRAINS, RESOURCES)


func test_unknown_province_gives_null() -> void:
	assert_null(_build(0), "eau")
	assert_null(_build(999))


func test_occupied_province() -> void:
	var info := _build(10)
	assert_eq(info.name_key, "PROV_10")
	assert_eq(info.owner_name_key, "COUNTRY_UKR")
	assert_eq(info.owner_color, Color.html("#4C8FD6"))
	assert_true(info.is_occupied)
	assert_eq(info.controller_name_key, "COUNTRY_RUS")
	assert_false(info.is_capital)
	assert_eq(info.terrain_name_key, "TERRAIN_PLAINS")
	assert_eq(info.neighbor_count, 3)


func test_resources_sorted_by_amount() -> void:
	assert_eq(_build(10).resources, [["RESOURCE_STEEL", 4.0], ["RESOURCE_COAL", 2.0]])


func test_capital_not_occupied() -> void:
	var info := _build(11)
	assert_true(info.is_capital)
	assert_false(info.is_occupied)
	assert_eq(info.resources, [])


func test_unowned_province() -> void:
	var info := _build(12)
	assert_eq(info.owner_name_key, "")
	assert_false(info.is_occupied)
	assert_eq(info.terrain_name_key, "tundra", "clé brute si le terrain est inconnu")


func test_number_format() -> void:
	assert_eq(NumberFormat.integer(0, "fr"), "0")
	assert_eq(NumberFormat.integer(999, "en"), "999")
	assert_eq(NumberFormat.integer(2138259, "en"), "2,138,259")
	assert_eq(NumberFormat.integer(2138259, "fr"), "2 138 259")
	assert_eq(NumberFormat.integer(-1500, "en_US"), "-1,500")
	assert_eq(NumberFormat.integer(1000000, "de"), "1,000,000", "séparateur par défaut")

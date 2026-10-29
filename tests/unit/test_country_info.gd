extends GutTest

const PROVINCES := {
	"1": {"name_key": "PROV_1", "owner": "AAA", "controller": "AAA", "population": 1000, "area_km2": 50.0},
	"2": {"name_key": "PROV_2", "owner": "AAA", "controller": "BBB", "population": 500, "area_km2": 25.0},
	"3": {"name_key": "PROV_3", "owner": "BBB", "controller": "BBB", "population": 300, "area_km2": 10.0},
}
const NAMES := {
	"characters": {"chr_a": {"first_name": "Ana", "last_name": "Ruiz"}, "chr_b": {"first_name": "Ben", "last_name": "Ode"}},
	"parties": {"pty_a": {"name": {"en": "Unity", "fr": "Unité"}}, "pty_b": {"name": "Verts"}},
	"organizations": {"un": {"abbreviation": {"en": "UN", "fr": "ONU"}}},
}
const REGIMES := {"presidential_republic": {"name_key": "REGIME_PRESIDENTIAL_REPUBLIC"}}
const IDEOLOGIES := {"centrist": {"name_key": "IDEOLOGY_CENTRIST"}}


func _countries() -> Dictionary:
	return {
		"AAA": {"name_key": "COUNTRY_AAA", "color": "#FF0000", "capital": 1, "regime": "presidential_republic",
			"head_of_state": "chr_a", "head_of_government": "chr_b", "ruling_party": "pty_a",
			"coalition_partners": ["pty_b"], "ideology": "centrist", "population": 2000,
			"economy": {"gdp_billion_usd": 10.0, "debt_to_gdp": 0.8}, "military": {"active_personnel": 5000},
			"organizations": ["un"]},
		"BBB": {"name_key": "COUNTRY_BBB", "color": "#0000FF", "capital": 3},
	}


func test_unknown_country() -> void:
	assert_null(CountryInfo.build("", _countries(), PROVINCES, NAMES, REGIMES, IDEOLOGIES))
	assert_null(CountryInfo.build("ZZZ", _countries(), PROVINCES, NAMES, REGIMES, IDEOLOGIES))


func test_detailed_country() -> void:
	var info := CountryInfo.build("AAA", _countries(), PROVINCES, NAMES, REGIMES, IDEOLOGIES)
	assert_eq(info.capital_name_key, "PROV_1")
	assert_eq(info.regime_name_key, "REGIME_PRESIDENTIAL_REPUBLIC")
	assert_eq(info.head_of_state_name, "Ana Ruiz")
	assert_eq(info.head_of_government_name, "Ben Ode")
	assert_eq(info.ruling_party_name, {"en": "Unity", "fr": "Unité"})
	assert_eq(info.coalition_names, ["Verts"])
	assert_eq(info.ideology_name_key, "IDEOLOGY_CENTRIST")
	assert_eq(info.population, 2000, "population du pays prioritaire")
	assert_eq(info.province_count, 2)
	assert_almost_eq(info.area_km2, 75.0, 0.01)
	assert_almost_eq(info.gdp_per_capita, 5000000.0, 0.1)
	assert_almost_eq(info.debt_to_gdp, 0.8, 0.001)
	assert_eq(info.active_personnel, 5000.0)
	assert_eq(info.organization_abbreviations, [{"en": "UN", "fr": "ONU"}])
	assert_eq(info.occupied_count, 1)
	assert_eq(info.occupying_count, 0)


func test_minimal_country_hides_missing_data() -> void:
	var info := CountryInfo.build("BBB", _countries(), PROVINCES, NAMES, REGIMES, IDEOLOGIES)
	assert_eq(info.population, 300, "somme des provinces")
	assert_eq(info.head_of_state_name, "")
	assert_null(info.ruling_party_name)
	assert_eq(info.gdp_billion_usd, CountryInfo.MISSING)
	assert_eq(info.occupying_count, 1)


func test_country_indices_match_owner_texture() -> void:
	var indices := ProvinceLookup.country_indices({"BBB": {}, "AAA": {}})
	assert_eq(indices, {"AAA": ProvinceLookup.FIRST_COUNTRY_INDEX, "BBB": ProvinceLookup.FIRST_COUNTRY_INDEX + 1})

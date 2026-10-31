extends GutTest
## Vérifie que les données livrées avec le jeu sont valides et cohérentes.

## Les 30 pays majeurs, dont les dirigeants et partis sont écrits à la main.
const MAJOR_COUNTRIES := ["ARG", "AUS", "BRA", "CAN", "CHN", "DEU", "EGY", "ESP", "FRA", "GBR", "IDN", "IND",
	"IRN", "ISR", "ITA", "JPN", "KOR", "MEX", "NGA", "PAK", "POL", "PRK", "RUS", "SAU", "TUR", "TWN", "UKR",
	"USA", "VNM", "ZAF"]
const MIN_LEADER_AGE := 30
const MAX_LEADER_AGE := 95
const MIN_CULTURE_COUNT := 40
const FINAL_PARTY_GROUP := "liberal"
const MIN_COUNTRY_COUNT := 190
const MIN_PROVINCE_COUNT := 4000
const LOCALIZATION_DIR := "res://data/localization"
const TRANSLATED_CATEGORIES := ["countries", "provinces", "sea_zones", "straits", "ideologies", "regimes",
	"terrains", "resources", "traits", "challenges", "economy_sectors", "budget_taxes", "budget_spending",
	"social_groups", "trade_agreements"]
const MIN_SEA_ZONE_COUNT := 150

const LocalizationScript := preload("res://core/localization/localization.gd")

var _repository: DataRepository
var _messages: Dictionary = {}


func before_all() -> void:
	_repository = DataRepository.new()
	_repository.load_roots(PackedStringArray([ModManager.BASE_DATA_ROOT]))
	_repository.validate()
	for file_name: String in DirAccess.get_files_at(LOCALIZATION_DIR):
		if file_name.get_extension() == "csv":
			_messages = JsonMerge.merge(_messages, LocalizationScript.parse_csv(LOCALIZATION_DIR.path_join(file_name)))


func test_base_data_has_no_error() -> void:
	assert_eq(_repository.errors.size(), 0, "\n".join(_repository.errors.slice(0, 20)))
	assert_eq(_repository.warnings.size(), 0, "\n".join(_repository.warnings))


func test_world_is_covered() -> void:
	var countries := _repository.get_category("countries")
	assert_gt(countries.size(), MIN_COUNTRY_COUNT)
	assert_gt(_repository.get_category("provinces").size(), MIN_PROVINCE_COUNT)
	for tag: String in MAJOR_COUNTRIES:
		assert_true(countries.has(tag), tag)


func test_every_country_has_real_data() -> void:
	var countries := _repository.get_category("countries")
	var provinces := _repository.get_category("provinces")
	var province_totals: Dictionary = {}
	for key: String in provinces.keys():
		var owner := str((provinces[key] as Dictionary).get("owner", ""))
		province_totals[owner] = int(province_totals.get(owner, 0)) + int(provinces[key]["population"])
	for tag: String in countries.keys():
		var country: Dictionary = countries[tag]
		assert_gt(int(country["population"]), 0, "population de %s" % tag)
		assert_gt(float(country["economy"]["gdp_billion_usd"]), 0.0, "PIB de %s" % tag)
		assert_almost_eq(float(province_totals.get(tag, 0)), float(country["population"]),
			maxf(float(country["population"]) * 0.001, 10.0), "population des provinces de %s" % tag)
	assert_eq((countries["USA"]["organizations"] as Array).has("nato"), true)
	assert_eq((countries["TWN"]["organizations"] as Array).has("un"), false, "Taïwan hors ONU")


func test_each_country_capital_belongs_to_it() -> void:
	var countries := _repository.get_category("countries")
	for tag: String in countries.keys():
		var capital := SchemaValidator.to_key(countries[tag]["capital"])
		assert_eq(_repository.get_entry("provinces", capital).get("owner"), tag, "capitale de %s" % tag)


func test_province_color_encodes_its_id() -> void:
	var provinces := _repository.get_category("provinces").merged(_repository.get_category("sea_zones"))
	var mismatches: Array[String] = []
	for province_id: String in provinces.keys():
		var id := int(province_id)
		var expected := "#%02X%02X00" % [id & 0xFF, (id >> 8) & 0xFF]
		if str(provinces[province_id]["color"]).to_upper() != expected:
			mismatches.append(province_id)
	assert_eq(mismatches.size(), 0, "provinces : %s" % str(mismatches.slice(0, 10)))


func test_sea_zones_follow_provinces() -> void:
	var info: Dictionary = _repository.get_category("map")["map"]
	var sea_zones := _repository.get_category("sea_zones")
	assert_gt(sea_zones.size(), MIN_SEA_ZONE_COUNT)
	assert_eq(int(info["max_id"]), int(info["province_count"]) + sea_zones.size())
	for zone_id: String in sea_zones.keys():
		assert_gt(int(zone_id), int(info["province_count"]), "zone %s numérotée après les provinces" % zone_id)


func test_coastal_flag_matches_sea_neighbors() -> void:
	var provinces := _repository.get_category("provinces")
	var sea_zones := _repository.get_category("sea_zones")
	var mismatches: int = 0
	for province_id: String in provinces.keys():
		var province: Dictionary = provinces[province_id]
		var sea_neighbors: Array = province["sea_neighbors"]
		if bool(province["coastal"]) != not sea_neighbors.is_empty():
			mismatches += 1
		for zone: Variant in sea_neighbors:
			var coasts: Array = sea_zones[SchemaValidator.to_key(zone)]["coasts"]
			if not coasts.has(float(province_id)):
				mismatches += 1
	assert_eq(mismatches, 0)


func test_straits_connect_two_sea_zones() -> void:
	var straits := _repository.get_category("straits")
	for strait_id: String in ["suez", "panama", "hormuz", "malacca", "bosphorus", "gibraltar"]:
		assert_true(straits.has(strait_id), strait_id)
		var strait: Dictionary = straits[strait_id]
		assert_eq((strait["sea_zones"] as Array).size(), 2, strait_id)
		assert_gt((strait["provinces"] as Array).size(), 0, strait_id)


func test_owned_provinces_have_a_controller() -> void:
	var provinces := _repository.get_category("provinces")
	for province_id: String in provinces.keys():
		var province: Dictionary = provinces[province_id]
		assert_eq(province.has("owner"), province.has("controller"), "province %s" % province_id)


func test_neighbors_are_symmetric() -> void:
	var provinces := _repository.get_category("provinces")
	var broken: int = 0
	for province_id: String in provinces.keys():
		for neighbor: Variant in provinces[province_id]["neighbors"]:
			var other: Dictionary = provinces[SchemaValidator.to_key(neighbor)]
			if not (other["neighbors"] as Array).has(float(province_id)):
				broken += 1
	assert_eq(broken, 0)


func test_every_country_has_leaders() -> void:
	var countries := _repository.get_category("countries")
	for tag: String in countries.keys():
		var country: Dictionary = countries[tag]
		assert_true(country.has("head_of_state"), "chef de l'État de %s" % tag)
		assert_true(country.has("head_of_government"), "chef du gouvernement de %s" % tag)
		assert_true(country.has("ideology"), "idéologie de %s" % tag)


## Un chef de l'État étranger n'est admis que s'il est aussi chef de l'État de son propre pays
## (royaumes du Commonwealth, coprince d'Andorre).
func test_characters_belong_to_their_country() -> void:
	var characters: Dictionary = _repository.resolve_ref("names#characters")
	var countries := _repository.get_category("countries")
	for tag: String in countries.keys():
		var country: Dictionary = countries[tag]
		var head_of_government: Dictionary = characters[country["head_of_government"]]
		assert_eq(head_of_government["country"], tag, "chef du gouvernement de %s" % tag)
		var head_of_state: Dictionary = characters[country["head_of_state"]]
		var home: Dictionary = countries[head_of_state["country"]]
		assert_eq(home["head_of_state"], country["head_of_state"], "chef de l'État de %s" % tag)


func test_leaders_have_plausible_ages() -> void:
	var characters: Dictionary = _repository.resolve_ref("names#characters")
	var year := int(_repository.get_value("defines", "game.start_date.year", 0))
	for character_id: String in characters.keys():
		var age := year - int(characters[character_id]["birth_year"])
		assert_between(age, MIN_LEADER_AGE, MAX_LEADER_AGE, character_id)


func test_parties_are_consistent() -> void:
	var characters: Dictionary = _repository.resolve_ref("names#characters")
	var parties: Dictionary = _repository.resolve_ref("names#parties")
	var countries := _repository.get_category("countries")
	for party_id: String in parties.keys():
		var party: Dictionary = parties[party_id]
		assert_true(party.has("leader"), "chef de %s" % party_id)
		var leader: Dictionary = characters[party["leader"]]
		assert_eq(leader.get("party", ""), party_id, "chef de %s membre du parti" % party_id)
		assert_eq(leader["country"], party["country"], "chef de %s" % party_id)
	for tag: String in countries.keys():
		var country: Dictionary = countries[tag]
		var governing: Array = (country.get("coalition_partners", []) as Array).duplicate()
		if country.has("ruling_party"):
			governing.append(country["ruling_party"])
		else:
			assert_false(country.has("coalition_partners"), "coalition sans parti au pouvoir : %s" % tag)
		for party_id: Variant in governing:
			assert_eq(parties[party_id]["country"], tag, "%s gouverne %s" % [party_id, tag])


func test_no_two_characters_share_a_name() -> void:
	var characters: Dictionary = _repository.resolve_ref("names#characters")
	var seen: Dictionary = {}
	for character_id: String in characters.keys():
		var character: Dictionary = characters[character_id]
		var full_name := "%s %s" % [character["first_name"], character["last_name"]]
		assert_false(seen.has(full_name), "%s / %s : %s" % [character_id, seen.get(full_name, ""), full_name])
		seen[full_name] = character_id


func test_cultures_are_usable() -> void:
	var cultures := _repository.get_category("names/cultures")
	var styles := _repository.get_category("names/party_styles")
	assert_gt(cultures.size(), MIN_CULTURE_COUNT)
	for culture_id: String in cultures.keys():
		var culture: Dictionary = cultures[culture_id]
		if culture.has("female_family_names"):
			assert_eq((culture["female_family_names"] as Array).size(), (culture["family_names"] as Array).size(),
				"formes féminines de %s alignées" % culture_id)
		var style: Dictionary = styles[culture["party_style"]]
		assert_true((style["names"] as Dictionary).has(FINAL_PARTY_GROUP),
			"le style %s doit couvrir le groupe de repli final" % culture["party_style"])


func test_start_date_is_january_first_2026() -> void:
	var start := GameDate.from_dict(_repository.get_value("defines", "game.start_date", {}))
	assert_eq(start.format_iso(), "2026-01-01 00:00")


func test_every_name_key_is_translated() -> void:
	var missing: Array[String] = []
	for category: String in TRANSLATED_CATEGORIES:
		var table := _repository.get_category(category)
		for entry_id: String in table.keys():
			var key: String = table[entry_id]["name_key"]
			for locale: String in ["en", "fr"]:
				if not (_messages[locale] as Dictionary).has(key):
					missing.append("%s (%s)" % [key, locale])
	assert_eq(missing.size(), 0, str(missing.slice(0, 10)))


func test_country_sheet_shows_leaders_for_every_country() -> void:
	var countries := _repository.get_category("countries")
	var year := int(_repository.get_value("defines", "game.start_date.year", 0))
	for tag: String in countries.keys():
		var info := CountryInfo.build(tag, countries, _repository.get_category("provinces"),
			_repository.get_category("names"), _repository.get_category("regimes"),
			_repository.get_category("ideologies"), _repository.get_category("names/cultures"), year)
		assert_false(info.head_of_state_name.is_empty(), "chef de l'État de %s" % tag)
		assert_false(info.head_of_government_name.is_empty(), "chef du gouvernement de %s" % tag)
		assert_ne(info.head_of_state_age, CountryInfo.UNKNOWN_AGE, "âge du chef de l'État de %s" % tag)
		assert_false(info.ideology_name_key.is_empty(), "idéologie de %s" % tag)


func test_every_country_has_a_flag() -> void:
	var countries := _repository.get_category("countries")
	for tag: String in countries.keys():
		var path := CountryFlags.path_for(tag, countries[tag])
		assert_true(CountryFlags.has_image(path), "drapeau de %s" % tag)
		var texture := load(path) as Texture2D
		if texture != null:
			assert_eq(texture.get_width() * CountryFlags.ASPECT.y, texture.get_height() * CountryFlags.ASPECT.x,
				"proportions 4:3 du drapeau de %s" % tag)


func test_no_flag_without_country() -> void:
	var countries := _repository.get_category("countries")
	var flag_dir := CountryFlags.DEFAULT_PATH.get_base_dir()
	for file_name: String in DirAccess.get_files_at(flag_dir):
		if file_name.get_extension() == "svg":
			assert_true(countries.has(file_name.get_basename()), "drapeau en trop : %s" % file_name)


func _selection() -> CountrySelection:
	return CountrySelection.build(_repository.get_category("countries"), _repository.get_category("provinces"),
		_repository.get_category("challenges"), _repository.get_value("defines", "country_selection", {}))


func test_challenge_descriptions_are_translated() -> void:
	var challenges := _repository.get_category("challenges")
	for challenge_id: String in challenges.keys():
		var key := str(challenges[challenge_id]["description_key"])
		for locale: String in ["en", "fr"]:
			assert_true((_messages[locale] as Dictionary).has(key), "%s (%s)" % [key, locale])


func test_every_country_has_a_difficulty() -> void:
	var selection := _selection()
	var per_level: Dictionary = {}
	for tag: String in _repository.get_category("countries").keys():
		var level := int(selection.difficulties.get(tag, 0))
		assert_between(level, CountrySelection.MIN_DIFFICULTY, CountrySelection.MAX_DIFFICULTY, tag)
		per_level[level] = int(per_level.get(level, 0)) + 1
	for level: int in range(CountrySelection.MIN_DIFFICULTY, CountrySelection.MAX_DIFFICULTY + 1):
		assert_gt(int(per_level.get(level, 0)), 0, "aucun pays de difficulté %d" % level)


func test_difficulty_follows_power_and_crises() -> void:
	var selection := _selection()
	for tag: String in ["USA", "CHN"]:
		assert_eq(selection.difficulties[tag], CountrySelection.MIN_DIFFICULTY, tag)
	for tag: String in ["UKR", "SOM", "YEM"]:
		assert_eq(selection.difficulties[tag], CountrySelection.MAX_DIFFICULTY, tag)
	assert_lt(int(selection.difficulties["FRA"]), int(selection.difficulties["BEL"]))


func test_major_countries_have_written_challenges() -> void:
	var countries := _repository.get_category("countries")
	var selection := _selection()
	for tag: String in MAJOR_COUNTRIES:
		assert_true((countries[tag] as Dictionary).has("challenges"), tag)
		assert_gt((selection.challenges[tag] as Array).size(), 1, tag)


func test_unrecognized_entities_need_advanced_mode() -> void:
	var selection := _selection()
	var standard := selection.playable_tags(false)
	var advanced := selection.playable_tags(true)
	assert_eq(advanced.size(), _repository.get_category("countries").size())
	for tag: String in ["CYN", "SOL"]:
		assert_false(standard.has(tag), tag)
		assert_true(advanced.has(tag), tag)
	for tag: String in ["TWN", "KOS", "PSE"]:
		assert_true(standard.has(tag), tag)


func test_every_country_has_a_valid_currency() -> void:
	var currencies := _repository.get_category("currencies")
	for currency_id: String in currencies.keys():
		var peg := str(currencies[currency_id]["peg"])
		assert_true(peg.is_empty() or currencies.has(peg), "ancrage de %s" % currency_id)
	var sectors := _repository.get_category("economy_sectors")
	for tag: String in _repository.get_category("countries").keys():
		var economy: Dictionary = _repository.get_category("countries")[tag]["economy"]
		var total := 0.0
		for share: Variant in (economy["sectors"] as Dictionary).values():
			total += float(share)
		assert_almost_eq(total, 1.0, 0.01, "secteurs de %s" % tag)
		assert_eq((economy["sectors"] as Dictionary).size(), sectors.size(), "secteurs de %s" % tag)


func test_world_economy_stays_stable_for_ten_years() -> void:
	var settings: Dictionary = _repository.get_value("defines", "economy", {})
	var state := SimState.new()
	var date := GameDate.new()
	date.year = 2026
	date.month = 1
	date.day = 1
	state.setup(2026, date)
	var budget_definitions := {"taxes": _repository.get_category("budget_taxes"),
		"spending": _repository.get_category("budget_spending"),
		"settings": _repository.get_value("defines", "budget", {})}
	var resource_definitions := {"straits": _repository.get_category("straits"),
		"sectors": _repository.get_category("economy_sectors"),
		"settings": _repository.get_value("defines", "resources", {})}
	var trade_definitions := {"agreements": _repository.get_category("trade_agreements"),
		"settings": _repository.get_value("defines", "trade", {})}
	WorldSetup.populate(state, _repository.get_category("countries"), _repository.get_category("currencies"), settings,
		budget_definitions, _repository.get_category("resources"), resource_definitions, trade_definitions)
	var resource_system := ResourceSystem.new()
	var trade_system := TradeSystem.new()
	var budget_system := BudgetSystem.new()
	var system := EconomySystem.new(_repository.get_category("economy_sectors"))
	var crises := 0
	for month: int in 120:
		state.date.month = month % 12 + 1
		resource_system.on_month(state)
		trade_system.on_month(state)
		budget_system.on_month(state)
		system.on_month(state)
		for event: Dictionary in state.events:
			if event["type"] == EconomySystem.EVENT_DEBT_CRISIS:
				crises += 1
		state.events.clear()
	var inflation_bounds: Array = settings["inflation_bounds"]
	for tag: String in state.countries.keys():
		var economy: EconomyState = state.countries[tag].economy
		var currency := state.get_currency(economy.currency)
		assert_false(is_nan(economy.real_gdp) or is_nan(economy.inflation) or is_nan(economy.debt_ratio(currency)), tag)
		assert_gt(economy.real_gdp, 0.0, tag)
		assert_between(economy.inflation, float(inflation_bounds[0]), 100.0, "inflation de %s" % tag)
		assert_between(economy.debt_ratio(currency), 0.0, 4.0, "dette de %s" % tag)
		assert_between(currency.policy_rate, 0.0, 100.0, "taux de %s" % currency.id)
	for tag: String in ["USA", "CHN", "DEU", "FRA", "JPN", "GBR", "IND"]:
		var economy: EconomyState = state.countries[tag].economy
		assert_false(economy.in_crisis(), "%s ne doit pas faire défaut" % tag)
		assert_between(economy.inflation, 0.0, 6.0, "inflation de %s" % tag)
		assert_between(economy.growth, -1.0, 7.0, "croissance de %s" % tag)
	assert_lt(crises, 30, "trop de crises de la dette")
	# Les pays de l'IA ne soldent pas leur dette et ne la laissent pas exploser.
	for tag: String in ["ARG", "LBN"]:
		var economy: EconomyState = state.countries[tag].economy
		assert_gt(economy.debt_ratio(state.get_currency(economy.currency)), 0.05, "dette de %s" % tag)
	for resource_id: String in state.markets.keys():
		assert_between((state.markets[resource_id] as MarketState).price_ratio(), 0.8, 1.25, "prix de %s" % resource_id)
	var ukraine: EconomyState = state.countries["UKR"].economy
	assert_lt(ukraine.debt_ratio(state.get_currency(ukraine.currency)), 2.5, "dette de l'Ukraine")


func test_every_budget_matches_its_country() -> void:
	var taxes := _repository.get_category("budget_taxes")
	var lines := _repository.get_category("budget_spending")
	for tag: String in _repository.get_category("countries").keys():
		var budget: Dictionary = _repository.get_category("countries")[tag]["budget"]
		assert_eq((budget["taxes"] as Dictionary).size(), taxes.size(), "impôts de %s" % tag)
		assert_eq((budget["spending"] as Dictionary).size(), lines.size(), "dépenses de %s" % tag)


func test_resources_are_consistent() -> void:
	var resources := _repository.get_category("resources")
	var countries := _repository.get_category("countries")
	for resource_id: String in resources.keys():
		if not (resources[resource_id] as Dictionary).has("market"):
			continue
		var produced := 0.0
		var used := 0.0
		for tag: String in countries.keys():
			var entry: Dictionary = (countries[tag]["resources"] as Dictionary).get(resource_id, {})
			produced += float(entry.get("production", 0.0))
			used += float(entry.get("consumption", 0.0))
		assert_gt(produced, 0.0, resource_id)
		assert_almost_eq(used / produced, 1.0, 0.01, "marché de %s équilibré au départ" % resource_id)
	var producing_provinces := 0
	for province: Dictionary in _repository.get_category("provinces").values():
		if not (province.get("resources", {}) as Dictionary).is_empty():
			producing_provinces += 1
	assert_gt(producing_provinces, 500, "provinces productrices")
	assert_true((countries["SAU"]["resources"] as Dictionary).has("oil"))
	assert_true((countries["COD"]["resources"] as Dictionary).has("cobalt"))


func test_trade_is_consistent() -> void:
	var countries := _repository.get_category("countries")
	for tag: String in countries.keys():
		var partners: Dictionary = countries[tag]["trade"]["partners"]
		assert_false(partners.has(tag), "%s commerce avec lui-même" % tag)
		if tag != "VAT":
			assert_gt(partners.size(), 0, "partenaires de %s" % tag)
	var mexico: Dictionary = countries["MEX"]["trade"]["partners"]
	var best := ""
	for partner: String in mexico.keys():
		if best.is_empty() or float(mexico[partner]) > float(mexico[best]):
			best = partner
	assert_eq(best, "USA", "premier client du Mexique")
	var agreements := _repository.get_category("trade_agreements")
	assert_true((agreements["eu_single_market"]["members"] as Array).has("FRA"))
	assert_true((agreements["usmca"]["members"] as Array).has("MEX"))
	assert_true((countries["USA"]["trade"]["surcharges"] as Dictionary).has("CHN"), "surtaxes de 2026")

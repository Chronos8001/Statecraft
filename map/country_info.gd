class_name CountryInfo
extends RefCounted
## Prépare les informations affichées pour un pays. Les valeurs absentes des données restent vides
## (chaîne vide, tableau vide ou -1) : le panneau masque alors la ligne correspondante.

const MISSING := -1.0
const USD_PER_BILLION := 1.0e9
const UNKNOWN_AGE := -1

var tag: String = ""
var name_key: String = ""
var color: Color = Color.TRANSPARENT
var flag_path: String = ""
var capital_id: int = 0
var capital_name_key: String = ""
var regime_name_key: String = ""
var head_of_state_name: String = ""
var head_of_state_age: int = UNKNOWN_AGE
var head_of_government_name: String = ""
var head_of_government_age: int = UNKNOWN_AGE
## Faux quand le chef de l'État dirige aussi le gouvernement (régime présidentiel).
var has_separate_head_of_government: bool = false
## Noms localisables (chaîne ou {"en": …, "fr": …}).
var ruling_party_name: Variant = null
var coalition_names: Array = []
var ideology_name_key: String = ""
var population: int = 0
var area_km2: float = 0.0
var province_count: int = 0
var gdp_billion_usd: float = MISSING
var gdp_per_capita: float = MISSING
var debt_to_gdp: float = MISSING
var active_personnel: float = MISSING
## Abréviations localisables des organisations.
var organization_abbreviations: Array = []
var occupied_count: int = 0
var occupying_count: int = 0


## Renvoie null si le pays n'existe pas. current_year sert au calcul de l'âge des dirigeants.
static func build(p_tag: String, countries: Dictionary, provinces: Dictionary, names: Dictionary,
		regimes: Dictionary, ideologies: Dictionary, cultures: Dictionary = {},
		current_year: int = 0) -> CountryInfo:
	if not countries.has(p_tag):
		return null
	var country: Dictionary = countries[p_tag]
	var info := CountryInfo.new()
	info.tag = p_tag
	info.name_key = str(country.get("name_key", ""))
	info.color = Color.html(str(country.get("color", "#000000")))
	info.flag_path = CountryFlags.path_for(p_tag, country)
	info.capital_id = int(country.get("capital", 0))
	info.capital_name_key = str((provinces.get(str(info.capital_id), {}) as Dictionary).get("name_key", ""))
	info.regime_name_key = str((regimes.get(str(country.get("regime", "")), {}) as Dictionary).get("name_key", ""))
	info.ideology_name_key = str((ideologies.get(str(country.get("ideology", "")), {}) as Dictionary).get("name_key", ""))

	var characters: Dictionary = names.get("characters", {})
	var head_of_state_id := str(country.get("head_of_state", ""))
	var head_of_government_id := str(country.get("head_of_government", head_of_state_id))
	var head_of_state: Dictionary = characters.get(head_of_state_id, {})
	var head_of_government: Dictionary = characters.get(head_of_government_id, {})
	info.head_of_state_name = NameGenerator.full_name(head_of_state, cultures)
	info.head_of_state_age = age_of(head_of_state, current_year)
	info.head_of_government_name = NameGenerator.full_name(head_of_government, cultures)
	info.head_of_government_age = age_of(head_of_government, current_year)
	info.has_separate_head_of_government = head_of_government_id != head_of_state_id
	var parties: Dictionary = names.get("parties", {})
	var ruling: Dictionary = parties.get(str(country.get("ruling_party", "")), {})
	if ruling.has("name"):
		info.ruling_party_name = ruling["name"]
	for partner: Variant in country.get("coalition_partners", []):
		var party: Dictionary = parties.get(str(partner), {})
		if party.has("name"):
			info.coalition_names.append(party["name"])
	var organizations: Dictionary = names.get("organizations", {})
	for organization_id: Variant in country.get("organizations", []):
		var organization: Dictionary = organizations.get(str(organization_id), {})
		info.organization_abbreviations.append(organization.get("abbreviation", str(organization_id)))

	var province_population := 0
	for key: String in provinces.keys():
		var province: Dictionary = provinces[key]
		var owner := str(province.get("owner", ""))
		var controller := str(province.get("controller", owner))
		if owner == p_tag:
			info.province_count += 1
			info.area_km2 += float(province.get("area_km2", 0.0))
			province_population += int(province.get("population", 0))
			if controller != p_tag:
				info.occupied_count += 1
		elif controller == p_tag:
			info.occupying_count += 1
	info.population = int(country.get("population", province_population))

	var economy: Dictionary = country.get("economy", {})
	if economy.has("gdp_billion_usd"):
		info.gdp_billion_usd = float(economy["gdp_billion_usd"])
		if info.population > 0:
			info.gdp_per_capita = info.gdp_billion_usd * USD_PER_BILLION / info.population
	if economy.has("debt_to_gdp"):
		info.debt_to_gdp = float(economy["debt_to_gdp"])
	var military: Dictionary = country.get("military", {})
	if military.has("active_personnel"):
		info.active_personnel = float(military["active_personnel"])
	return info


## Âge atteint au cours de l'année donnée ; UNKNOWN_AGE si l'année ou la naissance manque.
static func age_of(character: Dictionary, current_year: int) -> int:
	if current_year <= 0 or not character.has("birth_year"):
		return UNKNOWN_AGE
	return current_year - int(character["birth_year"])

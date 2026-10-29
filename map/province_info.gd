class_name ProvinceInfo
extends RefCounted
## Prépare les informations affichées pour une province, à partir des données de jeu.
## Sans nœud ni texte traduit : le panneau d'interface se charge de l'affichage.

var province_id: int = 0
var name_key: String = ""
var owner_tag: String = ""
var owner_name_key: String = ""
var owner_color: Color = Color.TRANSPARENT
var controller_tag: String = ""
var controller_name_key: String = ""
var is_occupied: bool = false
var is_capital: bool = false
var population: int = 0
var area_km2: float = 0.0
var terrain_name_key: String = ""
var infrastructure: int = 0
var coastal: bool = false
## Couples [clé de nom de ressource, quantité], triés par quantité décroissante.
var resources: Array = []
var neighbor_count: int = 0


## Renvoie null si l'identifiant ne correspond à aucune province.
static func build(p_province_id: int, provinces: Dictionary, countries: Dictionary,
		terrains: Dictionary, resource_types: Dictionary) -> ProvinceInfo:
	var key := str(p_province_id)
	if not provinces.has(key):
		return null
	var province: Dictionary = provinces[key]
	var info := ProvinceInfo.new()
	info.province_id = p_province_id
	info.name_key = str(province.get("name_key", ""))
	info.owner_tag = str(province.get("owner", ""))
	info.controller_tag = str(province.get("controller", info.owner_tag))
	if countries.has(info.owner_tag):
		var owner: Dictionary = countries[info.owner_tag]
		info.owner_name_key = str(owner.get("name_key", ""))
		info.owner_color = Color.html(str(owner.get("color", "#000000")))
		info.is_capital = int(owner.get("capital", 0)) == p_province_id
	if countries.has(info.controller_tag):
		info.controller_name_key = str((countries[info.controller_tag] as Dictionary).get("name_key", ""))
	info.is_occupied = not info.owner_tag.is_empty() and info.controller_tag != info.owner_tag
	info.population = int(province.get("population", 0))
	info.area_km2 = float(province.get("area_km2", 0.0))
	var terrain := str(province.get("terrain", ""))
	info.terrain_name_key = str((terrains.get(terrain, {}) as Dictionary).get("name_key", terrain))
	info.infrastructure = int(province.get("infrastructure", 0))
	info.coastal = bool(province.get("coastal", false))
	var amounts: Dictionary = province.get("resources", {})
	for resource: String in amounts.keys():
		var resource_key := str((resource_types.get(resource, {}) as Dictionary).get("name_key", resource))
		info.resources.append([resource_key, float(amounts[resource])])
	info.resources.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	info.neighbor_count = (province.get("neighbors", []) as Array).size()
	return info

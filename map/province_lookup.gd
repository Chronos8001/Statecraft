class_name ProvinceLookup
extends RefCounted
## Texture de correspondance id de province → couleur affichée. Le shader de carte la lit pour
## recolorer les provinces : changer de mode de carte ne regénère que cette petite texture.

const WIDTH := 256
const SEA_INDEX := 0
const UNOWNED_INDEX := 1
const FIRST_COUNTRY_INDEX := 2


@warning_ignore("integer_division")
static func build_image(colors: PackedColorArray) -> Image:
	var rows := maxi(1, ceili(float(colors.size()) / WIDTH))
	var image := Image.create_empty(WIDTH, rows, false, Image.FORMAT_RGBA8)
	for province_id: int in colors.size():
		image.set_pixel(province_id % WIDTH, province_id / WIDTH, colors[province_id])
	return image


## Indice du pays propriétaire de chaque province, encodé comme un id (R + G × 256) :
## 0 = mer ou lac, 1 = sans propriétaire, puis un indice par pays (ordre alphabétique des tags).
static func owner_indices(provinces: Dictionary, countries: Dictionary, sea_zones: Dictionary,
		max_id: int) -> PackedColorArray:
	var index_of_tag := country_indices(countries)
	var owners := PackedColorArray()
	owners.resize(max_id + 1)
	owners.fill(ProvinceMapData.id_to_color(UNOWNED_INDEX))
	owners[0] = ProvinceMapData.id_to_color(SEA_INDEX)
	for key: String in sea_zones.keys():
		var zone_id := int(key)
		if zone_id > 0 and zone_id <= max_id:
			owners[zone_id] = ProvinceMapData.id_to_color(SEA_INDEX)
	for key: String in provinces.keys():
		var province_id := int(key)
		var owner := str((provinces[key] as Dictionary).get("owner", ""))
		if province_id > 0 and province_id <= max_id and index_of_tag.has(owner):
			owners[province_id] = ProvinceMapData.id_to_color(index_of_tag[owner])
	return owners


## Indice de chaque pays dans la texture des propriétaires (tag → indice).
static func country_indices(countries: Dictionary) -> Dictionary:
	var tags: Array = countries.keys()
	tags.sort()
	var indices: Dictionary = {}
	for i: int in tags.size():
		indices[tags[i]] = i + FIRST_COUNTRY_INDEX
	return indices

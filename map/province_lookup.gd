class_name ProvinceLookup
extends RefCounted
## Texture de correspondance id de province → couleur affichée. Le shader de carte la lit pour
## recolorer les provinces : changer de mode de carte ne regénère que cette petite texture.

const WIDTH := 256


@warning_ignore("integer_division")
static func build_image(colors: PackedColorArray) -> Image:
	var rows := maxi(1, ceili(float(colors.size()) / WIDTH))
	var image := Image.create_empty(WIDTH, rows, false, Image.FORMAT_RGBA8)
	for province_id: int in colors.size():
		image.set_pixel(province_id % WIDTH, province_id / WIDTH, colors[province_id])
	return image


## Couleurs du mode politique : couleur du propriétaire, gris si sans propriétaire, mer pour l'id 0.
static func political_colors(provinces: Dictionary, countries: Dictionary, max_id: int,
		sea_color: Color, unowned_color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(max_id + 1)
	colors.fill(unowned_color)
	colors[0] = sea_color
	for key: String in provinces.keys():
		var province_id := int(key)
		if province_id <= 0 or province_id > max_id:
			continue
		var owner: String = (provinces[key] as Dictionary).get("owner", "")
		if countries.has(owner):
			colors[province_id] = Color.html(str(countries[owner]["color"]))
	return colors

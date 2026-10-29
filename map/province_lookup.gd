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


class_name ProvinceMapData
extends RefCounted
## Image des provinces décodée en mémoire (format RG8). La couleur d'un pixel encode
## l'identifiant de sa province : id = R + G × 256 (0 = eau).

const ID_CHANNEL_BASE := 256
const CHANNEL_MAX := 255.0

var width: int = 0
var height: int = 0
var id_image: Image


## Charge un PNG de provinces. Peut être appelé depuis un thread. Renvoie null en cas d'erreur.
static func from_png_file(path: String) -> ProvinceMapData:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return from_image(image)


static func from_image(image: Image) -> ProvinceMapData:
	if image.get_format() != Image.FORMAT_RG8:
		image.convert(Image.FORMAT_RG8)
	var data := ProvinceMapData.new()
	data.id_image = image
	data.width = image.get_width()
	data.height = image.get_height()
	return data


@warning_ignore("integer_division")
static func id_to_color(province_id: int) -> Color:
	return Color8(province_id % ID_CHANNEL_BASE, (province_id / ID_CHANNEL_BASE) % ID_CHANNEL_BASE, 0)


static func color_to_id(color: Color) -> int:
	return roundi(color.r * CHANNEL_MAX) + roundi(color.g * CHANNEL_MAX) * ID_CHANNEL_BASE


## Identifiant de la province à une position de carte (en pixels, bouclage est-ouest). 0 = eau ou hors carte.
func get_province_at(map_position: Vector2) -> int:
	var y := floori(map_position.y)
	if y < 0 or y >= height:
		return 0
	var x := posmod(floori(map_position.x), width)
	return color_to_id(id_image.get_pixel(x, y))

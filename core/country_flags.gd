class_name CountryFlags
extends RefCounted
## Drapeaux des pays : chemin de l'image et textures mises en cache.
## Un pays peut indiquer son propre fichier (champ « flag ») ; sinon assets/flags/<TAG>.svg.
## Sans image, le drapeau est un rectangle de la couleur du pays.

const DEFAULT_PATH := "res://assets/flags/%s.svg"
## Proportions communes à tous les drapeaux (4:3).
const ASPECT := Vector2i(4, 3)

static var _textures: Dictionary = {}


static func path_for(tag: String, country: Dictionary) -> String:
	var custom := str(country.get("flag", ""))
	return custom if not custom.is_empty() else DEFAULT_PATH % tag


static func has_image(path: String) -> bool:
	return ResourceLoader.exists(path, "Texture2D")


## Texture du drapeau ; repli sur fallback_color si l'image est introuvable.
static func texture_for(path: String, fallback_color: Color) -> Texture2D:
	var key := "%s|%s" % [path, fallback_color.to_html()]
	if _textures.has(key):
		return _textures[key]
	var texture: Texture2D = load(path) as Texture2D if has_image(path) else null
	if texture == null:
		texture = placeholder(fallback_color)
	_textures[key] = texture
	return texture


static func placeholder(color: Color) -> Texture2D:
	var image := Image.create(ASPECT.x, ASPECT.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


static func clear_cache() -> void:
	_textures.clear()

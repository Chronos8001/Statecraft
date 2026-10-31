class_name CountrySelectionPanel
extends Control
## Écran de sélection du pays, posé sur la carte : filtres et liste à gauche, résumé à droite.
## La carte reste visible et cliquable entre les deux panneaux.

## Pays choisi dans la liste (from_list) ou sur la carte.
signal country_selected(tag: String, from_list: bool)
signal play_requested(tag: String)

const FLAG_ICON_SIZE := Vector2i(32, 24)
## Lettres accentuées ramenées à leur base pour le tri et la recherche (« Égypte » avec les E).
const FOLDED_LETTERS := {
	"à": "a", "â": "a", "ä": "a", "á": "a", "ã": "a", "å": "a", "ç": "c", "é": "e", "è": "e", "ê": "e",
	"ë": "e", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ó": "o", "ô": "o", "ö": "o", "õ": "o", "ú": "u",
	"û": "u", "ü": "u", "ÿ": "y", "œ": "oe", "æ": "ae",
}

var selection: CountrySelection
var _listed_tags: Array[String] = []
var _selected_tag: String = ""

@onready var _search_edit: LineEdit = %SearchEdit
@onready var _difficulty_option: OptionButton = %DifficultyOption
@onready var _limited_check: CheckBox = %LimitedCheck
@onready var _country_list: ItemList = %CountryList
@onready var _count_label: Label = %CountLabel
@onready var _summary: CountrySummary = %CountrySummary


func _ready() -> void:
	selection = CountrySelection.build(DataLoader.get_category("countries"), DataLoader.get_category("provinces"),
		DataLoader.get_category("challenges"), DataLoader.get_define("country_selection", {}))
	_country_list.fixed_icon_size = FLAG_ICON_SIZE
	_search_edit.text_changed.connect(func(_text: String) -> void: _rebuild_list())
	_difficulty_option.item_selected.connect(func(_index: int) -> void: _rebuild_list())
	_limited_check.toggled.connect(func(_pressed: bool) -> void: _rebuild_list())
	_country_list.item_selected.connect(func(index: int) -> void: select_country(_listed_tags[index], true))
	_summary.play_requested.connect(func(tag: String) -> void: play_requested.emit(tag))
	EventBus.locale_changed.connect(func(_locale: String) -> void:
		_fill_difficulties()
		_rebuild_list())
	_fill_difficulties()
	_rebuild_list()


## Choisit un pays (liste ou carte). Renvoie false s'il n'est pas jouable avec les filtres actuels.
func select_country(tag: String, from_list: bool = false) -> bool:
	if not selection.is_playable(tag, _limited_check.button_pressed):
		return false
	_selected_tag = tag
	var info := CountryInfo.build(tag, DataLoader.get_category("countries"), DataLoader.get_category("provinces"),
		DataLoader.get_category("names"), DataLoader.get_category("regimes"), DataLoader.get_category("ideologies"),
		DataLoader.get_category("names/cultures"), GameState.sim.date.year)
	info.apply_economy(GameState.sim)
	var challenge_ids: Array[String] = selection.challenges.get(tag, [] as Array[String])
	_summary.show_country(info, int(selection.difficulties[tag]), challenge_ids)
	_select_in_list()
	country_selected.emit(tag, from_list)
	return true


func get_selected_tag() -> String:
	return _selected_tag


func _fill_difficulties() -> void:
	var current := maxi(_difficulty_option.selected, 0)
	_difficulty_option.clear()
	_difficulty_option.add_item(tr("SELECTION_ALL_DIFFICULTIES"), CountrySelection.ANY_DIFFICULTY)
	for level: int in range(CountrySelection.MIN_DIFFICULTY, CountrySelection.MAX_DIFFICULTY + 1):
		_difficulty_option.add_item(tr(CountrySummary.DIFFICULTY_KEY % level), level)
	_difficulty_option.select(current)


func _rebuild_list() -> void:
	var difficulty := _difficulty_option.get_selected_id() if _difficulty_option.selected >= 0 \
		else CountrySelection.ANY_DIFFICULTY
	var search := fold(_search_edit.text.strip_edges())
	var countries := DataLoader.get_category("countries")
	var entries: Array = []
	for tag: String in selection.playable_tags(_limited_check.button_pressed, difficulty):
		var country_name := tr(str((countries[tag] as Dictionary).get("name_key", tag)))
		var key := fold(country_name)
		if not search.is_empty() and not key.contains(search) and not tag.to_lower().contains(search):
			continue
		entries.append([key, tag, country_name])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	_country_list.clear()
	_listed_tags.clear()
	for entry: Array in entries:
		var tag := str(entry[1])
		var country: Dictionary = countries[tag]
		var index := _country_list.add_item(str(entry[2]), CountryFlags.texture_for(CountryFlags.path_for(tag, country),
			Color.html(str(country.get("color", "#808080")))))
		var level := int(selection.difficulties[tag])
		_country_list.set_item_tooltip(index, tr("SELECTION_DIFFICULTY_VALUE") % tr(CountrySummary.DIFFICULTY_KEY % level))
		_country_list.set_item_custom_fg_color(index, CountrySummary.difficulty_color(level))
		_listed_tags.append(tag)
	_count_label.text = tr("SELECTION_COUNT") % _listed_tags.size()
	_select_in_list()


func _select_in_list() -> void:
	var index := _listed_tags.find(_selected_tag)
	if index >= 0:
		_country_list.select(index)
		_country_list.ensure_current_is_visible()
	else:
		_country_list.deselect_all()


## Minuscules sans accents, pour trier et chercher.
static func fold(text: String) -> String:
	var lower := text.to_lower()
	var result := ""
	for character: String in lower:
		result += str(FOLDED_LETTERS.get(character, character))
	return result

class_name CountrySummary
extends InfoPanel
## Résumé d'un pays sur l'écran de sélection : drapeau, difficulté, chiffres clés et défis de départ.

signal play_requested(tag: String)

const DIFFICULTY_KEY := "DIFFICULTY_%d"
const CHALLENGE_NAME_COLOR := Color(0.95, 0.82, 0.5)

var _info: CountryInfo
var _difficulty: int = CountrySelection.MIN_DIFFICULTY
var _challenge_ids: Array[String] = []

@onready var _flag: TextureRect = %FlagRect
@onready var _name_label: Label = %NameLabel
@onready var _difficulty_label: Label = %DifficultyLabel
@onready var _stats_grid: GridContainer = %StatsGrid
@onready var _challenges_title: Label = %ChallengesTitle
@onready var _challenges_box: VBoxContainer = %ChallengesBox
@onready var _play_button: Button = %PlayButton


func _ready() -> void:
	_play_button.pressed.connect(func() -> void:
		if _info != null:
			play_requested.emit(_info.tag))
	EventBus.locale_changed.connect(func(_locale: String) -> void: _refresh())
	_refresh()


func show_country(info: CountryInfo, difficulty: int, challenge_ids: Array[String]) -> void:
	_info = info
	_difficulty = difficulty
	_challenge_ids = challenge_ids
	_refresh()


func get_tag() -> String:
	return _info.tag if _info != null else ""


func _refresh() -> void:
	_play_button.disabled = _info == null
	_clear_rows(_stats_grid)
	for child: Node in _challenges_box.get_children():
		_challenges_box.remove_child(child)
		child.queue_free()
	if _info == null:
		_flag.texture = null
		_name_label.text = tr("SELECTION_NONE")
		_difficulty_label.text = ""
		_challenges_title.visible = false
		return
	var locale := Localization.get_locale()
	_flag.texture = CountryFlags.texture_for(_info.flag_path, _info.color)
	_name_label.text = tr(_info.name_key)
	_difficulty_label.text = tr("SELECTION_DIFFICULTY_VALUE") % tr(DIFFICULTY_KEY % _difficulty)
	_difficulty_label.add_theme_color_override("font_color", difficulty_color(_difficulty))
	_add_row(_stats_grid, "COUNTRY_INFO_REGIME", tr(_info.regime_name_key) if not _info.regime_name_key.is_empty() else "")
	_add_row(_stats_grid, "COUNTRY_INFO_HEAD_OF_STATE", _info.head_of_state_name)
	if _info.has_separate_head_of_government:
		_add_row(_stats_grid, "COUNTRY_INFO_HEAD_OF_GOVERNMENT", _info.head_of_government_name)
	if _info.ruling_party_name != null:
		_add_row(_stats_grid, "COUNTRY_INFO_RULING_PARTY", Localization.pick_text(_info.ruling_party_name))
	_add_row(_stats_grid, "INFO_POPULATION", NumberFormat.integer(_info.population, locale))
	if _info.gdp_billion_usd >= 0.0:
		_add_row(_stats_grid, "COUNTRY_INFO_GDP",
			tr("COUNTRY_INFO_GDP_VALUE") % NumberFormat.integer(roundi(_info.gdp_billion_usd), locale))
	if _info.gdp_per_capita >= 0.0:
		_add_row(_stats_grid, "COUNTRY_INFO_GDP_PER_CAPITA",
			tr("COUNTRY_INFO_USD_VALUE") % NumberFormat.integer(roundi(_info.gdp_per_capita), locale))
	if _info.debt_to_gdp >= 0.0:
		_add_row(_stats_grid, "COUNTRY_INFO_DEBT", tr("COUNTRY_INFO_DEBT_VALUE") % roundi(_info.debt_to_gdp * 100.0))
	if _info.active_personnel >= 0.0:
		_add_row(_stats_grid, "COUNTRY_INFO_ACTIVE_PERSONNEL", NumberFormat.integer(roundi(_info.active_personnel), locale))
	var organizations := PackedStringArray()
	for abbreviation: Variant in _info.organization_abbreviations:
		organizations.append(Localization.pick_text(abbreviation))
	_add_row(_stats_grid, "COUNTRY_INFO_ORGANIZATIONS", LIST_SEPARATOR.join(organizations))
	_challenges_title.visible = not _challenge_ids.is_empty()
	var challenges := DataLoader.get_category("challenges")
	for challenge_id: String in _challenge_ids:
		var challenge: Dictionary = challenges.get(challenge_id, {})
		var title := Label.new()
		title.text = str(challenge.get("name_key", challenge_id))
		title.add_theme_color_override("font_color", CHALLENGE_NAME_COLOR)
		_challenges_box.add_child(title)
		var description := Label.new()
		description.text = str(challenge.get("description_key", ""))
		description.add_theme_color_override("font_color", LABEL_COLOR)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_challenges_box.add_child(description)


static func difficulty_color(difficulty: int) -> Color:
	var colors: Array = DataLoader.get_define("country_selection.difficulty_colors", [])
	var index := difficulty - CountrySelection.MIN_DIFFICULTY
	return Color.html(str(colors[index])) if index >= 0 and index < colors.size() else Color.WHITE

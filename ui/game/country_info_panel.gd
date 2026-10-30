class_name CountryInfoPanel
extends InfoPanel
## Panneau d'information d'un pays (ouvert par un clic simple sur la carte).

var _info: CountryInfo

@onready var _name_label: Label = %NameLabel
@onready var _tag_label: Label = %TagLabel
@onready var _swatch: ColorRect = %CountrySwatch
@onready var _stats_grid: GridContainer = %StatsGrid
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	EventBus.locale_changed.connect(func(_locale: String) -> void: _refresh())
	visible = false


func show_country(info: CountryInfo) -> void:
	_info = info
	_refresh()
	visible = true


func get_tag() -> String:
	return _info.tag if _info != null and visible else ""


func _refresh() -> void:
	if _info == null:
		return
	var locale := Localization.get_locale()
	_name_label.text = tr(_info.name_key)
	_tag_label.text = _info.tag
	_swatch.color = _info.color
	_clear_rows(_stats_grid)
	_add_row(_stats_grid, "COUNTRY_INFO_CAPITAL", tr(_info.capital_name_key) if not _info.capital_name_key.is_empty() else "")
	_add_row(_stats_grid, "COUNTRY_INFO_REGIME", _translated(_info.regime_name_key))
	_add_row(_stats_grid, "COUNTRY_INFO_HEAD_OF_STATE", _leader(_info.head_of_state_name, _info.head_of_state_age))
	if _info.has_separate_head_of_government:
		_add_row(_stats_grid, "COUNTRY_INFO_HEAD_OF_GOVERNMENT",
			_leader(_info.head_of_government_name, _info.head_of_government_age))
	if _info.ruling_party_name != null:
		_add_row(_stats_grid, "COUNTRY_INFO_RULING_PARTY", Localization.pick_text(_info.ruling_party_name))
	_add_row(_stats_grid, "COUNTRY_INFO_COALITION", _join_texts(_info.coalition_names))
	_add_row(_stats_grid, "COUNTRY_INFO_IDEOLOGY", _translated(_info.ideology_name_key))
	_add_row(_stats_grid, "INFO_POPULATION", NumberFormat.integer(_info.population, locale))
	_add_row(_stats_grid, "INFO_AREA", tr("INFO_AREA_VALUE") % NumberFormat.integer(roundi(_info.area_km2), locale))
	_add_row(_stats_grid, "COUNTRY_INFO_PROVINCES", str(_info.province_count))
	if _info.gdp_billion_usd >= 0.0:
		_add_row(_stats_grid, "COUNTRY_INFO_GDP", tr("COUNTRY_INFO_GDP_VALUE") % NumberFormat.integer(roundi(_info.gdp_billion_usd), locale))
	if _info.gdp_per_capita >= 0.0:
		_add_row(_stats_grid, "COUNTRY_INFO_GDP_PER_CAPITA", tr("COUNTRY_INFO_USD_VALUE") % NumberFormat.integer(roundi(_info.gdp_per_capita), locale))
	if _info.debt_to_gdp >= 0.0:
		_add_row(_stats_grid, "COUNTRY_INFO_DEBT", tr("COUNTRY_INFO_DEBT_VALUE") % roundi(_info.debt_to_gdp * 100.0))
	if _info.active_personnel >= 0.0:
		_add_row(_stats_grid, "COUNTRY_INFO_ACTIVE_PERSONNEL", NumberFormat.integer(roundi(_info.active_personnel), locale))
	_add_row(_stats_grid, "COUNTRY_INFO_ORGANIZATIONS", _join_texts(_info.organization_abbreviations))
	if _info.occupied_count > 0:
		_add_row(_stats_grid, "COUNTRY_INFO_OCCUPIED", tr("COUNTRY_INFO_PROVINCE_COUNT") % _info.occupied_count)
	if _info.occupying_count > 0:
		_add_row(_stats_grid, "COUNTRY_INFO_OCCUPYING", tr("COUNTRY_INFO_PROVINCE_COUNT") % _info.occupying_count)


## « Nom (âge) » ; le nom seul si l'âge est inconnu.
func _leader(leader_name: String, age: int) -> String:
	if leader_name.is_empty() or age == CountryInfo.UNKNOWN_AGE:
		return leader_name
	return tr("COUNTRY_INFO_LEADER_VALUE") % [leader_name, age]


func _translated(key: String) -> String:
	return tr(key) if not key.is_empty() else ""


func _join_texts(values: Array) -> String:
	var parts := PackedStringArray()
	for value: Variant in values:
		parts.append(Localization.pick_text(value))
	return LIST_SEPARATOR.join(parts)

class_name ProvinceInfoPanel
extends InfoPanel
## Panneau d'information d'une province ou d'une zone maritime.

var _info: ProvinceInfo

@onready var _name_label: Label = %NameLabel
@onready var _id_label: Label = %IdLabel
@onready var _country_swatch: ColorRect = %CountrySwatch
@onready var _country_label: Label = %CountryLabel
@onready var _occupation_label: Label = %OccupationLabel
@onready var _capital_label: Label = %CapitalLabel
@onready var _stats_grid: GridContainer = %StatsGrid
@onready var _close_button: Button = %CloseButton
@onready var _buildings: BuildingsSection = %BuildingsSection


func _ready() -> void:
	_close_button.pressed.connect(close)
	EventBus.locale_changed.connect(func(_locale: String) -> void: _refresh())
	visible = false


func show_province(info: ProvinceInfo) -> void:
	_info = info
	_refresh()
	visible = true


func _refresh() -> void:
	if _info == null:
		return
	var locale := Localization.get_locale()
	_name_label.text = tr(_info.name_key)
	_id_label.text = tr("INFO_SEA_ZONE_ID" if _info.is_sea_zone else "INFO_PROVINCE_ID") % _info.province_id
	var has_owner := not _info.owner_name_key.is_empty()
	_country_swatch.visible = has_owner
	_country_swatch.color = _info.owner_color
	if _info.is_sea_zone:
		_country_label.text = tr(_info.sea_kind_key)
	else:
		_country_label.text = tr(_info.owner_name_key) if has_owner else tr("INFO_UNOWNED")
	_occupation_label.visible = _info.is_occupied
	_occupation_label.text = tr("INFO_OCCUPIED_BY") % tr(_info.controller_name_key)
	_capital_label.visible = _info.is_capital

	_clear_rows(_stats_grid)
	_buildings.show_province("" if _info.is_sea_zone else str(_info.province_id))
	if _info.is_sea_zone:
		_add_row(_stats_grid, "INFO_AREA", tr("INFO_AREA_VALUE") % NumberFormat.integer(roundi(_info.area_km2), locale))
		_add_row(_stats_grid, "INFO_SEA_NEIGHBORS", str(_info.neighbor_count))
		_add_row(_stats_grid, "INFO_COASTS", str(_info.coast_count))
		_add_straits_row()
		return
	_add_row(_stats_grid, "INFO_POPULATION", NumberFormat.integer(_info.population, locale))
	_add_row(_stats_grid, "INFO_AREA", tr("INFO_AREA_VALUE") % NumberFormat.integer(roundi(_info.area_km2), locale))
	_add_row(_stats_grid, "INFO_TERRAIN", tr(_info.terrain_name_key))
	_add_row(_stats_grid, "INFO_INFRASTRUCTURE", tr("INFO_INFRASTRUCTURE_VALUE") % [
		_info.infrastructure, int(DataLoader.get_define("province.max_infrastructure"))])
	_add_row(_stats_grid, "INFO_COASTAL", tr("COMMON_YES") if _info.coastal else tr("COMMON_NO"))
	_add_row(_stats_grid, "INFO_RESOURCES", _resources_text())
	_add_row(_stats_grid, "INFO_NEIGHBORS", str(_info.neighbor_count))
	_add_straits_row()


func _add_straits_row() -> void:
	if _info.strait_name_keys.is_empty():
		return
	var names := PackedStringArray()
	for key: String in _info.strait_name_keys:
		names.append(tr(key))
	_add_row(_stats_grid, "INFO_STRAITS", LIST_SEPARATOR.join(names))


func _resources_text() -> String:
	if _info.resources.is_empty():
		return tr("INFO_RESOURCES_NONE")
	var parts := PackedStringArray()
	for entry: Array in _info.resources:
		parts.append("%s %s" % [tr(str(entry[0])), str(entry[1])])
	return LIST_SEPARATOR.join(parts)

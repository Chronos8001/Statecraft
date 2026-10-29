class_name ProvinceInfoPanel
extends PanelContainer
## Panneau d'information d'une province : nom, pays, occupation, statistiques.

signal closed

const RESOURCE_SEPARATOR := ", "

var _info: ProvinceInfo

@onready var _name_label: Label = %NameLabel
@onready var _id_label: Label = %IdLabel
@onready var _country_swatch: ColorRect = %CountrySwatch
@onready var _country_label: Label = %CountryLabel
@onready var _occupation_label: Label = %OccupationLabel
@onready var _capital_label: Label = %CapitalLabel
@onready var _stats_grid: GridContainer = %StatsGrid
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	EventBus.locale_changed.connect(func(_locale: String) -> void: _refresh())
	visible = false


func show_province(info: ProvinceInfo) -> void:
	_info = info
	_refresh()
	visible = true


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _refresh() -> void:
	if _info == null:
		return
	var locale := Localization.get_locale()
	_name_label.text = tr(_info.name_key)
	_id_label.text = tr("INFO_PROVINCE_ID") % _info.province_id
	var has_owner := not _info.owner_name_key.is_empty()
	_country_swatch.visible = has_owner
	_country_swatch.color = _info.owner_color
	_country_label.text = tr(_info.owner_name_key) if has_owner else tr("INFO_UNOWNED")
	_occupation_label.visible = _info.is_occupied
	_occupation_label.text = tr("INFO_OCCUPIED_BY") % tr(_info.controller_name_key)
	_capital_label.visible = _info.is_capital

	for child: Node in _stats_grid.get_children():
		_stats_grid.remove_child(child)
		child.queue_free()
	_add_row("INFO_POPULATION", NumberFormat.integer(_info.population, locale))
	_add_row("INFO_AREA", tr("INFO_AREA_VALUE") % NumberFormat.integer(roundi(_info.area_km2), locale))
	_add_row("INFO_TERRAIN", tr(_info.terrain_name_key))
	_add_row("INFO_INFRASTRUCTURE", tr("INFO_INFRASTRUCTURE_VALUE") % [
		_info.infrastructure, int(DataLoader.get_define("province.max_infrastructure"))])
	_add_row("INFO_COASTAL", tr("COMMON_YES") if _info.coastal else tr("COMMON_NO"))
	_add_row("INFO_RESOURCES", _resources_text())
	_add_row("INFO_NEIGHBORS", str(_info.neighbor_count))


func _resources_text() -> String:
	if _info.resources.is_empty():
		return tr("INFO_RESOURCES_NONE")
	var parts := PackedStringArray()
	for entry: Array in _info.resources:
		parts.append("%s %s" % [tr(str(entry[0])), str(entry[1])])
	return RESOURCE_SEPARATOR.join(parts)


func _add_row(label_key: String, value: String) -> void:
	var label := Label.new()
	label.text = label_key
	label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.76))
	_stats_grid.add_child(label)
	var value_label := Label.new()
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_grid.add_child(value_label)

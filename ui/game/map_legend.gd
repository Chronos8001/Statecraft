class_name MapLegend
extends PanelContainer
## Légende du mode de carte affiché.

const SWATCH_SIZE := Vector2(14, 14)

var _mode: MapMode
var _context: MapModeContext

@onready var _title: Label = %LegendTitle
@onready var _entries: VBoxContainer = %LegendEntries


func _ready() -> void:
	EventBus.locale_changed.connect(func(_locale: String) -> void: _refresh())


func show_mode(mode: MapMode, context: MapModeContext) -> void:
	_mode = mode
	_context = context
	_refresh()


func _refresh() -> void:
	if _mode == null:
		return
	_title.text = tr(_mode.name_key)
	for child: Node in _entries.get_children():
		child.queue_free()
	var legend := _mode.get_legend(_context)
	visible = not legend.is_empty()
	for entry: Dictionary in legend:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = entry["color"]
		row.add_child(swatch)
		var label := Label.new()
		label.text = _label_text(entry)
		row.add_child(label)
		_entries.add_child(row)


func _label_text(entry: Dictionary) -> String:
	if entry.has("label_key"):
		return tr(str(entry["label_key"]))
	var number := NumberFormat.integer(roundi(float(entry["value"])), Localization.get_locale())
	var unit_key := str(entry.get("unit_key", ""))
	return tr(unit_key) % number if not unit_key.is_empty() else number

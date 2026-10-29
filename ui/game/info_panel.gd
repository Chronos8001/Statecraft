class_name InfoPanel
extends PanelContainer
## Base des panneaux d'information (province, pays) : fermeture et lignes « libellé / valeur ».

signal closed

const LABEL_COLOR := Color(0.62, 0.68, 0.76)
const LIST_SEPARATOR := ", "


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _clear_rows(grid: GridContainer) -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()


func _add_row(grid: GridContainer, label_key: String, value: String) -> void:
	if value.is_empty():
		return
	var label := Label.new()
	label.text = label_key
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_child(label)
	var value_label := Label.new()
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid.add_child(value_label)

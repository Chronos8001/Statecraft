class_name ColorGradient
extends RefCounted
## Dégradé de couleurs défini par des paliers [valeur, "#couleur"], linéaire ou logarithmique.

const MIN_LOG_VALUE := 0.0001

var values: PackedFloat64Array = PackedFloat64Array()
var colors: PackedColorArray = PackedColorArray()
var logarithmic: bool = false


static func from_stops(stops: Array, p_logarithmic: bool) -> ColorGradient:
	var gradient := ColorGradient.new()
	gradient.logarithmic = p_logarithmic
	for stop: Array in stops:
		gradient.values.append(float(stop[0]))
		gradient.colors.append(Color.html(str(stop[1])))
	return gradient


func sample(value: float) -> Color:
	if colors.is_empty():
		return Color.BLACK
	var position := _transform(value)
	if position <= _transform(values[0]):
		return colors[0]
	for i: int in range(1, values.size()):
		var high := _transform(values[i])
		if position <= high:
			var low := _transform(values[i - 1])
			var weight := 0.0 if is_equal_approx(high, low) else (position - low) / (high - low)
			return colors[i - 1].lerp(colors[i], weight)
	return colors[colors.size() - 1]


func _transform(value: float) -> float:
	return log(maxf(value, MIN_LOG_VALUE)) if logarithmic else value

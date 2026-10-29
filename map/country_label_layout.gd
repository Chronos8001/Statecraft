class_name CountryLabelLayout
extends RefCounted
## Courbe (en pixels de carte) le long de laquelle écrire le nom d'un pays.
## Calcul : plus grand territoire d'un seul tenant du pays, axe principal de ses provinces
## (pondérées par leur taille), puis parabole ajustée le long de cet axe.

const SAMPLE_COUNT := 24
## Points testés le long de la courbe pour ne garder que la partie située dans le pays.
const CLIP_SAMPLE_COUNT := 64
## Part de la longueur utile du territoire conservée pour le texte (marge aux extrémités).
const LENGTH_MARGIN := 0.85
const MIN_DETERMINANT := 0.000001
const MIN_POINTS_FOR_CURVE := 3

var tag: String = ""
## Points de la courbe, de gauche à droite. Les x peuvent sortir de 0..largeur (pays à cheval sur le bord).
var points: PackedVector2Array = PackedVector2Array()
var length: float = 0.0
## Épaisseur du territoire perpendiculairement à la courbe.
var thickness: float = 0.0
## Courbe complète avant rééchantillonnage (sert au découpage).
var _curve: PackedVector2Array = PackedVector2Array()


## owner_at (facultatif) : Callable(Vector2) -> String donnant le pays sous un point de carte ;
## la courbe est alors réduite à son plus long morceau situé dans le pays.
static func compute_all(provinces: Dictionary, map_width: float, max_bend: float = 0.3,
		owner_at: Callable = Callable()) -> Dictionary:
	var by_owner: Dictionary = {}
	for key: String in provinces.keys():
		var owner := str((provinces[key] as Dictionary).get("owner", ""))
		if not owner.is_empty():
			if not by_owner.has(owner):
				by_owner[owner] = []
			(by_owner[owner] as Array).append(key)
	var layouts: Dictionary = {}
	for owner: String in by_owner.keys():
		var component := _largest_component(by_owner[owner], provinces)
		var layout := compute(owner, component, provinces, map_width, max_bend)
		if layout != null and owner_at.is_valid():
			layout.clip_to_owner(owner_at)
		if layout != null:
			layouts[owner] = layout
	return layouts


static func compute(p_tag: String, keys: Array, provinces: Dictionary, map_width: float,
		max_bend: float) -> CountryLabelLayout:
	if keys.is_empty():
		return null
	# Centres et poids, x déplié autour de la moyenne circulaire (pays à cheval sur le bord est-ouest).
	var reference := _circular_mean_x(keys, provinces, map_width)
	var centers := PackedVector2Array()
	var weights := PackedFloat64Array()
	var radii := PackedFloat64Array()
	var total_weight := 0.0
	var centroid := Vector2.ZERO
	for key: String in keys:
		var province: Dictionary = provinces[key]
		var center_data: Array = province["center"]
		var x := float(center_data[0])
		x = reference + wrapf(x - reference, -map_width * 0.5, map_width * 0.5)
		var center := Vector2(x, float(center_data[1]))
		var weight := maxf(float(province.get("size", 1)), 1.0)
		centers.append(center)
		weights.append(weight)
		radii.append(sqrt(weight / PI))
		centroid += center * weight
		total_weight += weight
	centroid /= total_weight

	# Axe principal (covariance pondérée).
	var cxx := 0.0
	var cyy := 0.0
	var cxy := 0.0
	for i: int in centers.size():
		var d := centers[i] - centroid
		cxx += weights[i] * d.x * d.x
		cyy += weights[i] * d.y * d.y
		cxy += weights[i] * d.x * d.y
	var angle := 0.5 * atan2(2.0 * cxy, cxx - cyy)
	var axis := Vector2(cos(angle), sin(angle))
	if axis.x < 0.0:
		axis = -axis
	var normal := Vector2(-axis.y, axis.x)

	# Coordonnées le long de l'axe (t) et perpendiculaires (u).
	var t_min := INF
	var t_max := -INF
	var ts := PackedFloat64Array()
	var us := PackedFloat64Array()
	for i: int in centers.size():
		var d := centers[i] - centroid
		var t := d.dot(axis)
		ts.append(t)
		us.append(d.dot(normal))
		t_min = minf(t_min, t - radii[i])
		t_max = maxf(t_max, t + radii[i])
	var coefficients := _fit_parabola(ts, us, weights)
	var half_length := (t_max - t_min) * 0.5
	# Courbure limitée : la flèche ne dépasse pas max_bend × demi-longueur.
	if half_length > 0.0 and absf(coefficients.x) * half_length * half_length > max_bend * half_length:
		coefficients.x = signf(coefficients.x) * max_bend / half_length

	var residual := 0.0
	for i: int in ts.size():
		var fitted := coefficients.x * ts[i] * ts[i] + coefficients.y * ts[i] + coefficients.z
		residual += weights[i] * (us[i] - fitted) * (us[i] - fitted)
	var mean_radius := 0.0
	for i: int in radii.size():
		mean_radius += radii[i] * weights[i]
	mean_radius /= total_weight

	var layout := CountryLabelLayout.new()
	layout.tag = p_tag
	layout.thickness = 2.0 * (sqrt(residual / total_weight) + mean_radius)
	var middle := (t_min + t_max) * 0.5
	var span := half_length * LENGTH_MARGIN
	var curve := PackedVector2Array()
	for s: int in CLIP_SAMPLE_COUNT:
		var t := middle - span + 2.0 * span * float(s) / float(CLIP_SAMPLE_COUNT - 1)
		var u := coefficients.x * t * t + coefficients.y * t + coefficients.z
		curve.append(centroid + axis * t + normal * u)
	layout._set_curve(curve)
	return layout


## Garde le plus long morceau de la courbe dont les points sont dans le pays.
func clip_to_owner(owner_at: Callable) -> void:
	var best_start := 0
	var best_count := 0
	var run_start := 0
	var run_count := 0
	for i: int in _curve.size():
		if str(owner_at.call(_curve[i])) == tag:
			if run_count == 0:
				run_start = i
			run_count += 1
			if run_count > best_count:
				best_count = run_count
				best_start = run_start
		else:
			run_count = 0
	if best_count >= 2 and best_count < _curve.size():
		_set_curve(_curve.slice(best_start, best_start + best_count))



## Rééchantillonne une polyligne en SAMPLE_COUNT points régulièrement espacés.
func _set_curve(curve: PackedVector2Array) -> void:
	_curve = curve
	var cumulative := PackedFloat64Array([0.0])
	for i: int in range(1, curve.size()):
		cumulative.append(cumulative[i - 1] + curve[i].distance_to(curve[i - 1]))
	length = cumulative[cumulative.size() - 1]
	points = PackedVector2Array()
	var segment := 1
	for s: int in SAMPLE_COUNT:
		var target := length * float(s) / float(SAMPLE_COUNT - 1)
		while segment < curve.size() - 1 and cumulative[segment] < target:
			segment += 1
		var piece := cumulative[segment] - cumulative[segment - 1] if curve.size() > 1 else 0.0
		var weight := 0.0 if piece <= 0.0 else (target - cumulative[segment - 1]) / piece
		points.append(curve[segment - 1].lerp(curve[mini(segment, curve.size() - 1)], clampf(weight, 0.0, 1.0)))


## Moindres carrés pondérés u = a t² + b t + c. Renvoie (a, b, c) ; droite (0, 0, moyenne) si dégénéré.
## Les valeurs sont ramenées vers 1 avant le calcul : la matrice 3 × 3 de Godot est en simple précision.
static func _fit_parabola(ts: PackedFloat64Array, us: PackedFloat64Array, weights: PackedFloat64Array) -> Vector3:
	var total := 0.0
	var mean_u := 0.0
	var scale := 0.0
	for i: int in ts.size():
		total += weights[i]
		mean_u += weights[i] * us[i]
		scale = maxf(scale, absf(ts[i]))
	mean_u /= maxf(total, 1.0)
	if ts.size() < MIN_POINTS_FOR_CURVE or scale <= 0.0:
		return Vector3(0.0, 0.0, mean_u)
	var s := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var r := Vector3.ZERO
	for i: int in ts.size():
		var w := weights[i] / total
		var t := ts[i] / scale
		var u := us[i] / scale
		var power := 1.0
		for k: int in 5:
			s[k] += w * power
			power *= t
		r += Vector3(w * u * t * t, w * u * t, w * u)
	var matrix := Basis(Vector3(s[4], s[3], s[2]), Vector3(s[3], s[2], s[1]), Vector3(s[2], s[1], s[0]))
	if absf(matrix.determinant()) < MIN_DETERMINANT:
		return Vector3(0.0, 0.0, mean_u)
	var normalized := matrix.inverse() * r
	return Vector3(normalized.x / scale, normalized.y, normalized.z * scale)


static func _circular_mean_x(keys: Array, provinces: Dictionary, map_width: float) -> float:
	var sum := Vector2.ZERO
	for key: String in keys:
		var province: Dictionary = provinces[key]
		var angle := float((province["center"] as Array)[0]) / map_width * TAU
		sum += Vector2(cos(angle), sin(angle)) * maxf(float(province.get("size", 1)), 1.0)
	return fposmod(sum.angle() / TAU * map_width, map_width)


## Plus grand ensemble de provinces voisines d'un même pays (en taille cumulée).
static func _largest_component(keys: Array, provinces: Dictionary) -> Array:
	var remaining: Dictionary = {}
	for key: String in keys:
		remaining[key] = true
	var best: Array = []
	var best_size := -1.0
	while not remaining.is_empty():
		var start: String = remaining.keys()[0]
		remaining.erase(start)
		var component: Array = [start]
		var size := 0.0
		var index := 0
		while index < component.size():
			var key: String = component[index]
			index += 1
			var province: Dictionary = provinces[key]
			size += float(province.get("size", 1))
			for neighbor: Variant in province.get("neighbors", []):
				var neighbor_key := SchemaValidator.to_key(neighbor)
				if remaining.has(neighbor_key):
					remaining.erase(neighbor_key)
					component.append(neighbor_key)
		if size > best_size:
			best_size = size
			best = component
	return best

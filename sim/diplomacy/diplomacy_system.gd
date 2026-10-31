class_name DiplomacySystem
extends SimSystem
## Diplomatie, une fois par mois : sans nouvel événement, les relations reviennent lentement à leur niveau
## naturel (celui de 2026), l'opinion publique suit les relations avec retard et la confiance se refait peu
## à peu.

const PRIORITY := 30
## Écart en dessous duquel une paire revient exactement à son niveau de départ.
const CLEANUP := 0.05


func get_id() -> StringName:
	return &"diplomacy"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	var settings := state.diplomacy_settings
	if settings.is_empty():
		return
	var diplomacy := state.diplomacy
	var relation_return := float(settings.get("relation_return", 0.0))
	var follow := float(settings.get("opinion_follow", 0.0))
	# L'opinion suit l'écart des relations de la paire (dans les deux sens).
	var opinion_keys: Dictionary = {}
	for key: String in diplomacy.opinion_changes.keys():
		opinion_keys[key] = true
	for key: String in diplomacy.relation_changes.keys():
		var parts := key.split("|")
		opinion_keys[DiplomacyState.opinion_key(parts[0], parts[1])] = true
		opinion_keys[DiplomacyState.opinion_key(parts[1], parts[0])] = true
	for key: String in opinion_keys.keys():
		var parts := key.split(">")
		var target := float(diplomacy.relation_changes.get(DiplomacyState.pair_key(parts[0], parts[1]), 0.0))
		var current := float(diplomacy.opinion_changes.get(key, 0.0))
		_store(diplomacy.opinion_changes, key, current + (target - current) * follow)
	_decay(diplomacy.relation_changes, relation_return)
	_decay(diplomacy.trust_changes, float(settings.get("trust_return", 0.0)))


static func _decay(changes: Dictionary, rate: float) -> void:
	for key: Variant in changes.keys():
		_store(changes, key, float(changes[key]) * (1.0 - rate))


static func _store(changes: Dictionary, key: Variant, value: float) -> void:
	if absf(value) < CLEANUP:
		changes.erase(key)
	else:
		changes[key] = value

class_name MobilizeCommand
extends Command
## Niveau de mobilisation : 0 (aucune), 1 (partielle), 2 (générale). Délai avant un nouveau changement.

const MAX_LEVEL := 2
const EVENT_MOBILIZATION := &"mobilization_changed"

var level: int = 0


func _init(p_issuer: StringName = &"", p_level: int = 0) -> void:
	issuer = p_issuer
	level = p_level


func get_type() -> StringName:
	return &"mobilize"


## Raison du refus (clé de localisation), vide si la commande est possible.
func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	if country == null or country.military == null or country.military.branches.is_empty() \
			or level < 0 or level > MAX_LEVEL:
		return "MILITARY_INVALID"
	if country.military.mobilization == level:
		return "MILITARY_ALREADY"
	if country.military.mobilization_cooldown > 0:
		return "MILITARY_COOLDOWN"
	return ""


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	var military := country.military
	military.mobilization = level
	military.mobilization_cooldown = int((state.military_settings.get("mobilization", {}) as Dictionary).get(
		"cooldown", 0))
	military.effects = MilitaryModel.mobilization_effects(military, state.military_settings.get("mobilization", {}))
	country.economy.military_growth = float(military.effects.get("growth", 0.0))
	state.add_event(EVENT_MOBILIZATION, str(issuer), {"level": level})


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["level"] = level
	return data

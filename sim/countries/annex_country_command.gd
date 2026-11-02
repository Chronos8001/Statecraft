class_name AnnexCountryCommand
extends Command
## Absorbe pacifiquement un pays (union). Pour l'instant réservée aux tests et au mode développement ; les arbres
## de décisions passent par l'effet « annex_country ».

var target: String = ""


func _init(p_issuer: StringName = &"", p_target: String = "") -> void:
	issuer = p_issuer
	target = p_target


func get_type() -> StringName:
	return &"annex_country"


func refusal_reason(state: SimState) -> String:
	return CountryLifecycle.annex_refusal(state, str(issuer), target)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	CountryLifecycle.annex(state, str(issuer), target)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	return data

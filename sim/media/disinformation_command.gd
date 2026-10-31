class_name DisinformationCommand
extends Command
## Opération de désinformation : déstabiliser un pays étranger ou salir l'opposition du pays.

var target: String = ""
var kind: String = MediaSystem.KIND_DESTABILIZE


func _init(p_issuer: StringName = &"", p_target: String = "", p_kind: String = MediaSystem.KIND_DESTABILIZE) -> void:
	issuer = p_issuer
	target = p_target
	kind = p_kind


func get_type() -> StringName:
	return &"disinformation"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	if country == null or not [MediaSystem.KIND_DESTABILIZE, MediaSystem.KIND_SMEAR].has(kind):
		return "LAWS_INVALID"
	if country.disinformation_cooldown > 0:
		return "MEDIA_COOLDOWN"
	if kind == MediaSystem.KIND_DESTABILIZE and (state.get_country(target) == null or target == country.tag):
		return "MEDIA_INVALID_TARGET"
	if kind == MediaSystem.KIND_SMEAR and country.politics.parties.size() < 2:
		return "MEDIA_NO_OPPOSITION"
	return ""


func execute(state: SimState) -> void:
	MediaSystem.disinformation(state.get_country(str(issuer)), state, target, kind)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["kind"] = kind
	return data

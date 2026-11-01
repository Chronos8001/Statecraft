class_name ChooseEventOptionCommand
extends Command
## Réponse du joueur à un événement en attente : l'option choisie s'applique à son pays.

var event_id: String = ""
var option: int = 0


func _init(p_issuer: StringName = &"", p_event_id: String = "", p_option: int = 0) -> void:
	issuer = p_issuer
	event_id = p_event_id
	option = p_option


func get_type() -> StringName:
	return &"choose_event_option"


func refusal_reason(state: SimState) -> String:
	return EventSystem.choice_refusal(state, str(issuer), event_id, option)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	EventSystem.answer(state, str(issuer), event_id, option)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["event"] = event_id
	data["option"] = option
	return data

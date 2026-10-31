class_name CrisisResponseCommand
extends Command
## Réponse du joueur à une grève, une manifestation ou une émeute : concéder, négocier ou réprimer.

const RESPONSES := ["concede", "negotiate", "repress"]

var crisis_id: int = 0
var response: String = ""


func _init(p_issuer: StringName = &"", p_crisis_id: int = 0, p_response: String = "") -> void:
	issuer = p_issuer
	crisis_id = p_crisis_id
	response = p_response


func get_type() -> StringName:
	return &"crisis_response"


func can_execute(state: SimState) -> bool:
	var country := state.get_country(str(issuer))
	if country == null or not RESPONSES.has(response):
		return false
	var definitions: Dictionary = state.politics_definitions.get("crises", {})
	for crisis: Dictionary in country.crises:
		if int(crisis["id"]) == crisis_id:
			return bool((definitions.get(crisis["type"], {}) as Dictionary).get("responses", false)) \
				and not crisis.has("response")
	return false


func execute(state: SimState) -> void:
	CrisisSystem.respond(state.get_country(str(issuer)), state, crisis_id, response)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["crisis"] = crisis_id
	data["response"] = response
	return data

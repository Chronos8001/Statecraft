class_name SetResearchCommand
extends Command
## Met une technologie dans un emplacement de recherche (vide : libère l'emplacement ; l'avancement est gardé).

var slot: int = 0
var technology: String = ""


func _init(p_issuer: StringName = &"", p_slot: int = 0, p_technology: String = "") -> void:
	issuer = p_issuer
	slot = p_slot
	technology = p_technology


func get_type() -> StringName:
	return &"set_research"


func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	if country == null or country.research == null or slot < 0 or slot >= country.research.slots.size():
		return "RESEARCH_INVALID"
	if technology.is_empty():
		return ""
	if country.research.is_researching(technology):
		return "RESEARCH_ALREADY"
	return ResearchSystem.availability(state, country, technology)


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	ResearchSystem.set_slot(state, state.get_country(str(issuer)), slot, technology)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["slot"] = slot
	data["technology"] = technology
	return data

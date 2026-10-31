class_name ChangeLawCommand
extends Command
## Proposer une nouvelle option pour une loi. En démocratie, la chambre basse vote (majorité des sièges) ;
## ailleurs, le pouvoir décide seul. Adoptée ou rejetée, la loi ne peut être remise en jeu avant un délai.

const EVENT_LAW_PASSED := &"law_passed"
const EVENT_LAW_REJECTED := &"law_rejected"

var law_id: String = ""
var option_id: String = ""


func _init(p_issuer: StringName = &"", p_law_id: String = "", p_option_id: String = "") -> void:
	issuer = p_issuer
	law_id = p_law_id
	option_id = p_option_id


func get_type() -> StringName:
	return &"change_law"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


## Clé de localisation expliquant le refus, ou "" si la proposition est possible.
func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	var definition: Dictionary = (state.politics_definitions.get("laws", {}) as Dictionary).get(law_id, {})
	if country == null or definition.is_empty() or LawModel.option_of(definition, option_id).is_empty():
		return "LAWS_INVALID"
	if str(country.laws.get(law_id, "")) == option_id:
		return "LAWS_ALREADY"
	if int(country.law_cooldowns.get(law_id, 0)) > 0:
		return "LAWS_COOLDOWN"
	return ""


## Résultat attendu du vote (null hors démocratie, où le pouvoir décide seul).
static func expected_vote(state: SimState, country: CountryState, law: String, option: String) -> Variant:
	var politics := country.politics
	if not politics.democratic or politics.parties.is_empty() or politics.seats <= 0:
		return null
	var definition: Dictionary = (state.politics_definitions.get("laws", {}) as Dictionary).get(law, {})
	return LawModel.vote(politics, definition, str(country.laws.get(law, "")), option, LawSystem.settings_of(state))


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	var settings := LawSystem.settings_of(state)
	var result: Variant = expected_vote(state, country, law_id, option_id)
	var passed := result == null or bool((result as Dictionary)["passed"])
	if passed:
		country.laws[law_id] = option_id
		LawSystem.apply_effects(country, state)
		country.law_cooldowns[law_id] = int(settings.get("cooldown_months", 0))
	else:
		country.law_cooldowns[law_id] = int(settings.get("rejected_cooldown_months", 0))
	var details := {"law": law_id, "option": option_id}
	if result != null:
		details["yes"] = (result as Dictionary)["yes"]
		details["no"] = (result as Dictionary)["no"]
	state.add_event(EVENT_LAW_PASSED if passed else EVENT_LAW_REJECTED, country.tag, details)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["law"] = law_id
	data["option"] = option_id
	return data

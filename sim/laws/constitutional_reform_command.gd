class_name ConstitutionalReformCommand
extends Command
## Réforme constitutionnelle : vote des 2/3 de la chambre basse ou référendum (deux mois plus tard) en
## démocratie, décret ailleurs.

const METHOD_PARLIAMENT := "parliament"
const METHOD_REFERENDUM := "referendum"
const COOLDOWN_PREFIX := "constitution:"

var reform_id: String = ""
var option_id: String = ""
var method: String = METHOD_PARLIAMENT


func _init(p_issuer: StringName = &"", p_reform_id: String = "", p_option_id: String = "",
		p_method: String = METHOD_PARLIAMENT) -> void:
	issuer = p_issuer
	reform_id = p_reform_id
	option_id = p_option_id
	method = p_method


func get_type() -> StringName:
	return &"constitutional_reform"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


## Clé de localisation expliquant le refus, ou "" si la réforme peut être engagée.
func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	var definition := ConstitutionSystem.definition_of(state, reform_id)
	if country == null or definition.is_empty() or LawModel.option_of(definition, option_id).is_empty() \
			or not [METHOD_PARLIAMENT, METHOD_REFERENDUM].has(method):
		return "LAWS_INVALID"
	var politics := country.politics
	if bool(definition.get("presidential_only", false)) and not politics.has_presidency:
		return "CONSTITUTION_NO_PRESIDENCY"
	if reform_id == "executive" and not ConstitutionModel.REPUBLICS.has(politics.regime):
		return "CONSTITUTION_NOT_REPUBLIC"
	if str(country.constitution.get(reform_id, "")) == option_id:
		return "LAWS_ALREADY"
	if int(country.law_cooldowns.get(COOLDOWN_PREFIX + reform_id, 0)) > 0:
		return "LAWS_COOLDOWN"
	if not politics.pending_referendum.is_empty():
		return "CONSTITUTION_REFERENDUM_PENDING"
	if method == METHOD_REFERENDUM and not politics.democratic:
		return "CONSTITUTION_NO_REFERENDUM"
	return ""


## Vote attendu de la chambre (null hors démocratie).
static func expected_vote(state: SimState, country: CountryState, reform: String, option: String) -> Variant:
	var politics := country.politics
	if not politics.democratic or politics.parties.is_empty() or politics.seats <= 0:
		return null
	return LawModel.vote(politics, ConstitutionSystem.definition_of(state, reform), str(country.constitution.get(reform, "")),
		option, LawSystem.settings_of(state), float(ConstitutionSystem.settings_of(state).get("required_share", 0.5)))


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	var settings := ConstitutionSystem.settings_of(state)
	country.law_cooldowns[COOLDOWN_PREFIX + reform_id] = int(settings.get("cooldown_months", 0))
	if method == METHOD_REFERENDUM:
		var date := ElectionSystem._add_months(state.date.year, state.date.month,
			int(settings.get("referendum_delay_months", 1)))
		country.politics.pending_referendum = {"reform": reform_id, "option": option_id, "year": date[0], "month": date[1]}
		state.add_event(ConstitutionSystem.EVENT_REFERENDUM_CALLED, country.tag, {"reform": reform_id})
		return
	var result: Variant = expected_vote(state, country, reform_id, option_id)
	if result == null or bool((result as Dictionary)["passed"]):
		ConstitutionSystem.apply_reform(country, state, reform_id, option_id)
	else:
		state.add_event(ConstitutionSystem.EVENT_REFORM_REJECTED, country.tag, {"reform": reform_id,
			"yes": (result as Dictionary)["yes"], "no": (result as Dictionary)["no"]})


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["reform"] = reform_id
	data["option"] = option_id
	data["method"] = method
	return data

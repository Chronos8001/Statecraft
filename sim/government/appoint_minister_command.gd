class_name AppointMinisterCommand
extends Command
## Nommer l'un des candidats proposés à un portefeuille. Chaque remaniement coûte un peu de stabilité.

var portfolio_id: String = ""
var candidate_index: int = 0


func _init(p_issuer: StringName = &"", p_portfolio_id: String = "", p_candidate_index: int = 0) -> void:
	issuer = p_issuer
	portfolio_id = p_portfolio_id
	candidate_index = p_candidate_index


func get_type() -> StringName:
	return &"appoint_minister"


func can_execute(state: SimState) -> bool:
	var country := state.get_country(str(issuer))
	if country == null or not (state.politics_definitions.get("portfolios", {}) as Dictionary).has(portfolio_id):
		return false
	return candidate_index >= 0 and candidate_index < GovernmentSystem.candidates(country, state, portfolio_id).size()


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	var minister: Dictionary = GovernmentSystem.candidates(country, state, portfolio_id)[candidate_index]
	GovernmentSystem.appoint(country, state, portfolio_id, minister)
	country.society.stability = maxf(country.society.stability
		- float(GovernmentModel.settings_of(state).get("reshuffle_stability", 0.0)), 0.0)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["portfolio"] = portfolio_id
	data["candidate"] = candidate_index
	return data

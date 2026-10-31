class_name PromiseCommand
extends CampaignCommand
## Promesse de campagne à un groupe social : satisfaction immédiate ; après le scrutin, le budget doit
## apporter assez à ce groupe avant l'échéance, sinon la promesse est rompue.

var group_id: String = ""


func _init(p_issuer: StringName = &"", p_group_id: String = "") -> void:
	issuer = p_issuer
	group_id = p_group_id


func get_type() -> StringName:
	return &"campaign_promise"


func _specific_refusal(country: CountryState, state: SimState) -> String:
	if not country.society.satisfaction.has(group_id):
		return "CAMPAIGN_UNKNOWN_GROUP"
	if country.politics.has_promise(group_id):
		return "CAMPAIGN_ALREADY_PROMISED"
	if country.politics.promises.size() >= int(ElectionSystem.campaign_settings(state).get("max_promises", 0)):
		return "CAMPAIGN_TOO_MANY_PROMISES"
	return ""


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	var settings := ElectionSystem.campaign_settings(state)
	var election := CampaignModel.campaign_election(country.politics, state.date.year, state.date.month, settings)
	var deadline := ElectionSystem._add_months(int(election[0]), int(election[1]), int(settings.get("promise_months", 0)))
	var gain := float(settings.get("promise_gain", 0.0))
	country.politics.promises.append({"group": group_id, "party": country.politics.ruling_party(),
		"deadline_year": deadline[0], "deadline_month": deadline[1], "gain": gain, "pending": true})
	country.society.bonuses[group_id] = float(country.society.bonuses.get(group_id, 0.0)) + gain


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["group"] = group_id
	return data

class_name CampaignCommand
extends Command
## Base des actions de campagne : possibles seulement pour le parti au pouvoir, dans les mois qui précèdent
## un scrutin. Les sous-classes donnent leur propre raison de refus.


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


## Clé de localisation expliquant le refus, ou "" si l'action est possible.
func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	if country == null or country.politics.parties.is_empty() or country.politics.ruling_party().is_empty():
		return "CAMPAIGN_NO_PARTY"
	if CampaignModel.campaign_election(country.politics, state.date.year, state.date.month,
			ElectionSystem.campaign_settings(state)).is_empty():
		return "CAMPAIGN_NOT_STARTED"
	return _specific_refusal(country, state)


func _specific_refusal(_country: CountryState, _state: SimState) -> String:
	return ""

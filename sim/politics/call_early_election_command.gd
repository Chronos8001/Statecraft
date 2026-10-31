class_name CallEarlyElectionCommand
extends Command
## Dissolution de la chambre : législatives anticipées quelques mois plus tard. Possible en démocratie
## parlementaire, pas trop tôt après le dernier scrutin, et si aucune élection n'est déjà prévue sous peu.


func _init(p_issuer: StringName = &"") -> void:
	issuer = p_issuer


func get_type() -> StringName:
	return &"call_early_election"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


## Clé de localisation expliquant le refus, ou "" si la dissolution est possible.
func refusal_reason(state: SimState) -> String:
	var country := state.get_country(str(issuer))
	if country == null or country.politics.seats <= 0:
		return "POLITICS_EARLY_NO_CHAMBER"
	var politics := country.politics
	var settings := ElectionSystem.settings_of(state)
	if not politics.democratic or politics.executive != PoliticsState.EXECUTIVE_PARLIAMENTARY or politics.suspended:
		return "POLITICS_EARLY_NOT_ALLOWED"
	if politics.months_since_election(state.date.year, state.date.month) \
			< int(settings.get("min_months_between_elections", 0)):
		return "POLITICS_EARLY_TOO_SOON"
	var delay := int(settings.get("early_election_delay_months", 1))
	var planned := ElectionSystem._add_months(state.date.year, state.date.month, delay)
	if not PoliticsState.is_due(politics.next_election_year, politics.next_election_month, planned[0], planned[1]):
		return "POLITICS_EARLY_ALREADY_PLANNED"
	return ""


func execute(state: SimState) -> void:
	var politics := state.get_country(str(issuer)).politics
	var planned := ElectionSystem._add_months(state.date.year, state.date.month,
		int(ElectionSystem.settings_of(state).get("early_election_delay_months", 1)))
	politics.next_election_year = planned[0]
	politics.next_election_month = planned[1]
	politics.dissolved = true

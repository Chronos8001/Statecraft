class_name RequestImfCommand
extends Command
## Demande d'aide au FMI : prêt à taux réduit contre un effort budgétaire, possible pour un pays
## mal noté ou en crise, sans programme en cours ni récent.


func _init(p_issuer: StringName = &"") -> void:
	issuer = p_issuer


func get_type() -> StringName:
	return &"request_imf"


func can_execute(state: SimState) -> bool:
	var country := state.get_country(str(issuer))
	if country == null or state.economy_settings.is_empty():
		return false
	return EconomySystem.can_request_imf(country.economy, CreditRating.new(state.economy_settings),
		state.economy_settings)


func execute(state: SimState) -> void:
	EconomySystem.start_imf_program(state.get_country(str(issuer)), state)

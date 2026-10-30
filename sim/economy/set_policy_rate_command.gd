class_name SetPolicyRateCommand
extends Command
## Le gouvernement fixe le taux directeur, quand la banque centrale dépend de lui
## (ni indépendante, ni ancrée à une autre monnaie, ni partagée avec d'autres pays).

var rate: float = 0.0


func _init(p_issuer: StringName = &"", p_rate: float = 0.0) -> void:
	issuer = p_issuer
	rate = p_rate


func get_type() -> StringName:
	return &"set_policy_rate"


func can_execute(state: SimState) -> bool:
	var currency := currency_of(state)
	return currency != null and not currency.independent and not currency.is_pegged() \
		and currency.issuer == str(issuer)


func execute(state: SimState) -> void:
	var settings := state.economy_settings
	currency_of(state).policy_rate = clampf(rate, float(settings.get("min_policy_rate", 0.0)),
		float(settings.get("max_policy_rate", rate)))


func currency_of(state: SimState) -> CurrencyState:
	var country := state.get_country(str(issuer))
	return state.get_currency(country.economy.currency) if country != null else null


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["rate"] = rate
	return data

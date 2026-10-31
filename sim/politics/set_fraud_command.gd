class_name SetFraudCommand
extends CampaignCommand
## Fraude prévue au prochain scrutin (0 à 3). Dans les régimes non démocratiques, les scrutins sont déjà joués.

const MAX_LEVEL := 3

var level: int = 0


func _init(p_issuer: StringName = &"", p_level: int = 0) -> void:
	issuer = p_issuer
	level = p_level


func get_type() -> StringName:
	return &"set_fraud"


func _specific_refusal(country: CountryState, _state: SimState) -> String:
	if not country.politics.democratic:
		return "CAMPAIGN_FRAUD_USELESS"
	if level < 0 or level > MAX_LEVEL or level == country.politics.fraud_level:
		return "CAMPAIGN_INVALID_AMOUNT"
	return ""


func execute(state: SimState) -> void:
	state.get_country(str(issuer)).politics.fraud_level = level


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["level"] = level
	return data

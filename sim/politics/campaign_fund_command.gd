class_name CampaignFundCommand
extends CampaignCommand
## Financement de la campagne par l'État (milliards de dollars, ajoutés à la dette), plafonné en % du PIB.

var amount: float = 0.0


func _init(p_issuer: StringName = &"", p_amount: float = 0.0) -> void:
	issuer = p_issuer
	amount = p_amount


func get_type() -> StringName:
	return &"campaign_fund"


func _specific_refusal(country: CountryState, state: SimState) -> String:
	if amount <= 0.0:
		return "CAMPAIGN_INVALID_AMOUNT"
	var limit := float(ElectionSystem.campaign_settings(state).get("max_spending_share", 0.0)) / CampaignModel.PERCENT \
		* TradeSystem.current_gdp(state, country.tag)
	if country.politics.campaign_spent + amount > limit + 0.0001:
		return "CAMPAIGN_SPENDING_LIMIT"
	return ""


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	country.politics.campaign_spent += amount
	InvestmentSystem.add_debt_usd(country, state, amount)
	country.politics.campaign_bonus = CampaignModel.campaign_bonus(country.politics,
		TradeSystem.current_gdp(state, country.tag), ElectionSystem.campaign_settings(state))


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["amount"] = amount
	return data

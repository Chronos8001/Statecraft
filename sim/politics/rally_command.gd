class_name RallyCommand
extends CampaignCommand
## Meeting dans une province du pays : un par mois, une fois par province et par campagne.

var province_id: String = ""


func _init(p_issuer: StringName = &"", p_province_id: String = "") -> void:
	issuer = p_issuer
	province_id = p_province_id


func get_type() -> StringName:
	return &"campaign_rally"


func _specific_refusal(country: CountryState, state: SimState) -> String:
	var provinces: Array = (state.politics_definitions.get("provinces", {}) as Dictionary).get(country.tag, [])
	if not provinces.any(func(entry: Array) -> bool: return str(entry[0]) == province_id):
		return "CAMPAIGN_NOT_OWN_PROVINCE"
	if country.politics.rallies.has(province_id):
		return "CAMPAIGN_RALLY_DONE"
	if country.politics.last_rally == state.date.year * CampaignModel.MONTHS_PER_YEAR + state.date.month:
		return "CAMPAIGN_RALLY_THIS_MONTH"
	return ""


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	var settings := ElectionSystem.campaign_settings(state)
	country.politics.rallies[province_id] = true
	country.politics.last_rally = state.date.year * CampaignModel.MONTHS_PER_YEAR + state.date.month
	var gdp := TradeSystem.current_gdp(state, country.tag)
	InvestmentSystem.add_debt_usd(country, state, float(settings.get("rally_cost_share", 0.0)) / CampaignModel.PERCENT * gdp)
	country.politics.campaign_bonus = CampaignModel.campaign_bonus(country.politics, gdp, settings)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["province"] = province_id
	return data

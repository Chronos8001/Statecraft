class_name SetOwnershipCommand
extends Command
## Change la part publique d'un secteur. Hausse = nationalisation : avec indemnisation, l'État rachète
## (la dette augmente) ; sans, c'est une expropriation (note dégradée, investisseurs étrangers en fuite).
## Baisse = privatisation : la vente réduit la dette.

var sector: String = ""
var share: float = 0.0
var compensated: bool = true


func _init(p_issuer: StringName = &"", p_sector: String = "", p_share: float = 0.0, p_compensated: bool = true) -> void:
	issuer = p_issuer
	sector = p_sector
	share = p_share
	compensated = p_compensated


func get_type() -> StringName:
	return &"set_ownership"


func can_execute(state: SimState) -> bool:
	var country := state.get_country(str(issuer))
	if country == null or state.investment_settings.is_empty() or share < 0.0 or share > 1.0:
		return false
	var ownership := country.economy.investment.public_ownership
	return ownership.has(sector) and not is_equal_approx(float(ownership[sector]), share)


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	var settings := state.investment_settings
	var investment := country.economy.investment
	var change := share - float(investment.public_ownership[sector])
	var value := InvestmentSystem.ownership_value(country, state, sector, change)
	investment.public_ownership[sector] = share
	if change < 0.0:
		InvestmentSystem.add_debt_usd(country, state, -value * float(settings.get("privatization_discount", 1.0)))
		state.add_event(InvestmentSystem.EVENT_PRIVATIZED, country.tag, {"sector": sector, "value": value})
	elif compensated:
		InvestmentSystem.add_debt_usd(country, state, value)
		state.add_event(InvestmentSystem.EVENT_NATIONALIZED, country.tag, {"sector": sector, "value": value})
	else:
		var expropriation: Dictionary = settings.get("expropriation", {})
		country.economy.rating = maxi(country.economy.rating - int(expropriation.get("rating_notches", 0)), 0)
		investment.expropriation_months = int(expropriation.get("penalty_months", 0))
		state.add_event(InvestmentSystem.EVENT_EXPROPRIATED, country.tag, {"sector": sector, "value": value})
	InvestmentSystem.update_country(country, state)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["sector"] = sector
	data["share"] = share
	data["compensated"] = compensated
	return data

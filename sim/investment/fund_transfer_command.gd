class_name FundTransferCommand
extends Command
## Mouvement du fonds souverain (milliards de dollars) : un versement est emprunté (la dette augmente),
## un retrait rembourse la dette.

var amount: float = 0.0


func _init(p_issuer: StringName = &"", p_amount: float = 0.0) -> void:
	issuer = p_issuer
	amount = p_amount


func get_type() -> StringName:
	return &"fund_transfer"


func can_execute(state: SimState) -> bool:
	var country := state.get_country(str(issuer))
	if country == null or is_zero_approx(amount):
		return false
	return amount > 0.0 or -amount <= country.economy.investment.sovereign_fund + 0.0001


func execute(state: SimState) -> void:
	var country := state.get_country(str(issuer))
	country.economy.investment.sovereign_fund = maxf(country.economy.investment.sovereign_fund + amount, 0.0)
	InvestmentSystem.add_debt_usd(country, state, amount)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["amount"] = amount
	return data

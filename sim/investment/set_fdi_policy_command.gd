class_name SetFdiPolicyCommand
extends Command
## Politique d'ouverture aux investissements étrangers : ouverte, contrôlée ou restreinte.

var policy: String = InvestmentState.OPEN


func _init(p_issuer: StringName = &"", p_policy: String = InvestmentState.OPEN) -> void:
	issuer = p_issuer
	policy = p_policy


func get_type() -> StringName:
	return &"set_fdi_policy"


func can_execute(state: SimState) -> bool:
	var country := state.get_country(str(issuer))
	return country != null and InvestmentState.POLICIES.has(policy) and country.economy.investment.fdi_policy != policy


func execute(state: SimState) -> void:
	state.get_country(str(issuer)).economy.investment.fdi_policy = policy


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["policy"] = policy
	return data

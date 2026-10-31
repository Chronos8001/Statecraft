class_name LeaveAgreementCommand
extends Command
## Quitte un accord commercial : les échanges avec les anciens partenaires repassent aux droits habituels.
## Rejoindre ou signer un accord demande l'accord des autres pays (diplomatie, étape 6).

var agreement_id: String = ""


func _init(p_issuer: StringName = &"", p_agreement_id: String = "") -> void:
	issuer = p_issuer
	agreement_id = p_agreement_id


func get_type() -> StringName:
	return &"leave_agreement"


func can_execute(state: SimState) -> bool:
	var agreement: Dictionary = state.trade.agreements.get(agreement_id, {})
	return not agreement.is_empty() and (agreement["members"] as Array).has(str(issuer))


func execute(state: SimState) -> void:
	var agreement: Dictionary = state.trade.agreements[agreement_id]
	var members: Array = (agreement["members"] as Array).duplicate()
	members.erase(str(issuer))
	if members.size() < 2:
		state.trade.agreements.erase(agreement_id)
	else:
		agreement["members"] = members
	state.trade.refresh_pair_kinds(TradeModel.KIND_ORDER)
	state.add_event(TradeSystem.EVENT_AGREEMENT_LEFT, str(issuer), {"agreement": agreement_id})
	state.trade.dirty = true
	TradeSystem.update_trade(state)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["agreement"] = agreement_id
	return data

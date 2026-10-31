class_name SetTariffCommand
extends Command
## Fixe la surtaxe douanière appliquée aux produits d'un pays (0 = la retirer).

var target: String = ""
var surcharge: float = 0.0


func _init(p_issuer: StringName = &"", p_target: String = "", p_surcharge: float = 0.0) -> void:
	issuer = p_issuer
	target = p_target
	surcharge = p_surcharge


func get_type() -> StringName:
	return &"set_tariff"


func can_execute(state: SimState) -> bool:
	return TradeCommands.valid_partner(state, str(issuer), target) and surcharge >= 0.0


func execute(state: SimState) -> void:
	var table: Dictionary = state.trade.surcharges.get(str(issuer), {})
	var limit := float(state.trade_settings.get("embargo_tariff", surcharge))
	table[target] = clampf(surcharge, 0.0, limit)
	state.trade.surcharges[str(issuer)] = table
	state.trade.dirty = true
	TradeSystem.update_trade(state)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["surcharge"] = surcharge
	return data

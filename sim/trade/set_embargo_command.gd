class_name SetEmbargoCommand
extends Command
## Décrète ou lève un embargo contre un pays : sur tout le commerce (TradeState.ALL_GOODS) ou sur une
## ressource. Un embargo total remplace les embargos par ressource.

var target: String = ""
var goods: String = TradeState.ALL_GOODS
var active: bool = true


func _init(p_issuer: StringName = &"", p_target: String = "", p_goods: String = TradeState.ALL_GOODS,
		p_active: bool = true) -> void:
	issuer = p_issuer
	target = p_target
	goods = p_goods
	active = p_active


func get_type() -> StringName:
	return &"set_embargo"


func can_execute(state: SimState) -> bool:
	if not TradeCommands.valid_partner(state, str(issuer), target):
		return false
	if goods != TradeState.ALL_GOODS and not state.markets.has(goods):
		return false
	if active:
		return not state.trade.is_embargoed(str(issuer), target, goods)
	var current := state.trade.embargo_goods(str(issuer), target)
	return not current.is_empty() if goods == TradeState.ALL_GOODS else current.has(goods)


func execute(state: SimState) -> void:
	var table: Dictionary = state.trade.embargoes.get(str(issuer), {})
	var current: Array = (table.get(target, []) as Array).duplicate()
	if goods == TradeState.ALL_GOODS:
		current = [TradeState.ALL_GOODS] if active else []
	elif active:
		current.append(goods)
	else:
		current.erase(goods)
	if current.is_empty():
		table.erase(target)
	else:
		table[target] = current
	if table.is_empty():
		state.trade.embargoes.erase(str(issuer))
	else:
		state.trade.embargoes[str(issuer)] = table
	state.trade.dirty = true
	TradeSystem.update_trade(state)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["goods"] = goods
	data["active"] = active
	return data

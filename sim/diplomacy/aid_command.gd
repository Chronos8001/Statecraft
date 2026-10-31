class_name AidCommand
extends Command
## Proposer une aide à un pays : montant (milliards de dollars par an, ou en une fois) et durée en mois.
## Un pays de l'IA refuse si ses relations avec nous sont trop mauvaises pour ce type d'aide.

var target: String = ""
var kind: String = ""
var amount: float = 0.0
var months: int = 1


func _init(p_issuer: StringName = &"", p_target: String = "", p_kind: String = "", p_amount: float = 0.0,
		p_months: int = 1) -> void:
	issuer = p_issuer
	target = p_target
	kind = p_kind
	amount = p_amount
	months = p_months


func get_type() -> StringName:
	return &"aid"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func refusal_reason(state: SimState) -> String:
	var tag := str(issuer)
	if state.get_country(tag) == null or state.get_country(target) == null or tag == target \
			or not state.aid_definitions.has(kind):
		return "DIPLOMACY_INVALID"
	if amount <= 0.0 or not (AidSystem.settings_of(state).get("durations", []) as Array).has(months):
		return "AID_INVALID_AMOUNT"
	return ""


func execute(state: SimState) -> void:
	var tag := str(issuer)
	if AidSystem.accepts(state, tag, target, kind):
		AidSystem.start_program(state, tag, target, kind, amount, months)
		state.add_event(AidSystem.EVENT_AID, tag, {"target": target, "kind": kind, "amount": amount})
	else:
		state.diplomacy.change_relation(tag, target, float(AidSystem.settings_of(state).get("refused_relation", 0.0)))
		state.add_event(AidSystem.EVENT_AID_REFUSED, tag, {"target": target, "kind": kind})


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["kind"] = kind
	data["amount"] = amount
	data["months"] = months
	return data

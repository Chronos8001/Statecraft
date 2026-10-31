class_name ClaimCommand
extends Command
## Revendications territoriales : faire valoir ou abandonner une revendication, revendiquer une province
## voisine (selon la tension mondiale).

const PRESS := "press"
const RENOUNCE := "renounce"
const ADD := "add"

var action: String = ""
var claim_id: int = -1
var target: String = ""
var province_id: String = ""


func _init(p_issuer: StringName = &"", p_action: String = "", p_claim_id: int = -1, p_target: String = "",
		p_province_id: String = "") -> void:
	issuer = p_issuer
	action = p_action
	claim_id = p_claim_id
	target = p_target
	province_id = p_province_id


func get_type() -> StringName:
	return &"claim"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func refusal_reason(state: SimState) -> String:
	var tag := str(issuer)
	if state.get_country(tag) == null:
		return "DIPLOMACY_INVALID"
	match action:
		PRESS, RENOUNCE:
			var claim: Dictionary = state.diplomacy.claims.get(claim_id, {})
			if claim.is_empty() or str(claim["claimant"]) != tag:
				return "DIPLOMACY_INVALID"
			if action == PRESS and state.diplomacy.cooldown("claim_%d" % claim_id, tag, str(claim["target"])) > 0:
				return "DIPLOMACY_COOLDOWN"
		ADD:
			if state.get_country(target) == null or target == tag:
				return "DIPLOMACY_INVALID"
			if not TensionSystem.unlocked(state, "add_claim"):
				return "TENSION_TOO_LOW"
			var provinces: Dictionary = state.energy_definitions.get("provinces", {})
			if not TensionSystem.adjacent_provinces(state, tag, target, provinces).has(province_id):
				return "CLAIM_NOT_ADJACENT"
			if TensionSystem.is_claimed_by(state, tag, province_id):
				return "DIPLOMACY_ALREADY"
		_:
			return "DIPLOMACY_INVALID"
	return ""


func execute(state: SimState) -> void:
	match action:
		PRESS:
			TensionSystem.press_claim(state, claim_id)
		RENOUNCE:
			TensionSystem.renounce_claim(state, claim_id)
		ADD:
			TensionSystem.new_claim(state, str(issuer), target, province_id)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["action"] = action
	data["claim"] = claim_id
	data["target"] = target
	data["province"] = province_id
	return data

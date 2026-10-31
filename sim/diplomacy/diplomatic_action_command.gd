class_name DiplomaticActionCommand
extends Command
## Action diplomatique envers un pays : améliorer les relations, visite d'État, ouvrir ou fermer une
## ambassade, reconnaître un État contesté ou retirer sa reconnaissance, garantir son indépendance ou
## retirer cette garantie, ultimatum (tribut).

const ACTIONS := ["improve_relations", "state_visit", "open_embassy", "close_embassy", "recognize",
	"withdraw_recognition", "guarantee", "revoke_guarantee", "ultimatum"]
## Actions qui demandent une ambassade.
const NEED_EMBASSY := ["improve_relations", "state_visit"]

var target: String = ""
var action: String = ""


func _init(p_issuer: StringName = &"", p_target: String = "", p_action: String = "") -> void:
	issuer = p_issuer
	target = p_target
	action = p_action


func get_type() -> StringName:
	return &"diplomatic_action"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


## Clé de localisation expliquant le refus, ou "" si l'action est possible.
func refusal_reason(state: SimState) -> String:
	var tag := str(issuer)
	var diplomacy := state.diplomacy
	if state.get_country(tag) == null or state.get_country(target) == null or tag == target or not ACTIONS.has(action):
		return "DIPLOMACY_INVALID"
	if diplomacy.cooldown(action, tag, target) > 0:
		return "DIPLOMACY_COOLDOWN"
	if NEED_EMBASSY.has(action) and not diplomacy.has_embassy(tag, target):
		return "DIPLOMACY_NO_EMBASSY"
	var recognition := DiplomacySystem.recognition_of(state, target)
	match action:
		"open_embassy":
			if diplomacy.has_embassy(tag, target):
				return "DIPLOMACY_ALREADY"
			if not recognition.is_empty() and not diplomacy.recognizes(tag, target):
				return "DIPLOMACY_NOT_RECOGNIZED"
		"close_embassy":
			if not diplomacy.has_embassy(tag, target):
				return "DIPLOMACY_ALREADY"
		"recognize", "withdraw_recognition":
			if recognition.is_empty() or str(recognition.get("parent", "")) == tag:
				return "DIPLOMACY_NOT_DISPUTED"
			if diplomacy.recognizes(tag, target) == (action == "recognize"):
				return "DIPLOMACY_ALREADY"
		"ultimatum":
			if not TensionSystem.unlocked(state, "ultimatum"):
				return "TENSION_TOO_LOW"
		"guarantee", "revoke_guarantee":
			if diplomacy.guarantees_independence(tag, target) == (action == "guarantee"):
				return "DIPLOMACY_ALREADY"
	return ""


func execute(state: SimState) -> void:
	DiplomacySystem.perform(state, str(issuer), target, action)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["action"] = action
	return data

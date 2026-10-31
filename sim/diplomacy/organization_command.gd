class_name OrganizationCommand
extends Command
## Actions dans les organisations internationales : adhérer, partir, faire exclure un membre, inviter
## (organisations créées en jeu), créer une organisation, proposer une résolution de condamnation à l'ONU.

const JOIN := "join"
const LEAVE := "leave"
const EXPEL := "expel"
const INVITE := "invite"
const CREATE := "create"
const RESOLUTION := "resolution"
const ACTIONS := [JOIN, LEAVE, EXPEL, INVITE, CREATE, RESOLUTION]

var action: String = ""
var organization: String = ""
var target: String = ""
## Nom de la nouvelle organisation, ou assemblée de la résolution (general_assembly / security_council).
var text: String = ""
var kind: String = ""


func _init(p_issuer: StringName = &"", p_action: String = "", p_organization: String = "", p_target: String = "",
		p_text: String = "", p_kind: String = "") -> void:
	issuer = p_issuer
	action = p_action
	organization = p_organization
	target = p_target
	text = p_text
	kind = p_kind


func get_type() -> StringName:
	return &"organization"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


## Clé de localisation expliquant le refus, ou "" si l'action est possible.
func refusal_reason(state: SimState) -> String:
	var tag := str(issuer)
	var diplomacy := state.diplomacy
	if state.get_country(tag) == null or not ACTIONS.has(action):
		return "DIPLOMACY_INVALID"
	if action == CREATE:
		var kinds: Array = OrganizationSystem.settings_of(state).get("creatable_kinds", [])
		return "" if not text.strip_edges().is_empty() and kinds.has(kind) else "ORGANIZATION_INVALID_NAME"
	if not diplomacy.organizations.has(organization):
		return "DIPLOMACY_INVALID"
	var member := OrganizationSystem.is_member(state, organization, tag)
	match action:
		JOIN:
			if member:
				return "DIPLOMACY_ALREADY"
			if OrganizationSystem.is_custom(state, organization):
				return "ORGANIZATION_INVITATION_ONLY"
			if not OrganizationSystem.eligible(state, organization, tag):
				return "ORGANIZATION_NOT_ELIGIBLE"
			if diplomacy.cooldown("join_" + organization, tag, tag) > 0:
				return "DIPLOMACY_COOLDOWN"
		LEAVE:
			if not member:
				return "ORGANIZATION_NOT_MEMBER"
		EXPEL, INVITE:
			if not member:
				return "ORGANIZATION_NOT_MEMBER"
			if state.get_country(target) == null or target == tag:
				return "DIPLOMACY_INVALID"
			if (action == EXPEL) != OrganizationSystem.is_member(state, organization, target):
				return "DIPLOMACY_INVALID"
			if action == INVITE and not OrganizationSystem.is_custom(state, organization):
				return "ORGANIZATION_NOT_CUSTOM"
			if diplomacy.cooldown(action + "_" + organization, tag, target) > 0:
				return "DIPLOMACY_COOLDOWN"
		RESOLUTION:
			if organization != OrganizationSystem.UN or not member:
				return "ORGANIZATION_NOT_MEMBER"
			if text == OrganizationSystem.SECURITY_COUNCIL and not diplomacy.security_council.has(tag):
				return "ORGANIZATION_NOT_IN_COUNCIL"
			if state.get_country(target) == null or target == tag:
				return "DIPLOMACY_INVALID"
			if diplomacy.cooldown("resolution", tag, target) > 0:
				return "DIPLOMACY_COOLDOWN"
	return ""


func execute(state: SimState) -> void:
	var tag := str(issuer)
	match action:
		JOIN:
			OrganizationSystem.join(state, organization, tag)
		LEAVE:
			OrganizationSystem.leave(state, organization, tag)
		EXPEL:
			OrganizationSystem.expel(state, organization, tag, target)
		INVITE:
			OrganizationSystem.invite(state, organization, tag, target)
		CREATE:
			OrganizationSystem.create(state, tag, text.strip_edges(), kind)
		RESOLUTION:
			OrganizationSystem.vote_resolution(state, text, tag, target)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["action"] = action
	data["organization"] = organization
	data["target"] = target
	data["text"] = text
	data["kind"] = kind
	return data

class_name InfluenceCommand
extends Command
## Dépenser des points d'influence dans un pays : soutenir un parti, financer l'opposition, influence
## culturelle, ouvrir ou fermer une base militaire.

var target: String = ""
var action: String = ""
var party_id: String = ""


func _init(p_issuer: StringName = &"", p_target: String = "", p_action: String = "", p_party_id: String = "") -> void:
	issuer = p_issuer
	target = p_target
	action = p_action
	party_id = p_party_id


func get_type() -> StringName:
	return &"influence"


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func refusal_reason(state: SimState) -> String:
	var tag := str(issuer)
	var country := state.get_country(target)
	if state.get_country(tag) == null or country == null or tag == target or not InfluenceSystem.ACTIONS.has(action):
		return "DIPLOMACY_INVALID"
	var settings: Dictionary = (InfluenceSystem.settings_of(state).get("actions", {}) as Dictionary).get(action, {})
	if float(state.diplomacy.influence_points.get(tag, 0.0)) < float(settings.get("cost", 0.0)):
		return "INFLUENCE_NOT_ENOUGH"
	if state.diplomacy.cooldown("influence_" + action, tag, target) > 0:
		return "DIPLOMACY_COOLDOWN"
	var has_base := state.diplomacy.bases.has(DiplomacyState.opinion_key(tag, target))
	match action:
		"support_party":
			if not country.politics.parties.has(party_id):
				return "INFLUENCE_NO_PARTY"
		"fund_opposition":
			if country.politics.parties.size() < 2:
				return "MEDIA_NO_OPPOSITION"
		"open_base":
			if has_base:
				return "DIPLOMACY_ALREADY"
			if not state.diplomacy.has_treaty(tag, target, "military_access") \
					and state.diplomacy.relation(tag, target) < float(settings.get("min_relation", 0.0)):
				return "INFLUENCE_BASE_REFUSED"
		"close_base":
			if not has_base:
				return "DIPLOMACY_ALREADY"
	return ""


func execute(state: SimState) -> void:
	InfluenceSystem.perform(state, str(issuer), target, action, party_id)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["target"] = target
	data["action"] = action
	data["party"] = party_id
	return data

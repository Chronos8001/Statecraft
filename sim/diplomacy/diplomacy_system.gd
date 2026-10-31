class_name DiplomacySystem
extends SimSystem
## Diplomatie, une fois par mois : sans nouvel événement, les relations reviennent lentement à leur niveau
## naturel (celui de 2026, relevé par les traités signés pendant la partie), l'opinion publique suit les
## relations avec retard et la confiance se refait peu à peu. Les actions et traités sont appliqués par les
## commandes (fonctions statiques ci-dessous).

const PRIORITY := 30
## Écart en dessous duquel une paire revient exactement à son niveau de départ.
const CLEANUP := 0.05
const EVENT_TREATY_SIGNED := &"treaty_signed"
const EVENT_TREATY_REFUSED := &"treaty_refused"
const EVENT_TREATY_CANCELLED := &"treaty_cancelled"
const EVENT_ACTION := &"diplomatic_action"
const EVENT_ULTIMATUM := &"ultimatum"
const FREE_TRADE := "free_trade"
const AGREEMENT_PREFIX := "treaty_"


func get_id() -> StringName:
	return &"diplomacy"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	var settings := state.diplomacy_settings
	if settings.is_empty():
		return
	var diplomacy := state.diplomacy
	var relation_return := float(settings.get("relation_return", 0.0))
	var follow := float(settings.get("opinion_follow", 0.0))
	# L'opinion suit l'écart des relations de la paire (dans les deux sens).
	var opinion_keys: Dictionary = {}
	for key: String in diplomacy.opinion_changes.keys():
		opinion_keys[key] = true
	for key: String in diplomacy.relation_changes.keys():
		var parts := key.split("|")
		opinion_keys[DiplomacyState.opinion_key(parts[0], parts[1])] = true
		opinion_keys[DiplomacyState.opinion_key(parts[1], parts[0])] = true
	for key: String in opinion_keys.keys():
		var parts := key.split(">")
		var target := float(diplomacy.relation_changes.get(DiplomacyState.pair_key(parts[0], parts[1]), 0.0))
		var current := float(diplomacy.opinion_changes.get(key, 0.0))
		_store(diplomacy.opinion_changes, key, current + (target - current) * follow)
	_decay(diplomacy.relation_changes, relation_return)
	_decay(diplomacy.trust_changes, float(settings.get("trust_return", 0.0)))
	for key: Variant in diplomacy.cooldowns.keys():
		var months := int(diplomacy.cooldowns[key]) - 1
		if months <= 0:
			diplomacy.cooldowns.erase(key)
		else:
			diplomacy.cooldowns[key] = months


static func _decay(changes: Dictionary, rate: float) -> void:
	for key: Variant in changes.keys():
		_store(changes, key, float(changes[key]) * (1.0 - rate))


static func _store(changes: Dictionary, key: Variant, value: float) -> void:
	if absf(value) < CLEANUP:
		changes.erase(key)
	else:
		changes[key] = value


static func actions_settings(state: SimState) -> Dictionary:
	return state.diplomacy_settings.get("actions", {})


## État contesté : {parent, recognized_by | not_recognized_by}, ou {} pour un État reconnu de tous.
static func recognition_of(state: SimState, tag: String) -> Dictionary:
	return (state.diplomacy_start.get("recognition", {}) as Dictionary).get(tag, {})


## Situation de départ : traités de 2026, ambassades fermées, reconnaissance des États contestés.
static func setup_start(state: SimState) -> void:
	var diplomacy := state.diplomacy
	var start := state.diplomacy_start
	for entry: Variant in (start.get("treaties", {}) as Dictionary).get("list", []):
		var values: Array = entry
		if state.countries.has(values[1]) and state.countries.has(values[2]):
			add_treaty(state, str(values[0]), str(values[1]), str(values[2]), true)
	for entry: Variant in (start.get("no_embassy", {}) as Dictionary).get("list", []):
		diplomacy.closed_embassies[DiplomacyState.pair_key(str(entry[0]), str(entry[1]))] = true
	var recognition: Dictionary = start.get("recognition", {})
	for disputed: String in recognition.keys():
		if not state.countries.has(disputed):
			continue
		var rules: Dictionary = recognition[disputed]
		var parent := str(rules.get("parent", ""))
		for tag: String in state.countries.keys():
			if tag == disputed or tag == parent:
				continue
			var recognized := (rules["recognized_by"] as Array).has(tag) if rules.has("recognized_by") \
				else not (rules.get("not_recognized_by", []) as Array).has(tag)
			if recognized:
				diplomacy.recognitions[DiplomacyState.opinion_key(tag, disputed)] = true
			else:
				diplomacy.closed_embassies[DiplomacyState.pair_key(tag, disputed)] = true
		if not parent.is_empty():
			diplomacy.closed_embassies[DiplomacyState.pair_key(parent, disputed)] = true


## Nouveau traité. Ceux signés pendant la partie relèvent durablement les relations ; un traité de
## libre-échange devient un accord commercial.
static func add_treaty(state: SimState, treaty_type: String, a: String, b: String, initial: bool) -> int:
	var diplomacy := state.diplomacy
	var treaty_id := diplomacy.next_treaty_id
	diplomacy.next_treaty_id += 1
	diplomacy.treaties[treaty_id] = {"type": treaty_type, "a": a, "b": b, "initial": initial,
		"year": state.date.year, "month": state.date.month}
	if not initial:
		var key := DiplomacyState.pair_key(a, b)
		var bonus := float((state.treaty_definitions.get(treaty_type, {}) as Dictionary).get("relation_bonus", 0.0))
		diplomacy.treaty_bonus[key] = float(diplomacy.treaty_bonus.get(key, 0.0)) + bonus
		if treaty_type == FREE_TRADE and not state.trade.start_flows.is_empty():
			state.trade.agreements["%s%d" % [AGREEMENT_PREFIX, treaty_id]] = {"kind": FREE_TRADE, "members": [a, b]}
			_refresh_trade(state)
	return treaty_id


static func _refresh_trade(state: SimState) -> void:
	state.trade.refresh_pair_kinds(TradeModel.KIND_ORDER)
	state.trade.dirty = true
	TradeSystem.update_trade(state)


static func propose_treaty(state: SimState, proposer: String, target: String, treaty_type: String) -> void:
	var settings := actions_settings(state)
	var definition: Dictionary = state.treaty_definitions.get(treaty_type, {})
	var diplomacy := state.diplomacy
	diplomacy.set_cooldown("treaty_" + treaty_type, proposer, target, int(settings.get("treaty_cooldown", 0)))
	var accepted := target == str(state.player_tag) \
		or DiplomacyModel.treaty_score(state, proposer, target, definition) > 0.0
	if accepted:
		add_treaty(state, treaty_type, proposer, target, false)
		diplomacy.change_trust(proposer, target, float(settings.get("treaty_signed_trust", 0.0)))
		TensionSystem.add_event(state, "treaty_signed")
		state.add_event(EVENT_TREATY_SIGNED, proposer, {"target": target, "treaty": treaty_type})
	else:
		diplomacy.change_relation(proposer, target, float(settings.get("treaty_refused_relation", 0.0)))
		state.add_event(EVENT_TREATY_REFUSED, proposer, {"target": target, "treaty": treaty_type})


static func cancel_treaty(state: SimState, by: String, treaty_id: int) -> void:
	var diplomacy := state.diplomacy
	var treaty: Dictionary = diplomacy.treaties.get(treaty_id, {})
	if treaty.is_empty():
		return
	var other := str(treaty["b"]) if treaty["a"] == by else str(treaty["a"])
	var definition: Dictionary = state.treaty_definitions.get(treaty["type"], {})
	diplomacy.treaties.erase(treaty_id)
	if not bool(treaty.get("initial", false)):
		var key := DiplomacyState.pair_key(by, other)
		diplomacy.treaty_bonus[key] = float(diplomacy.treaty_bonus.get(key, 0.0)) - float(definition.get("relation_bonus", 0.0))
		if is_zero_approx(float(diplomacy.treaty_bonus[key])):
			diplomacy.treaty_bonus.erase(key)
	var agreement_id := "%s%d" % [AGREEMENT_PREFIX, treaty_id]
	if state.trade.agreements.has(agreement_id):
		state.trade.agreements.erase(agreement_id)
		_refresh_trade(state)
	diplomacy.change_relation(by, other, float(definition.get("break_relation", 0.0)))
	diplomacy.change_trust(by, other, float(definition.get("break_trust", 0.0)))
	state.add_event(EVENT_TREATY_CANCELLED, by, {"target": other, "treaty": treaty["type"]})


## Effets d'une action diplomatique (réglages « actions » de la diplomatie).
static func perform(state: SimState, actor: String, target: String, action: String) -> void:
	var settings: Dictionary = actions_settings(state).get(action, {})
	var diplomacy := state.diplomacy
	var country := state.get_country(actor)
	diplomacy.set_cooldown(action, actor, target, int(settings.get("cooldown", 0)))
	if settings.has("cost_share"):
		InvestmentSystem.add_debt_usd(country, state, float(settings["cost_share"]) / DiplomacyModel.PERCENT
			* TradeSystem.current_gdp(state, actor))
	match action:
		"open_embassy":
			diplomacy.closed_embassies.erase(DiplomacyState.pair_key(actor, target))
		"close_embassy":
			diplomacy.closed_embassies[DiplomacyState.pair_key(actor, target)] = true
		"recognize", "withdraw_recognition":
			var parent := str(recognition_of(state, target).get("parent", ""))
			if action == "recognize":
				diplomacy.recognitions[DiplomacyState.opinion_key(actor, target)] = true
			else:
				diplomacy.recognitions.erase(DiplomacyState.opinion_key(actor, target))
				diplomacy.closed_embassies[DiplomacyState.pair_key(actor, target)] = true
			if not parent.is_empty():
				diplomacy.change_relation(actor, parent, float(settings.get("parent_relation", 0.0)))
				diplomacy.change_trust(actor, parent, float(settings.get("parent_trust", 0.0)))
		"guarantee":
			diplomacy.guarantees[DiplomacyState.opinion_key(actor, target)] = true
			var threshold := float(settings.get("enemy_threshold", -DiplomacyState.LIMIT))
			for enemy: String in state.countries.keys():
				if enemy != actor and enemy != target and diplomacy.relation(enemy, target) <= threshold:
					diplomacy.change_relation(actor, enemy, float(settings.get("enemy_relation", 0.0)))
		"revoke_guarantee":
			diplomacy.guarantees.erase(DiplomacyState.opinion_key(actor, target))
		"ultimatum":
			_ultimatum(state, actor, target, settings)
			return
	diplomacy.change_relation(actor, target, float(settings.get("relation", 0.0)))
	diplomacy.change_trust(actor, target, float(settings.get("trust", 0.0)))
	diplomacy.change_opinion(actor, target, float(settings.get("opinion", 0.0)))
	diplomacy.change_opinion(target, actor, float(settings.get("opinion", 0.0)))
	state.add_event(EVENT_ACTION, actor, {"target": target, "action": action})


## Ultimatum : céder un tribut (part du PIB de la cible) ou subir une rupture de confiance.
static func _ultimatum(state: SimState, actor: String, target: String, settings: Dictionary) -> void:
	var diplomacy := state.diplomacy
	TensionSystem.add_event(state, "ultimatum")
	var accepted := target != str(state.player_tag) and DiplomacyModel.ultimatum_score(state, actor, target, settings) > 0.0
	if accepted:
		var amount := float(settings.get("tribute_share", 0.0)) / DiplomacyModel.PERCENT \
			* TradeSystem.current_gdp(state, target)
		InvestmentSystem.add_debt_usd(state.get_country(target), state, amount)
		InvestmentSystem.add_debt_usd(state.get_country(actor), state, -amount)
		diplomacy.change_relation(actor, target, float(settings.get("accepted_relation", 0.0)))
		diplomacy.change_trust(actor, target, float(settings.get("accepted_trust", 0.0)))
		diplomacy.change_opinion(target, actor, float(settings.get("accepted_opinion", 0.0)))
	else:
		diplomacy.change_relation(actor, target, float(settings.get("refused_relation", 0.0)))
		diplomacy.change_trust(actor, target, float(settings.get("refused_trust", 0.0)))
	state.add_event(EVENT_ULTIMATUM, actor, {"target": target, "accepted": accepted})

class_name LeaderSystem
extends SimSystem
## Dirigeants, une fois par mois : mort naturelle du chef de l'État et du chef du gouvernement selon leur âge
## (loi de Gompertz : la mortalité annuelle croît d'un facteur fixe chaque année), puis succession.
## Les événements peuvent aussi tuer un dirigeant (attentat, maladie) avec kill().
## Succession : nouveau personnage du même parti (même nom de famille dans une monarchie) ; il prend aussi la
## tête du parti. Choc de stabilité plus fort hors des démocraties.

const PRIORITY := 6
const EVENT_LEADER_DIED := &"leader_died"
const HEAD_OF_STATE := "head_of_state"
const HEAD_OF_GOVERNMENT := "head_of_government"
const ROLES := [HEAD_OF_STATE, HEAD_OF_GOVERNMENT]
const CAUSE_NATURAL := "natural"
const MONTHS_PER_YEAR := 12.0


func get_id() -> StringName:
	return &"leaders"


func get_periods() -> Array[StringName]:
	return [MONTHLY]


func get_priority() -> int:
	return PRIORITY


func on_month(state: SimState) -> void:
	var settings := settings_of(state)
	if settings.is_empty():
		return
	var tags: Array = state.countries.keys()
	tags.sort()
	for tag: String in tags:
		var country: CountryState = state.countries[tag]
		for role: String in ROLES:
			var character_id := leader_id(country, role)
			if character_id.is_empty() or (role == HEAD_OF_GOVERNMENT
					and character_id == country.politics.head_of_state):
				continue
			var leader := GovernmentSystem.character(state, character_id)
			if not leader.has("birth_year"):
				continue
			var age := state.date.year - int(leader["birth_year"])
			if state.rng.randf() < monthly_death_chance(age, settings):
				kill(state, country, role, CAUSE_NATURAL)


static func settings_of(state: SimState) -> Dictionary:
	return state.politics_definitions.get("leader_settings", {})


## Chance de mourir dans le mois à cet âge.
static func monthly_death_chance(age: int, settings: Dictionary) -> float:
	var annual := float(settings.get("mortality_at_reference", 0.0)) * float(settings.get("office_factor", 1.0)) \
		* exp(float(settings.get("mortality_growth", 0.0)) * (age - float(settings.get("reference_age", 0.0))))
	annual = clampf(annual, 0.0, float(settings.get("max_annual", 1.0)))
	return 1.0 - pow(1.0 - annual, 1.0 / MONTHS_PER_YEAR)


static func leader_id(country: CountryState, role: String) -> String:
	return country.politics.head_of_state if role == HEAD_OF_STATE else country.politics.head_of_government


## Chef d'un parti : remplaçant nommé en cours de partie, sinon celui des données.
static func party_leader(state: SimState, party_id: String) -> String:
	if state.party_leaders.has(party_id):
		return str(state.party_leaders[party_id])
	return str(((state.politics_definitions.get("parties", {}) as Dictionary).get(party_id, {}) as Dictionary).get(
		"leader", ""))


## Mort d'un dirigeant (cause : « natural » ou celle d'un événement) et succession. Renvoie false si le poste
## est vacant ou si aucun successeur ne peut être créé.
static func kill(state: SimState, country: CountryState, role: String, cause: String) -> bool:
	var politics := country.politics
	var character_id := leader_id(country, role)
	if character_id.is_empty():
		return false
	var deceased := GovernmentSystem.character(state, character_id)
	var party := str(deceased.get("party", politics.ruling_party()))
	var successor := GovernmentModel.make_character(state, country, party, "%s|successor|%s|%d" % [country.tag,
		character_id, state.date.to_day_number()])
	if successor.is_empty():
		return false
	if role == HEAD_OF_STATE and politics.regime.contains("monarchy") and deceased.has("last_name"):
		successor["last_name"] = deceased["last_name"]
	var successor_id := "%s%d" % [GovernmentSystem.CHARACTER_PREFIX, state.next_character_id]
	state.next_character_id += 1
	state.characters[successor_id] = successor
	state.dead_characters[character_id] = true
	if politics.head_of_state == character_id:
		politics.head_of_state = successor_id
	if politics.head_of_government == character_id:
		politics.head_of_government = successor_id
	if not party.is_empty() and party_leader(state, party) == character_id:
		state.party_leaders[party] = successor_id
	var settings := settings_of(state)
	var shock: Dictionary = settings.get("democratic_shock" if politics.democratic else "autocratic_shock", {})
	country.society.stability = clampf(country.society.stability - float(shock.get("stability", 0.0)), 0.0,
		SocietyModel.PERCENT)
	country.society.legitimacy = clampf(country.society.legitimacy - float(shock.get("legitimacy", 0.0)), 0.0,
		SocietyModel.PERCENT)
	state.add_event(EVENT_LEADER_DIED, country.tag, {"role": role, "cause": cause, "deceased": character_id,
		"successor": successor_id, "democratic": politics.democratic})
	return true

class_name SimState
extends RefCounted
## État complet d'une partie, indépendant de l'affichage. Tout le hasard de la simulation
## passe par rng, initialisé avec une graine unique : à graine et commandes identiques,
## la partie se déroule de la même façon.

var game_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var date: GameDate = GameDate.new()
var player_tag: StringName = &""
## tag → CountryState (rempli par WorldSetup au début de la partie).
var countries: Dictionary = {}
## identifiant → CurrencyState.
var currencies: Dictionary = {}
## Section « economy » de defines.json, utilisée par les systèmes et les commandes économiques.
var economy_settings: Dictionary = {}
## Impôts, postes de dépense et réglages du budget : {taxes, spending, settings}.
var budget_definitions: Dictionary = {}
## Événements de simulation du dernier tick ({type, tag, …}), transmis à l'interface puis vidés.
var events: Array[Dictionary] = []


func setup(p_seed: int, start_date: GameDate, p_player_tag: StringName = &"") -> void:
	game_seed = p_seed
	rng.seed = p_seed
	date = start_date.copy()
	player_tag = p_player_tag


func get_country(tag: String) -> CountryState:
	return countries.get(tag)


func get_currency(currency_id: String) -> CurrencyState:
	return currencies.get(currency_id)


func add_event(type: StringName, tag: String, details: Dictionary = {}) -> void:
	var event := {"type": type, "tag": tag}
	event.merge(details)
	events.append(event)

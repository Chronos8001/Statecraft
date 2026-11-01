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
## identifiant de ressource → MarketState.
var markets: Dictionary = {}
## Détroits fermés au commerce (identifiant → true).
var closed_straits: Dictionary = {}
## Routes des détroits, chaînes d'approvisionnement des secteurs et réglages : {straits, sectors, settings}.
var resource_definitions: Dictionary = {}
var trade: TradeState = TradeState.new()
## Sources d'énergie, bâtiments, provinces, production des mines et réglages : {sources, buildings, provinces,
## mine_outputs, settings}.
var energy_definitions: Dictionary = {}
## Bâtiments par province : identifiant de province → {bâtiment: nombre}.
var buildings: Dictionary = {}
## Chantiers en cours : [{id, tag, building, province, months_left, total_months, monthly_cost}].
var projects: Array[Dictionary] = []
var next_project_id: int = 0
## Section « investment » de defines.json.
var investment_settings: Dictionary = {}
## Groupes sociaux, régimes, idéologies et réglages de la société : {groups, regimes, ideologies, settings}.
var society_definitions: Dictionary = {}
## Partis (names#parties) et réglages de la vie politique : {parties, settings}.
var politics_definitions: Dictionary = {}
## Section « trade » de defines.json.
var trade_settings: Dictionary = {}
## Relations entre pays et section « diplomacy » de defines.json.
var diplomacy: DiplomacyState = DiplomacyState.new()
var diplomacy_settings: Dictionary = {}
## Types de traités (data/treaties) et situation diplomatique de départ (data/diplomacy).
var treaty_definitions: Dictionary = {}
var diplomacy_start: Dictionary = {}
## Règles des organisations (data/organization_rules).
var organization_rules: Dictionary = {}
## Mesures de sanction (data/sanctions).
var sanction_definitions: Dictionary = {}
## Types d'aide (data/aid).
var aid_definitions: Dictionary = {}
## Forces armées : modules remplaçables (modèle, combats, IA) et réglages (defines.military).
var military: MilitaryRegistry = MilitaryRegistry.new()
var military_settings: Dictionary = {}
## Contrôle des provinces : id → pays contrôleur ; provinces disputées : id → {by, share} (part tenue par « by »).
var province_control: Dictionary = {}
var contested: Dictionary = {}
## Voisins terrestres de chaque province (identifiants en texte), calculés au départ.
var province_neighbors: Dictionary = {}
## Provinces de chaque pays propriétaire (tag → [identifiants]), propriétaire de chaque province et provinces
## frontalières (voisines d'une province d'un autre propriétaire), calculés au départ.
var provinces_by_owner: Dictionary = {}
var province_owner: Dictionary = {}
var border_provinces: Array[String] = []
## Compteur incrémenté à chaque changement de contrôleur ou de province disputée.
var control_version: int = 0
## Groupes d'armées : id → ArmyGroup.
var army_groups: Dictionary = {}
var next_army_group_id: int = 1
## Flottes : id → Fleet ; zones maritimes (data/sea_zones), voisines par la mer (détroits et canaux compris :
## zone → [zones]), détroit franchi entre deux zones (« a|b » → identifiant) ; contrôle des mers en guerre :
## zone → {war, side, leader} (contested: true si aucun camp ne domine), recalculé chaque jour.
var fleets: Dictionary = {}
var next_fleet_id: int = 1
var sea_zones: Dictionary = {}
var sea_links: Dictionary = {}
var sea_link_straits: Dictionary = {}
var sea_control: Dictionary = {}
## Détroits fermés par les combats (identifiant → true), rouverts quand la mer n'est plus disputée.
var war_closed_straits: Dictionary = {}
## Actions ponctuelles : affaiblissement d'un camp sur un front (« clé du front|tag » → {factor, days_left}),
## dégâts aux infrastructures des provinces (id → points), effets temporaires sur la croissance
## (tag → [{growth, months_left}]).
var front_penalties: Dictionary = {}
var infrastructure_damage: Dictionary = {}
var attack_effects: Dictionary = {}
## Pays voisins par la terre (tag → {tag: true}), d'après les propriétaires des provinces au départ.
var land_neighbors: Dictionary = {}
## Guerres en cours : id → War ; factions rebelles : id → RebelFaction ; buts de guerre (data/war_goals).
var wars: Dictionary = {}
var next_war_id: int = 1
var rebels: Dictionary = {}
var war_goal_definitions: Dictionary = {}
## Fronts des guerres : clé → Front ; recalculés quand le contrôle des provinces ou les guerres changent.
var fronts: Dictionary = {}
var fronts_dirty: bool = true
## Calculés avec les fronts pour chaque belligérant : province la plus peuplée tenue (tag → id) et présence
## sur la carte (tag → true s'il tient ou dispute au moins une province).
var front_seats: Dictionary = {}
var front_holdings: Dictionary = {}
## Terrains (data/terrains), pour la défense des provinces.
var terrain_definitions: Dictionary = {}
## Appels aux armes adressés au joueur, en attente de réponse : [{war, ally, side, days_left}].
var calls_to_arms: Array[Dictionary] = []
## Propositions de paix blanche adressées au joueur, en attente de réponse : [{war, from, days_left}].
var peace_offers: Array[Dictionary] = []
## Taille de l'image de la carte (pixels), pour les distances entre provinces.
var map_size: Vector2 = Vector2(360.0, 180.0)
## Personnages créés pendant la partie (ministres, successeurs) : identifiant → personnage.
var characters: Dictionary = {}
var next_character_id: int = 0
var next_crisis_id: int = 0
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

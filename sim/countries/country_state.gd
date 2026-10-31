class_name CountryState
extends RefCounted
## État d'un pays pendant la partie. Créé depuis les données au début de la partie
## (WorldSetup), puis modifié uniquement par les systèmes de simulation et les commandes.

var tag: String = ""
var economy: EconomyState = EconomyState.new()
var resources: CountryResources = CountryResources.new()
var energy: EnergyState = EnergyState.new()
var society: SocietyState = SocietyState.new()
var politics: PoliticsState = PoliticsState.new()
## Lois : identifiant → option en vigueur, options de départ, mois avant de pouvoir y revenir, et effets
## cumulés par rapport au départ ({groups, stability, growth, legitimacy, corruption, budget}).
var laws: Dictionary = {}
var start_laws: Dictionary = {}
var law_cooldowns: Dictionary = {}
var law_effects: Dictionary = {}

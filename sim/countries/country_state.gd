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
## Constitution : réforme → option en vigueur.
var constitution: Dictionary = {}
## Gouvernement : portefeuille → identifiant du ministre, compétence et corruption moyenne du cabinet de
## départ, effets du cabinet par rapport au départ, et compteur de tirages des candidats.
var cabinet: Dictionary = {}
var start_competence: Dictionary = {}
var start_minister_corruption: float = 0.0
var cabinet_effects: Dictionary = {}
var cabinet_generation: int = 0

class_name CountryState
extends RefCounted
## État d'un pays pendant la partie. Créé depuis les données au début de la partie
## (WorldSetup), puis modifié uniquement par les systèmes de simulation et les commandes.

var tag: String = ""
var economy: EconomyState = EconomyState.new()

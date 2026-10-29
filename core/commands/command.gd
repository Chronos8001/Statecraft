class_name Command
extends RefCounted
## Action envoyée par l'UI ou l'IA vers la simulation. L'UI ne modifie jamais l'état directement :
## elle soumet des commandes à GameState, qui les exécute au tick suivant. Cela garde la
## simulation déterministe et sérialisable (sauvegardes, rejeu, futur multijoueur).

## Tag du pays qui émet la commande.
var issuer: StringName = &""


func get_type() -> StringName:
	return &"command"


func can_execute(_state: SimState) -> bool:
	return true


func execute(_state: SimState) -> void:
	pass


func to_dict() -> Dictionary:
	return {"type": get_type(), "issuer": issuer}

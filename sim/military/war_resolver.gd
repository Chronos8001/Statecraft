class_name WarResolver
extends RefCounted
## Résolution des combats (module remplaçable via MilitaryRegistry). Le modèle de base agrégé arrive avec
## les guerres et les fronts (étape 7c) ; un DLC peut le remplacer par une résolution détaillée.


## Un jour de combat sur toutes les guerres en cours.
func resolve_day(_state: SimState) -> void:
	pass

class_name MilitaryAI
extends RefCounted
## Décisions militaires des pays de l'IA (module remplaçable via MilitaryRegistry). Avec les guerres
## (étape 7c) : défense, alliances, paix, et déclarations de guerre selon les revendications, la politique,
## les relations et le rapport de forces. Pour l'instant, l'IA garde ses forces de départ.


## Un mois de décisions pour un pays de l'IA.
func decide_month(_country: CountryState, _state: SimState) -> void:
	pass

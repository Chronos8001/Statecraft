class_name CountryRegistry
extends RefCounted
## Fiche d'un pays pour l'affichage : données de départ (data/countries) corrigées par les changements faits
## pendant la partie (nom, couleur, drapeau). Les pays dissous disparaissent de la liste complète.


static func entry(tag: String) -> Dictionary:
	var data := DataLoader.get_entry("countries", tag)
	var overrides: Dictionary = GameState.sim.country_overrides.get(tag, {})
	if overrides.is_empty():
		return data
	var merged := data.duplicate()
	merged.merge(overrides, true)
	return merged


static func all() -> Dictionary:
	var countries := DataLoader.get_category("countries")
	var sim := GameState.sim
	if sim.country_overrides.is_empty() and sim.dissolved.is_empty():
		return countries
	var result: Dictionary = {}
	for tag: Variant in countries.keys():
		if not sim.dissolved.has(tag):
			result[tag] = entry(str(tag))
	return result


static func name_of(tag: String) -> String:
	return TranslationServer.translate(str(entry(tag).get("name_key", tag)))

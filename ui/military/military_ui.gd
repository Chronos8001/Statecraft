class_name MilitaryUI
extends RefCounted
## Interface militaire (module remplaçable, comme les modules de MilitaryRegistry côté simulation) : un mod
## ou un DLC fournit sa propre sous-classe pour remplacer le panneau Armée et les symboles d'unités.

const PANEL_SCENE := "res://ui/military/military_panel.tscn"


## Panneau Armée du pays joué.
func create_panel() -> InfoPanel:
	return (load(PANEL_SCENE) as PackedScene).instantiate() as InfoPanel


## Nom d'un groupe d'armées : « 1er groupe d'armées », « 2nd Army Group ».
func group_name(group: ArmyGroup) -> String:
	return TranslationServer.translate("ARMY_GROUP_NAME") % ordinal(group.number)


## Nom affiché d'un pays ou d'une faction rebelle (« Rebelles (Soudan) »), déjà traduit.
static func side_name(state: SimState, tag: String) -> String:
	var country := WarSystem.country_of(state, tag)
	var name := TranslationServer.translate(str(DataLoader.get_entry("countries", country).get("name_key", country)))
	return TranslationServer.translate("REBEL_NAME") % name if WarSystem.is_rebel(state, tag) else name


## Nom d'une guerre : « Guerre Russie – Ukraine », « Guerre civile (Soudan) ».
static func war_name(state: SimState, war: War) -> String:
	if war.civil:
		return TranslationServer.translate("WAR_NAME_CIVIL") % side_name(state, war.defender_leader())
	return TranslationServer.translate("WAR_NAME") % [side_name(state, war.attacker_leader()),
		side_name(state, war.defender_leader())]


## Nom d'une flotte : « 1re flotte », « 2nd Fleet ».
func fleet_name(fleet: Fleet) -> String:
	var key := "ORDINAL_F_%d" % fleet.number
	var text := TranslationServer.translate(key)
	if text == key:
		text = TranslationServer.translate("ORDINAL_F_N") % fleet.number
	return TranslationServer.translate("FLEET_NAME") % text


## Nom d'une zone maritime.
static func sea_name(zone_id: String) -> String:
	return TranslationServer.translate(str(DataLoader.get_entry("sea_zones", zone_id).get("name_key", zone_id)))


## Texte d'une exigence de paix : « Zaporijjia », « Réparations (2 % du PIB par an, 5 ans) ».
static func demand_text(state: SimState, demand: Dictionary) -> String:
	if str(demand.get("type", "")) == WarEnd.REPARATIONS:
		var rules: Dictionary = WarEnd.settings_of(state).get("demands", {})
		return TranslationServer.translate("PEACE_DEMAND_REPARATIONS") % [roundi(float(rules.get("reparations_share", 0.0))),
			int(rules.get("reparations_years", 0))]
	var province := str(demand.get("province", ""))
	return TranslationServer.translate(str(DataLoader.get_entry("provinces", province).get("name_key", province)))


## Texte d'une proposition reçue (paix blanche, cessez-le-feu ou paix avec conditions).
static func offer_text(state: SimState, offer: Dictionary) -> String:
	var war: War = state.wars.get(int(offer["war"]))
	var from := side_name(state, str(offer["from"]))
	var days := int(offer.get("days_left", 0))
	match str(offer.get("kind", WarEnd.WHITE)):
		WarEnd.CEASEFIRE:
			return TranslationServer.translate("CEASEFIRE_OFFER_TEXT") % [from, war_name(state, war), days]
		WarEnd.PEACE:
			var parts: PackedStringArray = []
			for demand: Variant in offer.get("demands", []):
				parts.append(demand_text(state, demand))
			return TranslationServer.translate("PEACE_TERMS_TEXT") % [from, war_name(state, war), ", ".join(parts), days]
	return TranslationServer.translate("PEACE_OFFER_TEXT") % [from, war_name(state, war), days]


static func ordinal(number: int) -> String:
	var key := "ORDINAL_%d" % number
	var text := TranslationServer.translate(key)
	return text if text != key else TranslationServer.translate("ORDINAL_N") % number


## Symbole OTAN d'une branche (cadre ami, icône de l'arme).
func branch_symbol(branch: String) -> Control:
	var symbol := NatoSymbol.new()
	symbol.domain = branch
	symbol.icon = NatoSymbol.INFANTRY
	return symbol

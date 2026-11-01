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

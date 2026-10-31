class_name MilitaryUI
extends RefCounted
## Interface militaire (module remplaçable, comme les modules de MilitaryRegistry côté simulation) : un mod
## ou un DLC fournit sa propre sous-classe pour remplacer le panneau Armée et les symboles d'unités.

const PANEL_SCENE := "res://ui/military/military_panel.tscn"


## Panneau Armée du pays joué.
func create_panel() -> InfoPanel:
	return (load(PANEL_SCENE) as PackedScene).instantiate() as InfoPanel


## Symbole OTAN d'une branche (cadre ami, icône de l'arme).
func branch_symbol(branch: String) -> Control:
	var symbol := NatoSymbol.new()
	symbol.domain = branch
	symbol.icon = NatoSymbol.INFANTRY
	return symbol

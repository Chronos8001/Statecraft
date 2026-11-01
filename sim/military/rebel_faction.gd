class_name RebelFaction
extends RefCounted
## Faction rebelle d'une guerre civile : elle contrôle des provinces de son pays sans être un pays. Son
## identifiant (« SDN_REB ») sert de contrôleur dans le contrôle des provinces.

var id: String = ""
var country: String = ""


## Identifiant de la faction rebelle d'un pays.
static func id_for(tag: String) -> String:
	return tag + "_REB"

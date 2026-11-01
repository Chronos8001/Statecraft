class_name RebelFaction
extends RefCounted
## Faction rebelle d'une guerre civile : elle contrôle des provinces de son pays sans être un pays. Son
## identifiant (« SDN_REB ») sert de contrôleur dans le contrôle des provinces.

var id: String = ""
var country: String = ""
## Forces terrestres : effectifs (de départ et actuels), niveau d'équipement, entraînement et moral.
## Force de départ en part de l'armée de terre du gouvernement (données), convertie en effectifs.
var strength_share: float = 0.0
var start_personnel: float = 0.0
var personnel: float = 0.0
var level: float = 1.0
var training: float = 0.0
var morale: float = 0.0


## Identifiant de la faction rebelle d'un pays.
static func id_for(tag: String) -> String:
	return tag + "_REB"

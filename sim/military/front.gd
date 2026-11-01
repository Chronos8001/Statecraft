class_name Front
extends RefCounted
## Front entre deux ennemis d'une même guerre qui se touchent : provinces de chaque camp au contact (voisines
## d'une province ennemie, ou disputées entre eux) et posture de chacun. « a » est dans le camp attaquant.

var key: String = ""
var war_id: int = 0
var a: String = ""
var b: String = ""
## Provinces au contact tenues par chaque camp (tag → [identifiants]) ; une province disputée entre les deux
## figure des deux côtés.
var provinces: Dictionary = {}
## Provinces disputées entre a et b.
var contested: Array[String] = []
## Posture de chaque camp (tag → offensive, defensive, hold, retreat).
var postures: Dictionary = {}
## Calculés chaque jour : forces engagées (puissance, effectifs) et terrain gagné (part de province) par camp.
var strength: Dictionary = {}
var engaged: Dictionary = {}
var progress: Dictionary = {}


static func key_for(war_id: int, a: String, b: String) -> String:
	return "%d:%s|%s" % [war_id, a, b]


func other(tag: String) -> String:
	return b if tag == a else a


func provinces_of(tag: String) -> Array:
	return provinces.get(tag, [])


func posture_of(tag: String) -> String:
	return str(postures.get(tag, ""))

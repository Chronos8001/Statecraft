class_name PartyState
extends RefCounted
## Un parti dans la chambre basse : sièges, score au dernier scrutin et intentions de vote (en %).

var id: String = ""
var ideology: String = ""
## Famille politique (party_group de l'idéologie), utilisée pour l'affinité des groupes sociaux.
var party_group: String = ""
var seats: int = 0
var vote: float = 0.0
var poll: float = 0.0
var previous_poll: float = 0.0
var start_poll: float = 0.0
## Attrait propre du parti, calé au départ pour retrouver le sondage de janvier 2026.
var appeal: float = 1.0
## Écart aléatoire persistant des sondages (logarithme d'un facteur multiplicatif).
var drift: float = 0.0

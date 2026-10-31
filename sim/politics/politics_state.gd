class_name PoliticsState
extends RefCounted
## Vie politique d'un pays : chambre basse, gouvernement, sondages et calendrier électoral.

const SYSTEM_PROPORTIONAL := "proportional"
const SYSTEM_MAJORITARIAN := "majoritarian"
const SYSTEM_MIXED := "mixed"
## Qui forme le gouvernement : la chambre (parlementaire) ou le président élu (présidentiel).
const EXECUTIVE_PARLIAMENTARY := "parliamentary"
const EXECUTIVE_PRESIDENTIAL := "presidential"

var seats: int = 0
## Identifiant de parti → PartyState.
var parties: Dictionary = {}
## Partis membres du gouvernement (le premier dirige).
var government: Array[String] = []
## Petits partis et indépendants regroupés.
var other_seats: int = 0
var other_vote: float = 0.0
var other_poll: float = 0.0
var election_year: int = 0
var election_month: int = 1
var term_years: int = 0
## Chambre dissoute (élections à venir).
var dissolved: bool = false
## Sondages publiés et élections libres (démocraties) ; ailleurs, scrutins de façade.
var polls_published: bool = false
var democratic: bool = false
var executive: String = EXECUTIVE_PARLIAMENTARY
## Élections suspendues (loi martiale).
var suspended: bool = false
## Les autres partis refusent de gouverner avec les familles exclues (réglage « cordon_groups »).
var cordon: bool = false

var system_type: String = SYSTEM_PROPORTIONAL
## Seuil national (% des voix) pour obtenir des sièges à la proportionnelle.
var threshold: float = 0.0
## Part des sièges élus à la proportionnelle dans un système mixte.
var list_share: float = 0.0
var next_election_year: int = 0
var next_election_month: int = 1

var has_presidency: bool = false
var presidential_year: int = 0
var presidential_month: int = 1
var presidential_term: int = 0
var two_rounds: bool = false
var next_presidential_year: int = 0
var next_presidential_month: int = 1

var head_of_state: String = ""
var head_of_government: String = ""
## Idéologie dominante du pouvoir (celle du parti qui dirige le gouvernement après une alternance).
var ideology: String = ""
## Campagne du parti au pouvoir pour le prochain scrutin : dépense (milliards de dollars), bonus de sondage
## (logarithme d'un facteur), provinces où un meeting a eu lieu, mois du dernier meeting (année × 12 + mois).
var campaign_spent: float = 0.0
var campaign_bonus: float = 0.0
var rallies: Dictionary = {}
var last_rally: int = 0
## Fraude prévue au prochain scrutin (0 : aucune, 1 à 3 : de plus en plus massive).
var fraud_level: int = 0
## Promesses de campagne : [{group, party, deadline_year, deadline_month, gain}].
var promises: Array[Dictionary] = []
## Facteur de découverte des fraudes et scandales lié à la liberté de la presse (1 : presse libre).
var media_factor: float = 1.0
## Dernière élection tenue pendant la partie : {kind, year, month, votes: {parti: %}, seats_before, seats_after,
## regions: {province: parti en tête}, rounds: [[{parti: %}], …], winner, government_changed}.
var last_result: Dictionary = {}


func government_seats() -> int:
	var total := 0
	for party_id: String in government:
		var party: PartyState = parties.get(party_id)
		if party != null:
			total += party.seats
	return total


func has_majority() -> bool:
	return government_seats() * 2 > seats


func government_poll() -> float:
	var total := 0.0
	for party_id: String in government:
		var party: PartyState = parties.get(party_id)
		if party != null:
			total += party.poll
	return total


func is_in_government(party_id: String) -> bool:
	return government.has(party_id)


func has_promise(group_id: String) -> bool:
	return promises.any(func(promise: Dictionary) -> bool: return str(promise["group"]) == group_id)


func reset_campaign() -> void:
	campaign_spent = 0.0
	campaign_bonus = 0.0
	rallies.clear()
	fraud_level = 0


func ruling_party() -> String:
	return government[0] if not government.is_empty() else ""


## Mois écoulés depuis le dernier scrutin législatif, à la date donnée.
func months_since_election(year: int, month: int) -> int:
	return (year - election_year) * 12 + month - election_month


static func is_due(year: int, month: int, due_year: int, due_month: int) -> bool:
	return year > due_year or (year == due_year and month >= due_month)

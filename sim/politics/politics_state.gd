class_name PoliticsState
extends RefCounted
## Vie politique d'un pays : chambre basse, gouvernement et sondages.

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
## Sondages publiés (démocraties) ; ailleurs, l'opinion n'est qu'estimée.
var polls_published: bool = false


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

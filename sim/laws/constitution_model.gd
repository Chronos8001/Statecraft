class_name ConstitutionModel
extends RefCounted
## Formules de la constitution, sans état.
##
## Réforme : 2/3 des sièges de la chambre basse, ou référendum. Au référendum, les électeurs de chaque parti
## suivent sa position (de 0 % à 100 % de oui selon l'écart de position), les indécis et petits partis se
## partagent, et la popularité du pouvoir déplace le résultat.

const PERCENT := 100.0
const REPUBLICS := ["parliamentary_republic", "semi_presidential_republic", "presidential_republic"]
const TERM_LIMITS := {"one": 1, "two": 2, "none": 0}


## Options de départ de chaque réforme, déduites de la situation du pays.
static func start_options(politics: PoliticsState, term_limit: String) -> Dictionary:
	return {
		"presidential_term_limit": term_limit,
		"presidential_term": "t%d" % clampi(politics.presidential_term if politics.presidential_term > 0 else 5, 4, 7),
		"legislative_term": "t%d" % clampi(politics.term_years if politics.term_years > 0 else 5, 2, 5),
		"electoral_system": politics.system_type,
		"threshold": "low" if politics.threshold < 3.5 else "medium" if politics.threshold < 7.5 else "high",
		"executive": "presidential" if politics.regime == "presidential_republic"
			else "semi_presidential" if politics.regime == "semi_presidential_republic" else "parliamentary",
	}


## Part de oui (%) attendue à un référendum.
static func referendum_yes(politics: PoliticsState, society: SocietyState, definition: Dictionary, from_option: String,
		to_option: String, settings: Dictionary) -> float:
	var yes := politics.other_poll * 0.5
	var total := politics.other_poll
	for party: PartyState in politics.parties.values():
		var difference := clampf(LawModel.preference(definition, from_option, to_option, party.party_group), -2.0, 2.0)
		yes += party.poll * (0.5 + 0.25 * difference)
		total += party.poll
	var share := yes / total * PERCENT if total > 0.0 else PERCENT / 2.0
	share += float(settings.get("referendum_government_effect", 0.0)) * (society.support - PERCENT / 2.0)
	return clampf(share, 0.0, PERCENT)

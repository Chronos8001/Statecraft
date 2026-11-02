class_name RegimeChange
extends RefCounted
## Changement de régime hors réforme constitutionnelle (révolution, coup, démocratisation soudaine) : junte par le
## mécanisme du coup d'État ; démocratie : élections rétablies et exécutif selon le régime ; autres régimes : plus
## d'élections libres, le parti au pouvoir reste seul. L'influence des groupes sociaux suit le nouveau régime.

const EVENT_REGIME_CHANGED := &"regime_changed"
const JUNTA := "military_junta"
const ELECTION_DELAY_MONTHS := 12
const MONTHS_PER_YEAR := 12


static func apply(state: SimState, country: CountryState, regime: String) -> bool:
	var regimes: Dictionary = state.society_definitions.get("regimes", {})
	if not regimes.has(regime) or country.politics.regime == regime:
		return false
	var definition: Dictionary = regimes[regime]
	var politics := country.politics
	if regime == JUNTA:
		CrisisSystem.install_junta(country, state)
	else:
		var democratic := bool(definition.get("democratic", false))
		var was_democratic := politics.democratic
		politics.regime = regime
		politics.democratic = democratic
		politics.polls_published = democratic
		politics.suspended = not democratic
		if democratic:
			ConstitutionSystem._set_executive(country, state, regime)
			if not was_democratic:
				var next := ElectionSystem._add_months(state.date.year, state.date.month, ELECTION_DELAY_MONTHS)
				politics.next_election_year = next[0]
				politics.next_election_month = next[1]
				politics.term_years = maxi(politics.term_years, 4)
		else:
			politics.executive = PoliticsState.EXECUTIVE_PRESIDENTIAL
			var ruling := politics.ruling_party()
			if not ruling.is_empty():
				var government: Array[String] = [ruling]
				politics.government = government
		country.society.influence = SocietyModel.influence_weights(country.society.group_shares,
			state.society_definitions.get("groups", {}), definition.get("group_influence", {}))
	state.add_event(EVENT_REGIME_CHANGED, country.tag, {"regime": regime})
	return true

class_name TradeCommands
extends RefCounted
## Règles communes aux commandes commerciales du joueur.


static func valid_partner(state: SimState, issuer: String, target: String) -> bool:
	return issuer != target and state.get_country(issuer) != null and state.get_country(target) != null

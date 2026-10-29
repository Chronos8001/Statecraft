class_name SimState
extends RefCounted
## État complet d'une partie, indépendant de l'affichage. Tout le hasard de la simulation
## passe par rng, initialisé avec une graine unique : à graine et commandes identiques,
## la partie se déroule de la même façon.

var game_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var date: GameDate = GameDate.new()
var player_tag: StringName = &""


func setup(p_seed: int, start_date: GameDate, p_player_tag: StringName = &"") -> void:
	game_seed = p_seed
	rng.seed = p_seed
	date = start_date.copy()
	player_tag = p_player_tag

extends Node
## Bus de signaux globaux. Les systèmes émettent ici, l'UI et les autres systèmes écoutent,
## sans dépendre directement les uns des autres.

# --- Démarrage, données, mods ---
@warning_ignore("unused_signal")
signal mods_discovered(mod_count: int)
@warning_ignore("unused_signal")
signal data_loaded(file_count: int, error_count: int)
@warning_ignore("unused_signal")
signal locale_changed(locale: String)
@warning_ignore("unused_signal")
signal system_registered(key: StringName)

# --- Partie ---
@warning_ignore("unused_signal")
signal game_started(player_tag: StringName)
@warning_ignore("unused_signal")
signal game_saved(path: String)
@warning_ignore("unused_signal")
signal game_loaded(path: String)
@warning_ignore("unused_signal")
signal command_executed(command: Command)

# --- Temps ---
@warning_ignore("unused_signal")
signal game_speed_changed(speed: int)
@warning_ignore("unused_signal")
signal game_pause_changed(paused: bool)
@warning_ignore("unused_signal")
signal hour_passed(date: GameDate)
@warning_ignore("unused_signal")
signal day_passed(date: GameDate)
@warning_ignore("unused_signal")
signal week_passed(date: GameDate)
@warning_ignore("unused_signal")
signal month_passed(date: GameDate)
@warning_ignore("unused_signal")
signal year_passed(date: GameDate)

# --- Politique et diplomatie ---
@warning_ignore("unused_signal")
signal election_held(country_tag: StringName)
@warning_ignore("unused_signal")
signal government_changed(country_tag: StringName)
@warning_ignore("unused_signal")
signal war_declared(attacker_tag: StringName, defender_tag: StringName)
@warning_ignore("unused_signal")
signal peace_signed(country_a_tag: StringName, country_b_tag: StringName)

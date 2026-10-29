class_name InputActions
extends RefCounted
## Actions clavier par défaut. Déplacement de la carte en touches physiques (WASD = ZQSD en AZERTY) ;
## temps en touches logiques (Espace, + et - selon le caractère imprimé sur la touche).

const MAP_PAN_LEFT := &"map_pan_left"
const MAP_PAN_RIGHT := &"map_pan_right"
const MAP_PAN_UP := &"map_pan_up"
const MAP_PAN_DOWN := &"map_pan_down"
const MAP_ZOOM_IN := &"map_zoom_in"
const MAP_ZOOM_OUT := &"map_zoom_out"
const TIME_TOGGLE_PAUSE := &"time_toggle_pause"
const TIME_SPEED_UP := &"time_speed_up"
const TIME_SLOW_DOWN := &"time_slow_down"
## Touches 1 à 5 : vitesse directe, comme dans CK3 et HOI4.
const TIME_SPEED_ACTIONS: Array[StringName] = [&"time_speed_1", &"time_speed_2", &"time_speed_3",
	&"time_speed_4", &"time_speed_5"]

const DEFAULT_KEYS := {
	MAP_PAN_LEFT: [KEY_A, KEY_LEFT],
	MAP_PAN_RIGHT: [KEY_D, KEY_RIGHT],
	MAP_PAN_UP: [KEY_W, KEY_UP],
	MAP_PAN_DOWN: [KEY_S, KEY_DOWN],
	MAP_ZOOM_IN: [KEY_PAGEUP],
	MAP_ZOOM_OUT: [KEY_PAGEDOWN],
	&"time_speed_1": [KEY_1, KEY_KP_1],
	&"time_speed_2": [KEY_2, KEY_KP_2],
	&"time_speed_3": [KEY_3, KEY_KP_3],
	&"time_speed_4": [KEY_4, KEY_KP_4],
	&"time_speed_5": [KEY_5, KEY_KP_5],
}

const LOGICAL_KEYS := {
	TIME_TOGGLE_PAUSE: [KEY_SPACE],
	TIME_SPEED_UP: [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD],
	TIME_SLOW_DOWN: [KEY_MINUS, KEY_KP_SUBTRACT],
}


## Déclare les actions absentes de l'InputMap (sans écraser une configuration existante).
static func register_defaults() -> void:
	for action: StringName in DEFAULT_KEYS.keys():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in DEFAULT_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
	for action: StringName in LOGICAL_KEYS.keys():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in LOGICAL_KEYS[action]:
			var event := InputEventKey.new()
			event.keycode = keycode
			InputMap.action_add_event(action, event)

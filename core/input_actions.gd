class_name InputActions
extends RefCounted
## Actions clavier par défaut. Les touches sont physiques : WASD correspond à ZQSD sur un clavier AZERTY.

const MAP_PAN_LEFT := &"map_pan_left"
const MAP_PAN_RIGHT := &"map_pan_right"
const MAP_PAN_UP := &"map_pan_up"
const MAP_PAN_DOWN := &"map_pan_down"
const MAP_ZOOM_IN := &"map_zoom_in"
const MAP_ZOOM_OUT := &"map_zoom_out"

const DEFAULT_KEYS := {
	MAP_PAN_LEFT: [KEY_A, KEY_LEFT],
	MAP_PAN_RIGHT: [KEY_D, KEY_RIGHT],
	MAP_PAN_UP: [KEY_W, KEY_UP],
	MAP_PAN_DOWN: [KEY_S, KEY_DOWN],
	MAP_ZOOM_IN: [KEY_PAGEUP],
	MAP_ZOOM_OUT: [KEY_PAGEDOWN],
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

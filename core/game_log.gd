class_name GameLog
extends RefCounted
## Journal centralisé : chaque message est préfixé par le système qui l'émet.


static func info(source: String, message: String) -> void:
	print("[%s] %s" % [source, message])


static func warn(source: String, message: String) -> void:
	push_warning("[%s] %s" % [source, message])


static func error(source: String, message: String) -> void:
	push_error("[%s] %s" % [source, message])

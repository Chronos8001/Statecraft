class_name LaunchAiPlanCommand
extends Command
## Lance un plan national d'IA : dépense mensuelle pendant quelques années, adoption plus rapide, niveau visé plus haut.


func _init(p_issuer: StringName = &"") -> void:
	issuer = p_issuer


func get_type() -> StringName:
	return &"launch_ai_plan"


func refusal_reason(state: SimState) -> String:
	return AiRaceSystem.plan_refusal(state, str(issuer))


func can_execute(state: SimState) -> bool:
	return refusal_reason(state).is_empty()


func execute(state: SimState) -> void:
	AiRaceSystem.launch_plan(state, str(issuer))

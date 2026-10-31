extends GutTest
## Tension mondiale et revendications territoriales.

const DEFINES_PATH := "res://data/defines.json"
const CURRENCIES := {"usd": {"code": "USD", "usd_rate": 1.0, "policy_rate": 3.0, "inflation_target": 2.0, "peg": "",
	"independent": true, "issuer": ""}}
const START := {"treaties": {"list": []}, "no_embassy": {"list": []}, "recognition": {},
	"security_council": {"permanent": [], "elected": {}}, "sanctions": {"list": []}, "aid": {"list": []},
	"claims": {"list": [["AAA", "BBB", [2]], ["CCC", "AAA", []]]}}
const PROVINCES := {
	"1": {"owner": "AAA", "neighbors": [2, 3]}, "2": {"owner": "BBB", "neighbors": [1]},
	"3": {"owner": "BBB", "neighbors": [1, 4]}, "4": {"owner": "BBB", "neighbors": [3]},
	"5": {"owner": "AAA", "neighbors": []},
}
const GROUPS := {"military": {"influence": 2.0, "affinity": {},
	"reactions": {"unemployment": 0.0, "inflation": 0.0, "growth": 0.0, "blackout": 0.0, "public_ownership": 0.0}}}

var _defines: Dictionary


func before_all() -> void:
	_defines = JSON.parse_string(FileAccess.get_file_as_string(DEFINES_PATH))


func _country(relations: Dictionary) -> Dictionary:
	return {"population": 1000000, "currency": "usd", "relations": relations, "regime": "parliamentary_republic",
		"economy": {"gdp_billion_usd": 100.0, "debt_to_gdp": 0.5, "growth": 2.0, "inflation": 2.0, "unemployment": 5.0,
			"budget_balance": 0.0, "rating": "A", "foreign_debt_share": 0.0, "sectors": {"services": 1.0}},
		"society": {"groups": {"military": 1.0}, "stability": 50.0, "corruption": 30.0, "democracy": 8.0, "approval": 50.0}}


func _world() -> SimState:
	var state := SimState.new()
	state.setup(6, GameDate.new(), &"AAA")
	WorldSetup.populate(state, {"AAA": _country({"BBB": 0}), "BBB": _country({"AAA": 0}), "CCC": _country({})},
		CURRENCIES, _defines["economy"], {}, {}, {}, {}, {}, {},
		{"groups": GROUPS, "regimes": {"parliamentary_republic": {"democratic": true, "group_influence": {}}},
			"ideologies": {}, "settings": _defines["society"]},
		{"parties": {}, "characters": {}, "provinces": {"AAA": [["1", 1, 1.0], ["5", 1, 1.0]]}, "laws": {},
			"constitution": {}, "crises": {}, "settings": _defines["politics"]},
		{"settings": _defines["diplomacy"], "treaties": {}, "start": START, "organizations": {}, "organization_rules": {},
			"sanctions": {}, "aid": {}})
	state.energy_definitions["provinces"] = PROVINCES
	return state


func test_start_claims_and_tension() -> void:
	var state := _world()
	assert_eq(state.diplomacy.world_tension, 55.0)
	assert_eq(TensionSystem.claims_between(state, "AAA", "BBB").size(), 1)
	var whole: Dictionary = state.diplomacy.claims[TensionSystem.claims_between(state, "AAA", "CCC")[0]]
	assert_eq(TensionSystem.claimed_provinces(state, whole), ["1", "5"], "revendication sur tout le pays")
	TensionSystem.new().on_month(state)
	assert_lt(state.diplomacy.world_tension, 55.0, "retour lent vers le niveau de fond")


func test_press_and_renounce() -> void:
	var state := _world()
	var claim_id := TensionSystem.claims_between(state, "AAA", "BBB")[0]
	ClaimCommand.new(&"AAA", ClaimCommand.PRESS, claim_id).execute(state)
	assert_eq(state.diplomacy.world_tension, 57.0)
	assert_eq(state.diplomacy.relation("AAA", "BBB"), -10.0)
	assert_gt(float(state.get_country("AAA").society.bonuses["military"]), 0.0, "les nationalistes applaudissent")
	assert_eq(ClaimCommand.new(&"AAA", ClaimCommand.PRESS, claim_id).refusal_reason(state), "DIPLOMACY_COOLDOWN")
	ClaimCommand.new(&"AAA", ClaimCommand.RENOUNCE, claim_id).execute(state)
	assert_true(TensionSystem.claims_between(state, "AAA", "BBB").is_empty())
	assert_eq(state.diplomacy.relation("AAA", "BBB"), 10.0)
	assert_eq(ClaimCommand.new(&"BBB", ClaimCommand.RENOUNCE, 1).refusal_reason(state), "DIPLOMACY_INVALID",
		"on ne renonce qu'à ses propres revendications")


func test_new_claims_need_adjacency_and_tension() -> void:
	var state := _world()
	assert_eq(ClaimCommand.new(&"AAA", ClaimCommand.ADD, -1, "BBB", "4").refusal_reason(state), "CLAIM_NOT_ADJACENT")
	assert_eq(ClaimCommand.new(&"AAA", ClaimCommand.ADD, -1, "BBB", "2").refusal_reason(state), "DIPLOMACY_ALREADY")
	var command := ClaimCommand.new(&"AAA", ClaimCommand.ADD, -1, "BBB", "3")
	assert_eq(command.refusal_reason(state), "")
	state.diplomacy.world_tension = 20.0
	assert_eq(command.refusal_reason(state), "TENSION_TOO_LOW")
	assert_eq(DiplomaticActionCommand.new(&"AAA", "BBB", "ultimatum").refusal_reason(state), "TENSION_TOO_LOW")
	state.diplomacy.world_tension = 60.0
	command.execute(state)
	assert_true(TensionSystem.is_claimed_by(state, "AAA", "3"))


func test_thresholds_are_announced() -> void:
	var state := _world()
	state.diplomacy.world_tension = 39.0
	TensionSystem.add_event(state, "ultimatum")
	var unlocked: Array = state.events.filter(func(event: Dictionary) -> bool:
		return event["type"] == TensionSystem.EVENT_THRESHOLD and event["action"] == "ultimatum")
	assert_eq(unlocked.size(), 1)
	assert_true(bool(unlocked[0]["unlocked"]))

extends GutTest

const ClockScript := preload("res://core/game_clock.gd")
const HOURS_IN_JANUARY := 31 * 24


class CountingSystem extends SimSystem:
	var calls: Dictionary = {"hour": 0, "day": 0, "week": 0, "month": 0, "year": 0}
	var log: Array = []
	var id: StringName
	var priority: int

	func _init(p_id: StringName = &"counter", p_priority: int = 0) -> void:
		id = p_id
		priority = p_priority

	func get_id() -> StringName:
		return id

	func get_priority() -> int:
		return priority

	func get_periods() -> Array[StringName]:
		return [HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY]

	func on_hour(_state: SimState) -> void:
		calls["hour"] += 1

	func on_day(_state: SimState) -> void:
		calls["day"] += 1
		log.append(id)

	func on_week(_state: SimState) -> void:
		calls["week"] += 1

	func on_month(state: SimState) -> void:
		calls["month"] += 1
		log.append("%s:%d-%02d-%02d" % [id, state.date.year, state.date.month, state.date.day])

	func on_year(_state: SimState) -> void:
		calls["year"] += 1


func _state() -> SimState:
	var state := SimState.new()
	state.setup(1, GameDate.new(2026, 1, 1, 0))
	return state


func test_scheduler_calls_each_period() -> void:
	var scheduler := SimScheduler.new()
	var system := CountingSystem.new()
	scheduler.add_system(system)
	var state := _state()
	for i: int in HOURS_IN_JANUARY:
		scheduler.tick(state)
	assert_eq(state.date.format_iso(), "2026-02-01 00:00")
	assert_eq(system.calls["hour"], HOURS_IN_JANUARY)
	assert_eq(system.calls["day"], 31)
	assert_eq(system.calls["week"], 4, "lundis 5, 12, 19 et 26 janvier")
	assert_eq(system.calls["month"], 1)
	assert_eq(system.log.back(), "counter:2026-02-01", "le système mensuel voit le 1er février")


func test_new_year_triggers_yearly_systems() -> void:
	var scheduler := SimScheduler.new()
	var system := CountingSystem.new()
	scheduler.add_system(system)
	var state := SimState.new()
	state.setup(1, GameDate.new(2026, 12, 31, 23))
	assert_eq(scheduler.tick(state) & GameDate.CHANGED_YEAR, GameDate.CHANGED_YEAR)
	assert_eq(system.calls["year"], 1)
	assert_eq(system.calls["month"], 1)


func test_scheduler_order_is_deterministic() -> void:
	var scheduler := SimScheduler.new()
	var late := CountingSystem.new(&"late", 10)
	var first := CountingSystem.new(&"first", 0)
	var second := CountingSystem.new(&"second", 0)
	scheduler.add_system(late)
	scheduler.add_system(first)
	scheduler.add_system(second)
	var ids: Array = scheduler.get_systems(SimSystem.DAILY).map(func(s: SimSystem) -> StringName: return s.get_id())
	assert_eq(ids, [&"first", &"second", &"late"])
	scheduler.remove_system(second)
	assert_eq(scheduler.get_systems(SimSystem.DAILY).size(), 2)


func test_clock_converts_real_time_into_ticks() -> void:
	var clock: Node = autofree(ClockScript.new())
	clock.reset()
	clock.set_speed(2)
	var hours_per_second: float = clock.get_hours_per_second()
	assert_eq(clock.consume(1.0), mini(int(hours_per_second), int(DataLoader.get_define("time.max_ticks_per_frame"))))
	assert_eq(clock.consume(0.0), 0)


func test_clock_caps_ticks_per_frame() -> void:
	var clock: Node = autofree(ClockScript.new())
	clock.reset()
	clock.set_speed(clock.get_speed_count())
	var max_ticks := int(DataLoader.get_define("time.max_ticks_per_frame"))
	assert_eq(clock.consume(10.0), max_ticks)
	assert_lte(clock.consume(0.0), 1, "le retard est abandonné")


func test_clock_speed_and_pause() -> void:
	var clock: Node = autofree(ClockScript.new())
	clock.reset()
	assert_true(clock.is_paused, "une partie commence en pause")
	clock.set_speed(99)
	assert_eq(clock.speed, clock.get_speed_count())
	clock.set_speed(-3)
	assert_eq(clock.speed, 1)
	clock.toggle_pause()
	assert_false(clock.is_paused)


func test_long_date_format() -> void:
	var date := GameDate.new(2026, 1, 1, 8)
	assert_eq(DateFormat.long_date(date, "janvier", "fr"), "1er janvier 2026 · 08:00")
	assert_eq(DateFormat.long_date(GameDate.new(2026, 3, 14, 23), "mars", "fr"), "14 mars 2026 · 23:00")
	assert_eq(DateFormat.long_date(date, "January", "en"), "January 1, 2026 · 08:00")

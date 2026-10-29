extends GutTest


func test_leap_years() -> void:
	assert_true(GameDate.is_leap_year(2028))
	assert_false(GameDate.is_leap_year(2026))
	assert_false(GameDate.is_leap_year(2100))
	assert_true(GameDate.is_leap_year(2000))
	assert_eq(GameDate.days_in_month(2028, 2), 29)
	assert_eq(GameDate.days_in_month(2026, 2), 28)


func test_january_first_2026_is_a_thursday() -> void:
	assert_eq(GameDate.new(2026, 1, 1).day_of_week(), 3)


func test_advance_within_day() -> void:
	var date := GameDate.new(2026, 1, 1, 0)
	assert_eq(date.advance_hour(), 0)
	assert_eq(date.hour, 1)


func test_advance_to_next_day() -> void:
	var date := GameDate.new(2026, 1, 1, 23)
	assert_eq(date.advance_hour(), GameDate.CHANGED_DAY)
	assert_eq(date.format_iso(), "2026-01-02 00:00")


func test_monday_starts_a_new_week() -> void:
	var date := GameDate.new(2026, 1, 4, 23)
	assert_eq(date.advance_hour(), GameDate.CHANGED_DAY | GameDate.CHANGED_WEEK)


func test_end_of_month_and_year() -> void:
	var date := GameDate.new(2026, 12, 31, 23)
	var flags := date.advance_hour()
	assert_true(flags & GameDate.CHANGED_MONTH != 0)
	assert_true(flags & GameDate.CHANGED_YEAR != 0)
	assert_eq(date.format_iso(), "2027-01-01 00:00")


func test_february_in_leap_year() -> void:
	var date := GameDate.new(2028, 2, 28, 23)
	date.advance_hour()
	assert_eq(date.format_iso(), "2028-02-29 00:00")


func test_compare_copy_and_dict() -> void:
	var a := GameDate.new(2026, 5, 10, 12)
	var b := a.copy()
	assert_eq(a.compare(b), 0)
	b.advance_hour()
	assert_eq(a.compare(b), -1)
	assert_eq(b.compare(a), 1)
	assert_eq(GameDate.from_dict(a.to_dict()).format_iso(), a.format_iso())
	assert_false(GameDate.new(2026, 2, 30).is_valid())

extends GutTest
## Nombres à virgule selon la langue.


func test_decimal_french_and_english() -> void:
	assert_eq(NumberFormat.decimal(2.5, 1, "fr"), "2,5")
	assert_eq(NumberFormat.decimal(2.5, 1, "en"), "2.5")
	assert_eq(NumberFormat.decimal(1234.567, 2, "fr"), "1" + NumberFormat.NO_BREAK_SPACE + "234,57")
	assert_eq(NumberFormat.decimal(1234.567, 2, "en"), "1,234.57")


func test_decimal_rounding_and_sign() -> void:
	assert_eq(NumberFormat.decimal(0.06, 1, "en"), "0.1")
	assert_eq(NumberFormat.decimal(-3.25, 1, "fr"), "-3,3")
	assert_eq(NumberFormat.decimal(-0.01, 1, "en"), "0.0", "pas de « -0.0 »")
	assert_eq(NumberFormat.decimal(1.96, 1, "en"), "2.0", "retenue")
	assert_eq(NumberFormat.decimal(7.0, 0, "en"), "7")

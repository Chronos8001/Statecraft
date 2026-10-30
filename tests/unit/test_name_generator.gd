extends GutTest
## Générateur de noms de personnages et de partis.

const SEED := 42
const CULTURES := {
	"slavic": {
		"name_order": "given_first", "party_style": "local", "female_share": 0.0,
		"male_names": ["Ivan", "Oleg"], "female_names": ["Olga"],
		"family_names": ["Volkov", "Orlov"], "female_family_names": ["Volkova", "Orlova"],
	},
	"iberian": {
		"name_order": "given_first", "party_style": "translated", "female_share": 1.0, "family_name_count": 2,
		"male_names": ["Juan"], "female_names": ["Ana"], "family_names": ["Ruiz", "Vega", "Soto"],
	},
}
const STYLES := {
	"local": {"stopwords": ["de", "la"], "names": {"liberal": ["Union de la Liberté"], "national": ["Front Patriote"]}},
	"translated": {"stopwords": ["of"], "names": {"liberal": [{"en": "Party of Reform", "fr": "Parti de la réforme"}]}},
}
const IDEOLOGIES := {
	"liberal": {"party_group": "liberal", "color": "#F2C230"},
	"nationalist": {"party_group": "national", "color": "#5A3A1E"},
	"theocratic": {"party_group": "religious", "color": "#2E6B4F"},
}
const TRAITS := {
	"cautious": {"group": "temperament"}, "bold": {"group": "temperament"},
	"technocrat": {"group": "style"}, "europhile": {"group": "orientation", "random": false},
}
const SETTINGS := {
	"reference_year": 2026, "min_age": 40, "max_age": 60, "default_female_share": 0.5, "trait_chance": 1.0,
	"min_skill": 3, "max_skill": 6, "skills": ["administration", "economy"],
	"party_group_fallbacks": {"religious": "national", "national": "liberal"}, "party_color_spread": 0.2,
}


func _generator(seed_value: int = SEED) -> NameGenerator:
	return NameGenerator.new(CULTURES, STYLES, IDEOLOGIES, TRAITS, SETTINGS, seed_value)


func test_same_seed_gives_same_character() -> void:
	var first := _generator().generate_character("RUS", "slavic", "male", 0, "liberal")
	var second := _generator().generate_character("RUS", "slavic", "male", 0, "liberal")
	assert_eq(first, second)


func test_female_family_name_form() -> void:
	var character := _generator().generate_name("slavic", "female")
	assert_eq(character["first_name"], "Olga")
	assert_true(["Volkova", "Orlova"].has(character["last_name"]), character["last_name"])


func test_double_family_name() -> void:
	var parts: PackedStringArray = str(_generator().generate_name("iberian", "male")["last_name"]).split(" ")
	assert_eq(parts.size(), 2)
	assert_ne(parts[0], parts[1], "deux noms différents")


func test_gender_follows_female_share() -> void:
	var generator := _generator()
	assert_eq(generator.pick_gender("slavic"), "male")
	assert_eq(generator.pick_gender("iberian"), "female")


func test_generated_character_fields() -> void:
	var character := _generator().generate_character("RUS", "slavic", "male", 0, "nationalist")
	var age := 2026 - int(character["birth_year"])
	assert_between(age, 40, 60)
	assert_eq(character["country"], "RUS")
	assert_eq(character["culture"], "slavic")
	assert_eq(character["ideology"], "nationalist")
	assert_eq((character["traits"] as Array).size(), 2, "un trait par groupe tirable")
	assert_false((character["traits"] as Array).has("europhile"), "orientation jamais tirée")
	for skill: String in ["administration", "economy"]:
		assert_between(int(character["skills"][skill]), 3, 6, skill)


func test_given_birth_year_is_kept() -> void:
	assert_eq(_generator().generate_character("RUS", "slavic", "male", 1952, "liberal")["birth_year"], 1952)


func test_party_name_avoids_taken_names() -> void:
	var party := _generator().generate_party_name("slavic", "liberal")
	assert_eq(party, {"name": "Union de la Liberté", "abbreviation": "UL"})
	assert_eq(_generator().generate_party_name("slavic", "liberal", ["Union de la Liberté"]), {})


func test_party_name_falls_back_to_other_group() -> void:
	assert_eq(_generator().generate_party_name("slavic", "theocratic")["name"], "Front Patriote")
	assert_eq(_generator().generate_party_name("iberian", "theocratic")["abbreviation"], "PR",
		"repli religieux → national → libéral, sigle tiré de l'anglais")


func test_party_color_stays_close_to_ideology() -> void:
	var color := Color.html(_generator().party_color("liberal"))
	var base := Color.html("#F2C230")
	assert_almost_eq(color.h, base.h, 0.05, "même teinte")


func test_abbreviation_skips_stopwords_and_elisions() -> void:
	assert_eq(NameGenerator.abbreviate("Parti de l'unité nationale", ["de"]), "PUN")
	assert_eq(NameGenerator.abbreviate("Christlich-Bürgerliche Union"), "CBU")
	assert_eq(NameGenerator.abbreviate({"en": "National Unity Party", "fr": "Parti de l'unité nationale"}), "NUP")


func test_full_name_order() -> void:
	var cultures := {"chinese": {"name_order": "family_first"}}
	assert_eq(NameGenerator.full_name({"first_name": "Jianguo", "last_name": "Wei", "culture": "chinese"}, cultures),
		"Wei Jianguo")
	assert_eq(NameGenerator.full_name({"first_name": "Ana", "last_name": "Ruiz"}, cultures), "Ana Ruiz")
	assert_eq(NameGenerator.full_name({"first_name": "Akihiro", "last_name": ""}, cultures), "Akihiro")
	assert_eq(NameGenerator.full_name({}, cultures), "")

class_name AllianceMapMode
extends MapMode
## Couleur de la première alliance (types listés dans « organization_kinds ») dont le pays est membre.


func alliance_of(country: Dictionary, context: MapModeContext) -> String:
	var kinds: Array = definition.get("organization_kinds", [])
	for organization_id: Variant in country.get("organizations", []):
		var organization: Dictionary = context.organizations.get(str(organization_id), {})
		if kinds.has(organization.get("kind", "")):
			return str(organization_id)
	return ""


func compute_colors(context: MapModeContext) -> PackedColorArray:
	var none_color := Color.html(str(definition.get("none_color", "#000000")))
	return _color_provinces(context, func(province: Dictionary) -> Color:
		var owner := context.owner_of(province)
		if owner.is_empty():
			return context.unowned_color
		if not owner.has("organizations"):
			return context.no_data_color
		var alliance := alliance_of(owner, context)
		if alliance.is_empty():
			return none_color
		return Color.html(str((context.organizations[alliance] as Dictionary).get("color", "#000000"))))


func get_legend(context: MapModeContext) -> Array[Dictionary]:
	var kinds: Array = definition.get("organization_kinds", [])
	var legend: Array[Dictionary] = []
	for organization_id: String in context.organizations.keys():
		var organization: Dictionary = context.organizations[organization_id]
		if kinds.has(organization.get("kind", "")) and organization.has("color"):
			var label := Localization.pick_text(organization.get("name", organization_id))
			legend.append(_entry(Color.html(str(organization["color"])), label))
	legend.append(_entry(Color.html(str(definition.get("none_color", "#000000"))), "LEGEND_NONE"))
	legend.append(_entry(context.no_data_color, "LEGEND_NO_DATA"))
	return legend

extends Control
## Écran de jeu : charge la carte dans un thread puis l'affiche. Sans pays joué, commence par
## la sélection du pays (temps arrêté). Échap revient à l'écran titre.

const SOURCE := "GameScreen"
const TITLE_SCENE := "res://ui/title/title_screen.tscn"
const DEGREES_PER_TURN := 360.0
const DEGREES_HALF_TURN := 180.0
const BYTES_PER_MEGABYTE := 1048576.0
const DEFAULT_MAP_MODE := "political"
## Décalage (en pixels de carte) entre les flottes d'une même mer.
const FLEET_STACK_OFFSET := Vector2(14.0, 10.0)
const LIVE_MAP_MODES := ["trade", "stability", "support", "vote", "ideology", "unrest", "relations", "influence", "claims",
	"military_power", "military_control", "wars", "sea_control"]

var _thread: Thread
var _load_started_ms: int = 0
var _map_modes: MapModeRegistry
var _mode_context: MapModeContext
var _current_mode_id: String = DEFAULT_MAP_MODE
var _notification_timer: SceneTreeTimer
## Interface militaire remplaçable (mods, DLC) et son panneau Armée.
var _military_ui: MilitaryUI = MilitaryUI.new()
var _military_panel: InfoPanel
## Groupe d'armées sélectionné (-1 : aucun) : un clic droit sur la carte l'envoie dans la province visée.
var _selected_group: int = -1
## Flotte sélectionnée (-1 : aucune) : un clic droit sur une mer l'y envoie.
var _selected_fleet: int = -1

@onready var _map_view: MapView = %MapView
@onready var _loading_label: Label = %LoadingLabel
@onready var _debug_label: Label = %DebugLabel
@onready var _info_panel: ProvinceInfoPanel = %ProvinceInfoPanel
@onready var _country_panel: CountryInfoPanel = %CountryInfoPanel
@onready var _top_bar: TopBar = %TopBar
@onready var _notification_label: Label = %NotificationLabel

@onready var _mode_bar: MapModeBar = %MapModeBar
@onready var _legend: MapLegend = %MapLegend
@onready var _selection_panel: CountrySelectionPanel = %CountrySelectionPanel
@onready var _economy_panel: EconomyPanel = %EconomyPanel
@onready var _budget_panel: BudgetPanel = %BudgetPanel
@onready var _markets_panel: MarketsPanel = %MarketsPanel
@onready var _trade_panel: TradePanel = %TradePanel
@onready var _energy_panel: EnergyPanel = %EnergyPanel
@onready var _investment_panel: InvestmentPanel = %InvestmentPanel
@onready var _society_panel: SocietyPanel = %SocietyPanel
@onready var _politics_panel: PoliticsPanel = %PoliticsPanel
@onready var _laws_panel: LawsPanel = %LawsPanel
@onready var _government_panel: GovernmentPanel = %GovernmentPanel
@onready var _diplomacy_panel: DiplomacyPanel = %DiplomacyPanel
@onready var _world_panel: WorldPanel = %WorldPanel


func _ready() -> void:
	var map_info: Dictionary = DataLoader.get_category("map").get("map", {})
	var image_path := str(map_info.get("provinces_image", ""))
	_loading_label.text = "MAP_LOADING"
	_load_started_ms = Time.get_ticks_msec()
	_map_view.province_clicked.connect(_on_province_clicked)
	_map_view.province_double_clicked.connect(_show_province)
	_map_view.army_group_clicked.connect(_on_army_group_clicked)
	_map_view.fleet_clicked.connect(_on_fleet_clicked)
	_map_view.province_right_clicked.connect(_on_province_right_clicked)
	EventBus.day_passed.connect(func(_date: GameDate) -> void: _refresh_armies())
	EventBus.command_executed.connect(func(_command: Command) -> void: _refresh_armies())
	_info_panel.closed.connect(func() -> void: _map_view.set_selected_province(MapView.NO_SELECTION))
	_country_panel.closed.connect(func() -> void: _map_view.set_selected_country(""))
	_map_modes = MapModeRegistry.from_definitions(DataLoader.get_category("map_modes"))
	_mode_context = MapModeContext.from_game_data()
	_mode_bar.set_modes(_map_modes.modes)
	_mode_bar.mode_selected.connect(set_map_mode)
	_mode_bar.visible = false
	_legend.visible = false
	_selection_panel.visible = false
	_selection_panel.country_selected.connect(_on_country_selected)
	_selection_panel.play_requested.connect(_on_play_requested)
	_top_bar.economy_requested.connect(_economy_panel.toggle)
	_top_bar.budget_requested.connect(_budget_panel.toggle)
	_top_bar.markets_requested.connect(_markets_panel.toggle)
	_top_bar.trade_requested.connect(_trade_panel.toggle)
	_top_bar.energy_requested.connect(_energy_panel.toggle)
	_top_bar.investment_requested.connect(_investment_panel.toggle)
	_top_bar.society_requested.connect(_society_panel.toggle)
	_top_bar.politics_requested.connect(_politics_panel.toggle)
	_top_bar.laws_requested.connect(_laws_panel.toggle)
	_top_bar.government_requested.connect(_government_panel.toggle)
	_military_panel = _military_ui.create_panel()
	if _military_panel is MilitaryPanel:
		(_military_panel as MilitaryPanel).military_ui = _military_ui
	_government_panel.add_sibling(_military_panel)
	if _military_panel.has_signal("group_focus_requested"):
		_military_panel.connect("group_focus_requested", _focus_army_group)
	if _military_panel.has_signal("fleet_focus_requested"):
		_military_panel.connect("fleet_focus_requested", _focus_fleet)
	if _military_panel.has_signal("province_focus_requested"):
		_military_panel.connect("province_focus_requested", func(province_id: String) -> void:
			_map_view.focus_on(_province_center(DataLoader.get_category("provinces"), province_id),
				maxf(_map_view.camera.zoom, float(DataLoader.get_define("camera.capital_zoom")))))
	_top_bar.military_requested.connect(func() -> void: _military_panel.call("toggle"))
	_top_bar.world_requested.connect(_world_panel.toggle)
	_country_panel.diplomacy_requested.connect(func(tag: String) -> void:
		_country_panel.close()
		_diplomacy_panel.show_country(tag))
	EventBus.sim_event_raised.connect(_on_sim_event)
	EventBus.month_passed.connect(_on_month_passed)
	EventBus.command_executed.connect(func(_command: Command) -> void: _refresh_live_map_mode())
	EventBus.year_passed.connect(_on_year_passed)
	_thread = Thread.new()
	_thread.start(func() -> ProvinceMapData: return ProvinceMapData.from_png_file(image_path))


func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		_finish_loading()
	_update_debug()


func _unhandled_input(event: InputEvent) -> void:
	if _is_selecting():
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			get_tree().change_scene_to_file(TITLE_SCENE)
		return
	if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		get_viewport().set_input_as_handled()
		_cycle_map_mode(-1 if event.is_action_pressed("ui_focus_prev") else 1)
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		var panels: Array[InfoPanel] = [_info_panel, _country_panel, _economy_panel, _budget_panel, _markets_panel,
			_trade_panel, _energy_panel, _investment_panel, _society_panel,
			_politics_panel, _laws_panel, _government_panel, _diplomacy_panel,
			_world_panel, _military_panel]
		if panels.any(func(panel: InfoPanel) -> bool: return panel.visible):
			for panel: InfoPanel in panels:
				panel.close()
		else:
			get_tree().change_scene_to_file(TITLE_SCENE)


func _exit_tree() -> void:
	GameClock.set_running(false)
	GameClock.set_paused(true)
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _finish_loading() -> void:
	var data: ProvinceMapData = _thread.wait_to_finish()
	_thread = null
	if data == null:
		GameLog.error(SOURCE, "Impossible de charger l'image des provinces.")
		_loading_label.text = "MAP_LOAD_ERROR"
		return
	_map_view.setup(data, _mode_context.new_colors())
	set_map_mode(_current_mode_id)
	_loading_label.visible = false
	if GameState.sim.player_tag.is_empty():
		_enter_selection()
	else:
		_start_playing()
	GameLog.info(SOURCE, "Carte %d × %d chargée en %d ms." % [data.width, data.height,
		Time.get_ticks_msec() - _load_started_ms])
	# Les textures partent vers la carte graphique au rendu suivant.
	await get_tree().process_frame
	await get_tree().process_frame
	GameLog.info(SOURCE, "Mémoire graphique des textures : %d Mo." % roundi(
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / BYTES_PER_MEGABYTE))


func _is_selecting() -> bool:
	return _selection_panel.visible


## Sélection du pays : le temps reste arrêté, seuls la carte et les panneaux de choix sont affichés.
func _enter_selection() -> void:
	GameClock.set_running(false)
	_top_bar.visible = false
	_mode_bar.visible = false
	_legend.visible = false
	_debug_label.visible = false
	_selection_panel.visible = true


func _start_playing() -> void:
	_selection_panel.visible = false
	_debug_label.visible = true
	_mode_bar.visible = true
	set_map_mode(_current_mode_id)
	_top_bar.visible = true
	_top_bar.refresh()
	_selected_group = -1
	_selected_fleet = -1
	_refresh_armies()
	GameClock.set_running(true)


## Démarre la partie sur le pays choisi, caméra centrée sur sa capitale.
func _on_play_requested(tag: String) -> void:
	GameState.new_game(GameState.sim.game_seed, StringName(tag))
	_map_view.set_selected_country("")
	_focus_capital(tag, float(DataLoader.get_define("camera.capital_zoom")))
	_start_playing()


## Pays choisi dans la liste ou sur la carte : mis en évidence ; depuis la liste, la carte se centre dessus.
func _on_country_selected(tag: String, from_list: bool) -> void:
	_map_view.set_selected_country(tag)
	if from_list and _map_view.camera != null:
		_focus_capital(tag, _map_view.camera.zoom)


func _focus_capital(tag: String, zoom: float) -> void:
	var capital := int(DataLoader.get_entry("countries", tag).get("capital", 0))
	var center: Array = DataLoader.get_entry("provinces", str(capital)).get("center", [])
	if center.size() >= 2:
		_map_view.focus_on(Vector2(float(center[0]), float(center[1])), zoom)


## Les modes qui dépendent de la partie (commerce) suivent les décisions et les mois.
func _refresh_live_map_mode() -> void:
	if LIVE_MAP_MODES.has(_current_mode_id):
		set_map_mode(_current_mode_id)


func _on_month_passed(date: GameDate) -> void:
	_refresh_live_map_mode()
	if date.month != 1:
		_notify(tr("NOTIFY_NEW_MONTH") % [tr(DateFormat.month_key(date.month)), date.year])


## Guerres : déclarations, entrées en guerre, paix, appels aux armes (fenêtre de réponse pour le joueur).
## Vrai si l'événement a été traité.
func _on_war_event(event: Dictionary) -> bool:
	var state := GameState.sim
	var player := str(state.player_tag)
	var tag := str(event.get("tag", ""))
	var target := str(event.get("target", ""))
	match event.get("type"):
		WarSystem.EVENT_DECLARED:
			if not bool(event.get("civil", false)):
				_notify(tr("NOTIFY_WAR_DECLARED") % [MilitaryUI.side_name(state, tag), MilitaryUI.side_name(state, target)])
		WarSystem.EVENT_JOINED:
			_notify(tr("NOTIFY_WAR_JOINED") % [MilitaryUI.side_name(state, tag),
				MilitaryUI.side_name(state, str(event.get("leader", "")))])
		WarSystem.EVENT_ENDED:
			if bool(event.get("civil", false)):
				_notify(tr("NOTIFY_CIVIL_WAR_ENDED") % MilitaryUI.side_name(state, target))
			else:
				_notify(tr("NOTIFY_WAR_ENDED") % [MilitaryUI.side_name(state, tag), MilitaryUI.side_name(state, target)])
		WarSystem.EVENT_CALL:
			if tag == player:
				_show_call_to_arms(int(event.get("war", -1)), str(event.get("caller", "")))
		WarSystem.EVENT_CALL_REFUSED:
			if str(event.get("caller", "")) == player:
				_notify(tr("NOTIFY_CALL_REFUSED") % MilitaryUI.side_name(state, tag))
		WarSystem.EVENT_PEACE_REFUSED:
			if tag == player:
				_notify(tr("NOTIFY_WHITE_PEACE_REFUSED") % MilitaryUI.side_name(state, target))
		WarSystem.EVENT_PEACE_OFFER:
			if tag == player:
				_show_peace_offer(int(event.get("war", -1)), str(event.get("from", "")))
		WarSystem.EVENT_REBELS_WON:
			_notify(tr("NOTIFY_REBELS_WON") % MilitaryUI.side_name(state, tag))
		WarResolver.EVENT_PROVINCE_TAKEN:
			var previous := str(event.get("previous", ""))
			if tag == player or previous == player:
				var province := tr(str(DataLoader.get_entry("provinces", str(event.get("province", ""))).get("name_key", "")))
				_notify(tr("NOTIFY_PROVINCE_TAKEN" if tag == player else "NOTIFY_PROVINCE_LOST")
					% [province, MilitaryUI.side_name(state, previous if tag == player else tag)])
		_:
			return false
	return true


## Fenêtre d'appel aux armes : rejoindre ou refuser ; fermée sans réponse, l'appel reste dans le panneau Armée.
func _show_call_to_arms(war_id: int, caller: String) -> void:
	var state := GameState.sim
	var war: War = state.wars.get(war_id)
	if war == null:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("CALL_TO_ARMS_TITLE")
	dialog.dialog_text = tr("CALL_TO_ARMS_TEXT") % [MilitaryUI.side_name(state, caller), MilitaryUI.war_name(state, war),
		int((WarSystem.settings_of(state).get("call_to_arms", {}) as Dictionary).get("days", 0))]
	dialog.dialog_autowrap = true
	dialog.ok_button_text = tr("MILITARY_CALL_ACCEPT")
	dialog.cancel_button_text = tr("MILITARY_CALL_LATER")
	var refuse := dialog.add_button(tr("MILITARY_CALL_REFUSE"), true, "refuse")
	refuse.focus_mode = Control.FOCUS_NONE
	dialog.confirmed.connect(func() -> void: _submit_now(AnswerCallToArmsCommand.new(state.player_tag, war_id, true)))
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"refuse":
			_submit_now(AnswerCallToArmsCommand.new(state.player_tag, war_id, false))
			dialog.hide())
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 0))


## Paix blanche proposée par l'ennemi : accepter, refuser, ou répondre plus tard depuis le panneau Armée.
func _show_peace_offer(war_id: int, from: String) -> void:
	var state := GameState.sim
	var war: War = state.wars.get(war_id)
	if war == null:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("PEACE_OFFER_TITLE")
	dialog.dialog_text = tr("PEACE_OFFER_TEXT") % [MilitaryUI.side_name(state, from), MilitaryUI.war_name(state, war),
		int((state.military_settings.get("ai", {}) as Dictionary).get("peace", {}).get("player_days", 0))]
	dialog.dialog_autowrap = true
	dialog.ok_button_text = tr("MILITARY_PEACE_ACCEPT")
	dialog.cancel_button_text = tr("MILITARY_CALL_LATER")
	var refuse := dialog.add_button(tr("MILITARY_PEACE_REFUSE"), true, "refuse")
	refuse.focus_mode = Control.FOCUS_NONE
	dialog.confirmed.connect(func() -> void: _submit_now(AnswerPeaceCommand.new(state.player_tag, war_id, true)))
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"refuse":
			_submit_now(AnswerPeaceCommand.new(state.player_tag, war_id, false))
			dialog.hide())
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 0))


func _submit_now(command: Command) -> void:
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


## Événements économiques du pays joué : changement de note, défaut de paiement, FMI.
func _on_sim_event(event: Dictionary) -> void:
	# Événements mondiaux : visibles quel que soit le pays joué.
	match event.get("type"):
		ResourceSystem.EVENT_STRAIT_CLOSED:
			_notify(tr("NOTIFY_STRAIT_CLOSED") % tr(_strait_name_key(str(event.get("strait", "")))))
			return
		ResourceSystem.EVENT_STRAIT_OPENED:
			_notify(tr("NOTIFY_STRAIT_OPENED") % tr(_strait_name_key(str(event.get("strait", "")))))
			return
	if event.get("type") == CrisisSystem.EVENT_COUP or (event.get("type") == CrisisSystem.EVENT_STARTED
			and str(event.get("crisis", "")) == CrisisSystem.CIVIL_WAR):
		var country := DataLoader.get_entry("countries", str(event.get("tag", "")))
		var key := "NOTIFY_CIVIL_WAR" if event.get("type") == CrisisSystem.EVENT_STARTED \
			else "NOTIFY_COUP_SUCCESS" if bool(event.get("success", false)) else "NOTIFY_COUP_FAILED"
		_notify(tr(key) % tr(str(country.get("name_key", ""))))
		return
	if event.get("type") == TensionSystem.EVENT_THRESHOLD:
		_notify(tr("NOTIFY_TENSION_UNLOCKED" if bool(event.get("unlocked", false)) else "NOTIFY_TENSION_LOCKED")
			% tr("WORLD_ACTION_%s" % str(event.get("action", "")).to_upper()))
		return
	if event.get("type") == MobilizeCommand.EVENT_MOBILIZATION:
		var mobilizing := DataLoader.get_entry("countries", str(event.get("tag", "")))
		_notify(tr("NOTIFY_MOBILIZATION") % [tr(str(mobilizing.get("name_key", ""))),
			tr("MILITARY_MOBILIZATION_%d" % int(event.get("level", 0))).to_lower()])
		return
	if _on_war_event(event) or _on_naval_event(event):
		return
	if (event.get("type") == NavalModel.EVENT_ARRIVED or event.get("type") == NavalResolver.EVENT_DAMAGED) 			and str(event.get("tag", "")) == str(GameState.sim.player_tag):
		var fleet: Fleet = GameState.sim.fleets.get(int(event.get("fleet", -1)))
		if fleet != null:
			_notify(tr("NOTIFY_FLEET_ARRIVED" if event.get("type") == NavalModel.EVENT_ARRIVED else "NOTIFY_FLEET_DAMAGED")
				% [_military_ui.fleet_name(fleet), MilitaryUI.sea_name(str(event.get("zone", "")))])
		return
	if event.get("type") == ArmyGroupModel.EVENT_ARRIVED and str(event.get("tag", "")) == str(GameState.sim.player_tag):
		var arrived: ArmyGroup = GameState.sim.army_groups.get(int(event.get("group", -1)))
		if arrived != null:
			_notify(tr("NOTIFY_ARMY_ARRIVED") % [_military_ui.group_name(arrived), tr(str(DataLoader.get_entry(
				"provinces", arrived.province).get("name_key", "")))])
		return
	if event.get("type") == ElectionSystem.EVENT_FRAUD_DETECTED:
		var country := DataLoader.get_entry("countries", str(event.get("tag", "")))
		_notify(tr("NOTIFY_FRAUD_DETECTED") % tr(str(country.get("name_key", ""))))
		return
	if str(event.get("tag", "")) != str(GameState.sim.player_tag):
		return
	match event.get("type"):
		EconomySystem.EVENT_RATING_CHANGED:
			var key := "NOTIFY_RATING_UP" if bool(event.get("upgrade", false)) else "NOTIFY_RATING_DOWN"
			_notify(tr(key) % [event.get("old", ""), event.get("new", "")])
		EconomySystem.EVENT_DEBT_CRISIS:
			_notify(tr("NOTIFY_DEBT_CRISIS"))
		EconomySystem.EVENT_CRISIS_ENDED:
			_notify(tr("NOTIFY_CRISIS_ENDED") % event.get("new", ""))
		EconomySystem.EVENT_IMF_PROGRAM:
			_notify(tr("NOTIFY_IMF_PROGRAM"))
		EconomySystem.EVENT_IMF_ENDED:
			_notify(tr("NOTIFY_IMF_ENDED"))
		EnergySystem.EVENT_PROJECT_DONE:
			var building := DataLoader.get_entry("buildings", str(event.get("building", "")))
			var province := DataLoader.get_entry("provinces", str(event.get("province", "")))
			_notify(tr("NOTIFY_PROJECT_DONE") % [tr(str(building.get("name_key", ""))), tr(str(province.get("name_key", "")))])
		InvestmentSystem.EVENT_NATIONALIZED, InvestmentSystem.EVENT_EXPROPRIATED, InvestmentSystem.EVENT_PRIVATIZED:
			var sector := DataLoader.get_entry("economy_sectors", str(event.get("sector", "")))
			_notify(tr("NOTIFY_%s" % str(event.get("type")).to_upper()) % tr(str(sector.get("name_key", ""))))
		EnergySystem.EVENT_BLACKOUT:
			_notify(tr("NOTIFY_BLACKOUT"))
		ElectionSystem.EVENT_ELECTION:
			_notify(_election_text(event))
		ConstitutionSystem.EVENT_REFORM_ADOPTED, ConstitutionSystem.EVENT_REFORM_REJECTED:
			var reform := ConstitutionSystem.definition_of(GameState.sim, str(event.get("reform", "")))
			var key := "NOTIFY_REFORM_ADOPTED" if event.get("type") == ConstitutionSystem.EVENT_REFORM_ADOPTED \
				else "NOTIFY_REFORM_REJECTED"
			_notify(tr(key) % tr(str(reform.get("name_key", ""))))
		ConstitutionSystem.EVENT_REFERENDUM_CALLED:
			_notify(tr("NOTIFY_REFERENDUM_CALLED"))
		ConstitutionSystem.EVENT_REFERENDUM_HELD:
			var key := "NOTIFY_REFERENDUM_YES" if bool(event.get("passed", false)) else "NOTIFY_REFERENDUM_NO"
			_notify(tr(key) % NumberFormat.decimal(float(event.get("yes", 0.0)), 1, Localization.get_locale()))
		ConstitutionSystem.EVENT_EMERGENCY:
			_notify(tr("NOTIFY_EMERGENCY_ON" if bool(event.get("active", false)) else "NOTIFY_EMERGENCY_OFF"))
		ChangeLawCommand.EVENT_LAW_PASSED, ChangeLawCommand.EVENT_LAW_REJECTED:
			var law: Dictionary = (GameState.sim.politics_definitions.get("laws", {}) as Dictionary).get(str(event.get("law", "")), {})
			var key := "NOTIFY_LAW_PASSED" if event.get("type") == ChangeLawCommand.EVENT_LAW_PASSED else "NOTIFY_LAW_REJECTED"
			_notify(tr(key) % tr(str(law.get("name_key", ""))))
		GovernmentSystem.EVENT_SCANDAL, GovernmentSystem.EVENT_RESIGNATION:
			var portfolio: Dictionary = (GameState.sim.politics_definitions.get("portfolios", {}) as Dictionary).get(
				str(event.get("portfolio", "")), {})
			var key := "NOTIFY_MINISTER_SCANDAL" if event.get("type") == GovernmentSystem.EVENT_SCANDAL \
				else "NOTIFY_MINISTER_RESIGNED"
			_notify(tr(key) % tr(str(portfolio.get("name_key", ""))))
		DiplomacySystem.EVENT_TREATY_SIGNED, DiplomacySystem.EVENT_TREATY_REFUSED, DiplomacySystem.EVENT_TREATY_CANCELLED:
			var treaty: Dictionary = GameState.sim.treaty_definitions.get(str(event.get("treaty", "")), {})
			var other := DataLoader.get_entry("countries", str(event.get("target", "")))
			_notify(tr("NOTIFY_%s" % str(event.get("type")).to_upper()) % [tr(str(treaty.get("name_key", ""))),
				tr(str(other.get("name_key", "")))])
		DiplomacySystem.EVENT_ULTIMATUM:
			var other := DataLoader.get_entry("countries", str(event.get("target", "")))
			_notify(tr("NOTIFY_ULTIMATUM_ACCEPTED" if bool(event.get("accepted", false)) else "NOTIFY_ULTIMATUM_REFUSED")
				% tr(str(other.get("name_key", ""))))
		OrganizationSystem.EVENT_JOINED, OrganizationSystem.EVENT_JOIN_REFUSED, OrganizationSystem.EVENT_LEFT, \
				OrganizationSystem.EVENT_CREATED, OrganizationSystem.EVENT_EXPELLED:
			var organization: Dictionary = GameState.sim.diplomacy.organizations.get(str(event.get("organization", "")), {})
			_notify(tr("NOTIFY_%s" % str(event.get("type")).to_upper()) % Localization.pick_text(
				organization.get("name", "")))
		OrganizationSystem.EVENT_RESOLUTION:
			var target := DataLoader.get_entry("countries", str(event.get("target", "")))
			_notify(tr("NOTIFY_RESOLUTION_PASSED" if bool(event.get("passed", false)) else "NOTIFY_RESOLUTION_FAILED")
				% [tr(str(target.get("name_key", ""))), event.get("yes", 0), event.get("no", 0)])
		SanctionSystem.EVENT_SANCTION:
			var definition: Dictionary = GameState.sim.sanction_definitions.get(str(event.get("measure", "")), {})
			var other := DataLoader.get_entry("countries", str(event.get("target", "")))
			_notify(tr("NOTIFY_SANCTION_IMPOSED" if bool(event.get("active", false)) else "NOTIFY_SANCTION_LIFTED")
				% [tr(str(definition.get("name_key", ""))), tr(str(other.get("name_key", "")))])
		AidSystem.EVENT_AID, AidSystem.EVENT_AID_REFUSED:
			var definition: Dictionary = GameState.sim.aid_definitions.get(str(event.get("kind", "")), {})
			var other := DataLoader.get_entry("countries", str(event.get("target", "")))
			_notify(tr("NOTIFY_AID_GIVEN" if event.get("type") == AidSystem.EVENT_AID else "NOTIFY_AID_REFUSED")
				% [tr(str(definition.get("name_key", ""))), tr(str(other.get("name_key", "")))])
		InfluenceSystem.EVENT_INFLUENCE:
			if bool(event.get("exposed", false)):
				var other := DataLoader.get_entry("countries", str(event.get("target", "")))
				_notify(tr("NOTIFY_INFLUENCE_EXPOSED") % tr(str(other.get("name_key", ""))))
		MediaSystem.EVENT_DISINFORMATION:
			_notify(tr("NOTIFY_DISINFORMATION_EXPOSED" if bool(event.get("exposed", false)) else "NOTIFY_DISINFORMATION_DONE"))
		CrisisSystem.EVENT_STARTED:
			var definition: Dictionary = (GameState.sim.politics_definitions.get("crises", {}) as Dictionary).get(
				str(event.get("crisis", "")), {})
			var group := DataLoader.get_entry("social_groups", str(event.get("group", "")))
			_notify(tr("NOTIFY_UNREST") % [tr(str(definition.get("name_key", ""))), tr(str(group.get("name_key", "")))])
		PoliticsSystem.EVENT_PROMISE:
			var group := DataLoader.get_entry("social_groups", str(event.get("group", "")))
			var key := "NOTIFY_PROMISE_KEPT" if str(event.get("outcome", "")) == "kept" else "NOTIFY_PROMISE_BROKEN"
			_notify(tr(key) % tr(str(group.get("name_key", ""))))
		TradeSystem.EVENT_AGREEMENT_LEFT:
			var agreement := DataLoader.get_entry("trade_agreements", str(event.get("agreement", "")))
			_notify(tr("NOTIFY_AGREEMENT_LEFT") % tr(str(agreement.get("name_key", ""))))


## « Législatives : le PRD arrive en tête. Nouveau gouvernement dirigé par l'UC. »
func _election_text(event: Dictionary) -> String:
	var parties := DataLoader.repository.resolve_ref("names#parties")
	var winner := str((parties.get(str(event.get("winner", "")), {}) as Dictionary).get("abbreviation", ""))
	var presidential := str(event.get("kind", "")) == ElectionSystem.KIND_PRESIDENTIAL
	var text := tr("NOTIFY_PRESIDENTIAL_WON" if presidential else "NOTIFY_LEGISLATIVE_WON") % winner
	if bool(event.get("managed", false)) or winner.is_empty():
		return tr("NOTIFY_ELECTION_MANAGED")
	var politics := GameState.sim.get_country(str(event.get("tag", ""))).politics
	if bool(event.get("government_changed", false)):
		var ruling := str((parties.get(politics.ruling_party(), {}) as Dictionary).get("abbreviation", ""))
		text += " " + tr("NOTIFY_NEW_GOVERNMENT") % ruling
	elif not presidential:
		text += " " + tr("NOTIFY_GOVERNMENT_STAYS")
	return text


func _strait_name_key(strait_id: String) -> String:
	return str(DataLoader.get_entry("straits", strait_id).get("name_key", strait_id))


func _on_year_passed(date: GameDate) -> void:
	_notify(tr("NOTIFY_NEW_YEAR") % date.year)


## Message temporaire sous la barre supérieure.
func _notify(text: String) -> void:
	_notification_label.text = text
	_notification_label.visible = true
	_notification_timer = get_tree().create_timer(float(DataLoader.get_define("time.notification_seconds")))
	var timer := _notification_timer
	timer.timeout.connect(func() -> void:
		if _notification_timer == timer:
			_notification_label.visible = false)


func set_map_mode(mode_id: String) -> void:
	var mode := _map_modes.get_mode(mode_id)
	if mode == null or _map_view.camera == null:
		return
	_current_mode_id = mode_id
	_mode_context.refresh_from_simulation(GameState.sim)
	_map_view.set_province_colors(mode.compute_colors(_mode_context))
	_mode_bar.set_current(mode_id)
	_legend.show_mode(mode, _mode_context)


func _cycle_map_mode(step: int) -> void:
	var count := _map_modes.modes.size()
	if count == 0:
		return
	var index := posmod(_map_modes.index_of(_current_mode_id) + step, count)
	set_map_mode(_map_modes.modes[index].id)


## Clic simple : fiche du pays propriétaire ; mers et terres sans propriétaire ouvrent leur propre fiche.
func _on_province_clicked(province_id: int) -> void:
	var province: Dictionary = DataLoader.get_entry("provinces", str(province_id))
	var owner := str(province.get("owner", ""))
	if _is_selecting():
		_selection_panel.select_country(owner)
		return
	var info := CountryInfo.build(owner, DataLoader.get_category("countries"),
		DataLoader.get_category("provinces"), DataLoader.get_category("names"),
		DataLoader.get_category("regimes"), DataLoader.get_category("ideologies"),
		DataLoader.get_category("names/cultures"), GameState.sim.date.year)
	if info == null:
		_show_province(province_id)
		return
	info.apply_economy(GameState.sim)
	info.apply_politics(GameState.sim, DataLoader.get_category("names"), DataLoader.get_category("ideologies"),
		DataLoader.get_category("names/cultures"))
	info.apply_diplomacy(GameState.sim)
	_info_panel.close()
	_map_view.set_selected_province(MapView.NO_SELECTION)
	_map_view.set_selected_country(owner)
	_country_panel.show_country(info)


## Double-clic (ou clic sur une mer ou une terre sans propriétaire) : fiche de la province ou de la zone.
func _show_province(province_id: int) -> void:
	if _is_selecting():
		return
	var info := ProvinceInfo.build(province_id, DataLoader.get_category("provinces"),
		DataLoader.get_category("countries"), DataLoader.get_category("terrains"),
		DataLoader.get_category("resources"), DataLoader.get_category("sea_zones"),
		DataLoader.get_category("straits"))
	_country_panel.close()
	if info == null:
		_map_view.set_selected_province(MapView.NO_SELECTION)
		_info_panel.close()
		return
	_apply_live_control(info, str(province_id))
	_map_view.set_selected_province(province_id)
	_info_panel.show_province(info)


## Contrôle de la partie en cours (occupations, provinces disputées) à la place des données de départ.
func _apply_live_control(info: ProvinceInfo, province_id: String) -> void:
	var state := GameState.sim
	if info.is_sea_zone or state.province_control.is_empty() or not state.province_control.has(province_id):
		return
	info.controller_tag = ControlSystem.controller(state, province_id)
	info.controller_name_key = MilitaryUI.side_name(state, info.controller_tag)
	info.is_occupied = not info.owner_tag.is_empty() and info.controller_tag != info.owner_tag
	var contest: Dictionary = state.contested.get(province_id, {})
	if not contest.is_empty():
		info.contested_name_key = MilitaryUI.side_name(state, str(contest["by"]))
		info.contested_share = float(contest["share"])


## Pions des groupes d'armées : symbole selon l'appartenance au pays joué, effectifs, trajet.
func _refresh_armies() -> void:
	if _is_selecting() or _map_view.camera == null:
		return
	var state := GameState.sim
	var player := str(state.player_tag)
	var provinces := DataLoader.get_category("provinces")
	var reserve_share := ArmyGroupModel.reserve_share(state)
	var hostile := float(DataLoader.get_define("military_symbols.hostile_relation", -50.0))
	var locale := Localization.get_locale()
	var tokens: Array[Dictionary] = []
	var own: Array[Dictionary] = []
	for group: ArmyGroup in state.army_groups.values():
		var country := state.get_country(group.owner)
		if country == null or country.military == null:
			continue
		var affiliation := _affiliation(state, player, group.owner, hostile)
		var path: Array = []
		for step: String in group.path:
			path.append(_province_center(provinces, step))
		var token := {"id": group.id, "kind": ArmyLayer.ARMY, "position": _province_center(provinces, group.province),
			"affiliation": affiliation,
			"label": tr("ARMY_THOUSANDS") % NumberFormat.integer(roundi(group.personnel(country.military, reserve_share)
				/ 1000.0), locale), "selected": group.id == _selected_group, "path": path}
		# Les pions du pays joué sont dessinés par-dessus les autres.
		if group.owner == player:
			own.append(token)
		else:
			tokens.append(token)
	var stacks: Dictionary = {}
	for fleet: Fleet in state.fleets.values():
		var affiliation := _affiliation(state, player, fleet.owner, hostile)
		var index := int(stacks.get(fleet.zone, 0))
		stacks[fleet.zone] = index + 1
		var path: Array = []
		for step: String in fleet.path:
			path.append(_sea_center(step))
		var token := {"id": fleet.id, "kind": ArmyLayer.FLEET, "position": _sea_center(fleet.zone)
			+ FLEET_STACK_OFFSET * index, "affiliation": affiliation, "label": tr("FLEET_CONDITION") % roundi(fleet.condition
			* 100.0), "selected": fleet.id == _selected_fleet, "path": path}
		if fleet.owner == player:
			own.append(token)
		else:
			tokens.append(token)
	tokens.append_array(own)
	_map_view.set_army_tokens(tokens)


func _affiliation(state: SimState, player: String, tag: String, hostile: float) -> String:
	if player.is_empty():
		return NatoSymbol.NEUTRAL
	if ControlSystem.allied(state, player, tag):
		return NatoSymbol.FRIEND
	if WarSystem.at_war(state, player, tag) or state.diplomacy.relation(player, tag) < hostile:
		return NatoSymbol.HOSTILE
	return NatoSymbol.NEUTRAL


static func _sea_center(zone_id: String) -> Vector2:
	var center: Array = DataLoader.get_entry("sea_zones", zone_id).get("center", [0.0, 0.0])
	return Vector2(float(center[0]), float(center[1]))


static func _province_center(provinces: Dictionary, province_id: String) -> Vector2:
	var center: Array = (provinces.get(province_id, {}) as Dictionary).get("center", [0.0, 0.0])
	return Vector2(float(center[0]), float(center[1]))


func _on_army_group_clicked(group_id: int) -> void:
	var state := GameState.sim
	var group: ArmyGroup = state.army_groups.get(group_id)
	if group == null:
		return
	var country := state.get_country(group.owner)
	var name := _military_ui.group_name(group)
	if group.owner == str(state.player_tag):
		_selected_group = -1 if _selected_group == group_id else group_id
		_selected_fleet = -1
		if _selected_group >= 0:
			_notify(tr("NOTIFY_ARMY_SELECTED") % name)
	else:
		var owner_name := tr(str(DataLoader.get_entry("countries", group.owner).get("name_key", "")))
		_notify(tr("NOTIFY_ARMY_FOREIGN") % [name, owner_name, NumberFormat.integer(roundi(
			group.personnel(country.military, ArmyGroupModel.reserve_share(state))), Localization.get_locale())])
	_refresh_armies()


func _on_fleet_clicked(fleet_id: int) -> void:
	var state := GameState.sim
	var fleet: Fleet = state.fleets.get(fleet_id)
	if fleet == null:
		return
	var name := _military_ui.fleet_name(fleet)
	if fleet.owner == str(state.player_tag):
		_selected_fleet = -1 if _selected_fleet == fleet_id else fleet_id
		_selected_group = -1
		if _selected_fleet >= 0:
			_notify(tr("NOTIFY_FLEET_SELECTED") % name)
	else:
		_notify(tr("NOTIFY_FLEET_FOREIGN") % [name, MilitaryUI.side_name(state, fleet.owner), roundi(fleet.condition * 100.0)])
	_refresh_armies()


func _on_province_right_clicked(province_id: int) -> void:
	if _selected_fleet >= 0 and province_id > 0:
		var order := MoveFleetCommand.new(GameState.sim.player_tag, _selected_fleet, str(province_id))
		var reason := order.refusal_reason(GameState.sim)
		if not reason.is_empty():
			_notify(tr(reason))
			return
		if GameState.submit_command(order) and GameClock.is_paused:
			GameState.process_commands()
		return
	if _selected_group < 0 or province_id <= 0:
		return
	var state := GameState.sim
	var command := MoveArmyGroupCommand.new(state.player_tag, _selected_group, str(province_id))
	var refusal := command.refusal_reason(state)
	# Province ennemie : débarquement si une de nos flottes tient la mer voisine.
	if refusal == "ARMY_NOT_CONTROLLED" and WarSystem.at_war(state, str(state.player_tag),
			ControlSystem.controller(state, str(province_id))):
		var landing := LandingCommand.new(state.player_tag, _selected_group, str(province_id))
		var landing_refusal := landing.refusal_reason(state)
		if not landing_refusal.is_empty():
			_notify(tr(landing_refusal))
			return
		var group: ArmyGroup = state.army_groups[_selected_group]
		var odds := LandingSystem.chance(state, group, str(province_id), LandingSystem.landing_zone(state,
			str(state.player_tag), str(province_id)))
		_notify(tr("NOTIFY_LANDING_LAUNCHED") % [_military_ui.group_name(group), _province_label(str(province_id)),
			roundi(odds * 100.0)])
		if GameState.submit_command(landing) and GameClock.is_paused:
			GameState.process_commands()
		return
	if not refusal.is_empty():
		_notify(tr(refusal))
		return
	if GameState.submit_command(command) and GameClock.is_paused:
		GameState.process_commands()


## Centre la carte sur un groupe d'armées du pays joué et le sélectionne.
func _focus_army_group(group_id: int) -> void:
	var group: ArmyGroup = GameState.sim.army_groups.get(group_id)
	if group == null:
		return
	_selected_group = group_id
	_map_view.focus_on(_province_center(DataLoader.get_category("provinces"), group.province),
		maxf(_map_view.camera.zoom, float(DataLoader.get_define("camera.capital_zoom"))))
	_refresh_armies()


func _province_label(province_id: String) -> String:
	return tr(str(DataLoader.get_entry("provinces", province_id).get("name_key", province_id)))


## Débarquements et blocus du pays joué (ou qui le visent). Vrai si l'événement a été traité.
func _on_naval_event(event: Dictionary) -> bool:
	var state := GameState.sim
	var player := str(state.player_tag)
	var tag := str(event.get("tag", ""))
	match event.get("type"):
		LandingSystem.EVENT_SUCCEEDED, LandingSystem.EVENT_FAILED:
			var target := str(event.get("target", ""))
			if tag != player and target != player:
				return true
			var success: bool = event.get("type") == LandingSystem.EVENT_SUCCEEDED
			var key := ""
			if tag == player:
				key = "NOTIFY_LANDING_SUCCEEDED" if success else "NOTIFY_LANDING_FAILED"
			else:
				key = "NOTIFY_ENEMY_LANDING_SUCCEEDED" if success else "NOTIFY_ENEMY_LANDING_FAILED"
			_notify(tr(key) % [_province_label(str(event.get("province", ""))),
				MilitaryUI.side_name(state, target if tag == player else tag)])
		LandingSystem.EVENT_EVACUATED:
			if tag == player:
				_notify(tr("NOTIFY_BEACHHEAD_LOST") % _province_label(str(event.get("province", ""))))
		NuclearSystem.EVENT_STRIKE:
			var key := "NOTIFY_NUCLEAR_RETALIATION" if bool(event.get("retaliation", false)) else "NOTIFY_NUCLEAR_STRIKE"
			_notify(tr(key) % [MilitaryUI.side_name(state, tag), _province_label(str(event.get("province", ""))),
				MilitaryUI.side_name(state, str(event.get("target", "")))])
		NuclearSystem.EVENT_PROGRAM:
			var step := str(event.get("step", ""))
			if step == "detected" or step == "completed" or tag == player:
				_notify(tr("NOTIFY_NUCLEAR_PROGRAM_%s" % step.to_upper()) % MilitaryUI.side_name(state, tag))
		NuclearSystem.EVENT_ALERT:
			if int(event.get("level", 0)) >= NuclearSystem.MAX_ALERT or tag == player:
				_notify(tr("NOTIFY_NUCLEAR_ALERT") % [MilitaryUI.side_name(state, tag),
					tr("NUCLEAR_ALERT_%d" % int(event.get("level", 0))).to_lower()])
		MilitaryActions.EVENT_ACTION:
			var target := str(event.get("target", ""))
			var action := str(event.get("action", ""))
			if tag == player:
				var outcome := "SUCCESS" if bool(event.get("success", false)) else "FAILURE"
				var text := tr("NOTIFY_%s_%s" % [action.to_upper(), outcome]) % MilitaryUI.side_name(state, target)
				if bool(event.get("discovered", false)):
					text += " " + tr("NOTIFY_CYBER_DISCOVERED")
				_notify(text)
			elif target == player and (action != MilitaryActions.CYBER or bool(event.get("discovered", false))) \
					and bool(event.get("success", false)):
				_notify(tr("NOTIFY_%s_SUFFERED" % action.to_upper()) % MilitaryUI.side_name(state, tag))
		NavalModel.EVENT_BLOCKADE:
			if tag == player:
				var share := float(event.get("share", 0.0))
				if share > 0.0:
					_notify(tr("NOTIFY_BLOCKADE_STARTED") % roundi(share * 100.0))
				else:
					_notify(tr("NOTIFY_BLOCKADE_ENDED"))
		_:
			return false
	return true


## Centre la carte sur une flotte du pays joué et la sélectionne.
func _focus_fleet(fleet_id: int) -> void:
	var fleet: Fleet = GameState.sim.fleets.get(fleet_id)
	if fleet == null:
		return
	_selected_fleet = fleet_id
	_selected_group = -1
	_map_view.focus_on(_sea_center(fleet.zone), maxf(_map_view.camera.zoom, float(DataLoader.get_define("camera.capital_zoom"))))
	_refresh_armies()


func _update_debug() -> void:
	var camera := _map_view.camera
	if camera == null:
		_debug_label.text = ""
		return
	var map_position := camera.screen_to_map(_map_view.get_local_mouse_position())
	var longitude := map_position.x / camera.map_size.x * DEGREES_PER_TURN - DEGREES_HALF_TURN
	var latitude := DEGREES_HALF_TURN * 0.5 - map_position.y / camera.map_size.y * DEGREES_HALF_TURN
	_debug_label.text = tr("DEBUG_MAP_INFO") % [Engine.get_frames_per_second(), camera.zoom, latitude, longitude]

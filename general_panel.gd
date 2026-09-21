extends CanvasLayer
## Phone-sized General panel — Stats / Gear / Bag / Radio / Loop / Settlement.
## Godot 4.1-safe: explicit types; no ambiguous := on loop vars.
## Attach via GeneralPanel.attach(host_node, ui_canvas_layer).

class_name GeneralPanel

const SETTLEMENT_SCENE := ""  ## stub — empty until four buildings exist
const FONT_BODY := 16
const FONT_TITLE := 22
const FONT_SECTION := 18

signal closed
signal toast_requested(msg: String)

var _root: Control
var _panel: PanelContainer
var _stats_label: Label
var _loop_label: Label
var _radio_label: Label
var _gear_neck_btn: Button
var _gear_arm_l_btn: Button
var _gear_arm_r_btn: Button
var _gear_cloak_btn: Button
var _gear_weapon_btn: Button
var _gear_side_btn: Button
var _bag_grid: GridContainer
var _bag_btns: Array = []
var _settlement_panel: PanelContainer
var _player_ref: Node = null
var _open: bool = false

static func attach(host: Node, ui: CanvasLayer = null, player: Node = null) -> GeneralPanel:
	## Build General button on ui + panel layer. Returns the panel instance.
	var existing: Node = host.get_node_or_null("GeneralPanel")
	if existing != null and existing is GeneralPanel:
		var gp0: GeneralPanel = existing as GeneralPanel
		if player != null:
			gp0.set_player(player)
		return gp0
	var gp := GeneralPanel.new()
	gp.name = "GeneralPanel"
	host.add_child(gp)
	if player != null:
		gp.set_player(player)
	var layer: CanvasLayer = ui
	if layer == null:
		layer = host.get_node_or_null("UI") as CanvasLayer
	if layer != null:
		gp._add_general_button(layer)
	return gp

func set_player(player: Node) -> void:
	_player_ref = player

func _ready() -> void:
	layer = 30
	_build_ui()
	visible = false
	_open = false

func is_open() -> bool:
	return _open

func open_panel() -> void:
	if _player_ref != null and GameState.has_method("sync_hp_from_player"):
		GameState.sync_hp_from_player(_player_ref)
	_refresh_all()
	visible = true
	_open = true
	if _root:
		_root.visible = true

func close_panel() -> void:
	visible = false
	_open = false
	if _root:
		_root.visible = false
	if _settlement_panel:
		_settlement_panel.visible = false
	closed.emit()

func toggle_panel() -> void:
	if _open:
		close_panel()
	else:
		open_panel()

func _add_general_button(ui: CanvasLayer) -> void:
	if ui.get_node_or_null("GeneralButton") != null:
		var existing_btn: Button = ui.get_node("GeneralButton") as Button
		if existing_btn and not existing_btn.pressed.is_connected(toggle_panel):
			existing_btn.pressed.connect(toggle_panel)
		return
	var btn := Button.new()
	btn.name = "GeneralButton"
	btn.text = "General"
	btn.z_index = 40
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", 18)
	# Top-right, clear of objective / combat cluster
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 0.0
	btn.anchor_bottom = 0.0
	btn.offset_left = -128.0
	btn.offset_right = -16.0
	btn.offset_top = 58.0
	btn.offset_bottom = 106.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.28, 0.22, 0.42, 0.94)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)
	btn.pressed.connect(toggle_panel)
	ui.add_child(btn)

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Right side drawer — landscape phone (width free, height scarce)
	_panel.anchor_left = 0.52
	_panel.anchor_right = 0.99
	_panel.anchor_top = 0.04
	_panel.anchor_bottom = 0.96
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.10, 0.16, 0.96)
	pstyle.corner_radius_top_left = 16
	pstyle.corner_radius_top_right = 16
	pstyle.corner_radius_bottom_right = 16
	pstyle.corner_radius_bottom_left = 16
	pstyle.content_margin_left = 14
	pstyle.content_margin_right = 14
	pstyle.content_margin_top = 12
	pstyle.content_margin_bottom = 12
	pstyle.border_width_left = 2
	pstyle.border_width_top = 2
	pstyle.border_width_right = 2
	pstyle.border_width_bottom = 2
	pstyle.border_color = Color(0.45, 0.35, 0.65, 0.8)
	_panel.add_theme_stylebox_override("panel", pstyle)
	_root.add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(outer)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)
	var title := Label.new()
	title.text = "General"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", Color(0.92, 0.88, 1.0))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(88, 44)
	close_btn.add_theme_font_size_override("font_size", FONT_BODY)
	close_btn.pressed.connect(close_panel)
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)

	# --- Stats ---
	body.add_child(_section_title("Stats"))
	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.add_theme_font_size_override("font_size", FONT_BODY)
	_stats_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	body.add_child(_stats_label)

	# --- Gear ---
	body.add_child(_section_title("Gear"))
	var gear_hint := Label.new()
	gear_hint.text = "Tap gear to unequip · tap empty slot or bag item to re-equip"
	gear_hint.add_theme_font_size_override("font_size", FONT_BODY)
	gear_hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	body.add_child(gear_hint)
	var gear_row := VBoxContainer.new()
	gear_row.add_theme_constant_override("separation", 6)
	body.add_child(gear_row)
	_gear_neck_btn = _make_gear_btn("Neck", "neck")
	_gear_arm_l_btn = _make_gear_btn("Arm L", "arm_l")
	_gear_arm_r_btn = _make_gear_btn("Arm R", "arm_r")
	_gear_cloak_btn = _make_gear_btn("Cloak", "cloak")
	_gear_weapon_btn = _make_gear_btn("Stick", "weapon")
	_gear_side_btn = _make_gear_btn("Sgian", "side")
	gear_row.add_child(_gear_neck_btn)
	gear_row.add_child(_gear_arm_l_btn)
	gear_row.add_child(_gear_arm_r_btn)
	gear_row.add_child(_gear_cloak_btn)
	gear_row.add_child(_gear_weapon_btn)
	gear_row.add_child(_gear_side_btn)

	# --- Bag ---
	body.add_child(_section_title("Bag"))
	var bag_hint := Label.new()
	bag_hint.text = "Tap bag item to equip · or tap empty gear slot to re-equip"
	bag_hint.add_theme_font_size_override("font_size", FONT_BODY)
	bag_hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	body.add_child(bag_hint)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 3
	_bag_grid.add_theme_constant_override("h_separation", 6)
	_bag_grid.add_theme_constant_override("v_separation", 6)
	body.add_child(_bag_grid)
	_bag_btns.clear()
	var bi: int = 0
	while bi < GameState.BAG_SIZE:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.disabled = false
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", FONT_BODY)
		var captured_i: int = bi
		b.pressed.connect(func() -> void: _on_bag_slot(captured_i))
		_bag_grid.add_child(b)
		_bag_btns.append(b)
		bi += 1

	# --- Radio (near bag/gear) ---
	body.add_child(_section_title("Radio"))
	var radio_row := HBoxContainer.new()
	radio_row.add_theme_constant_override("separation", 8)
	body.add_child(radio_row)
	var prev_btn := Button.new()
	prev_btn.text = "◀ Prev"
	prev_btn.focus_mode = Control.FOCUS_NONE
	prev_btn.custom_minimum_size = Vector2(96, 48)
	prev_btn.add_theme_font_size_override("font_size", FONT_BODY)
	prev_btn.pressed.connect(_on_radio_prev)
	radio_row.add_child(prev_btn)
	_radio_label = Label.new()
	_radio_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_label.add_theme_font_size_override("font_size", FONT_BODY)
	_radio_label.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0))
	_radio_label.text = "—"
	radio_row.add_child(_radio_label)
	var next_btn := Button.new()
	next_btn.text = "Next ▶"
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.custom_minimum_size = Vector2(96, 48)
	next_btn.add_theme_font_size_override("font_size", FONT_BODY)
	next_btn.pressed.connect(_on_radio_next)
	radio_row.add_child(next_btn)
	var radio_note := Label.new()
	radio_note.text = "Cycles track_01…track_20 · missing skipped"
	radio_note.add_theme_font_size_override("font_size", FONT_BODY)
	radio_note.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	body.add_child(radio_note)

	# --- Loop ---
	body.add_child(_section_title("Loop"))
	_loop_label = Label.new()
	_loop_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loop_label.add_theme_font_size_override("font_size", FONT_BODY)
	_loop_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_loop_label.custom_minimum_size = Vector2(0, 40)
	body.add_child(_loop_label)

	# --- Settlement ---
	body.add_child(_section_title("Settlement"))
	var settle_btn := Button.new()
	settle_btn.text = "Open Settlement"
	settle_btn.focus_mode = Control.FOCUS_NONE
	settle_btn.custom_minimum_size = Vector2(0, 48)
	settle_btn.add_theme_font_size_override("font_size", FONT_BODY)
	settle_btn.pressed.connect(_on_settlement)
	body.add_child(settle_btn)

	_build_settlement_stub()

func _section_title(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", FONT_SECTION)
	lab.add_theme_color_override("font_color", Color(0.75, 0.7, 0.95))
	return lab

func _make_gear_btn(label: String, slot: String) -> Button:
	var b := Button.new()
	b.text = "%s: —" % label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", FONT_BODY)
	b.set_meta("gear_slot", slot)
	b.set_meta("gear_label", label)
	b.pressed.connect(func() -> void: _on_gear_slot_pressed(slot))
	return b

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# Only close if click is outside panel — dim covers full screen;
			# clicks on panel are on panel children, not dim.
			close_panel()

func _refresh_all() -> void:
	_refresh_stats()
	_refresh_gear()
	_refresh_bag()
	_refresh_loop()
	_refresh_radio()

func _refresh_stats() -> void:
	if _stats_label == null:
		return
	var nm: String = GameState.display_name()
	_stats_label.text = (
		"%s\nStrength  %d    Agility  %d    Wisdom  %d\nHP  %d / %d"
		% [nm, GameState.strength, GameState.agility, GameState.wisdom, GameState.hp, GameState.max_hp]
	)

func _refresh_gear() -> void:
	_set_gear_btn(_gear_neck_btn, "Neck", GameState.gear_neck)
	_set_gear_btn(_gear_arm_l_btn, "Arm L", GameState.gear_arm_l)
	_set_gear_btn(_gear_arm_r_btn, "Arm R", GameState.gear_arm_r)
	_set_gear_btn(_gear_cloak_btn, "Cloak", GameState.gear_cloak)
	_set_gear_btn(_gear_weapon_btn, "Stick", GameState.gear_weapon)
	_set_gear_btn(_gear_side_btn, "Sgian", GameState.gear_side)

func _set_gear_btn(btn: Button, label: String, item_id: String) -> void:
	if btn == null:
		return
	var shown: String = GameState.item_display_name(item_id)
	if item_id.is_empty():
		btn.text = "%s: (empty) — tap to re-equip" % label
	else:
		btn.text = "%s: %s" % [label, shown]
	btn.disabled = false

func _refresh_bag() -> void:
	GameState.ensure_bag()
	var i: int = 0
	while i < _bag_btns.size():
		var btn: Button = _bag_btns[i] as Button
		var item_id: String = ""
		if i < GameState.bag.size():
			item_id = str(GameState.bag[i])
		## Never disable bag buttons — on some touch builds, disabled→enabled
		## slots stop receiving taps (blocks re-equip after unequip).
		btn.disabled = false
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		if item_id.is_empty():
			btn.text = "·"
			btn.modulate = Color(1, 1, 1, 0.45)
		else:
			btn.text = GameState.item_display_name(item_id)
			btn.modulate = Color(1, 1, 1, 1)
		i += 1

func _refresh_loop() -> void:
	if _loop_label:
		_loop_label.text = GameState.loop_hint()

func _refresh_radio() -> void:
	if _radio_label == null:
		return
	if Music and Music.has_method("current_track_label"):
		var lab: String = str(Music.current_track_label())
		var idx: int = 0
		if Music.has_method("radio_index"):
			idx = int(Music.radio_index())
		if idx > 0:
			_radio_label.text = "%s  (%d/20)" % [lab, idx]
		else:
			_radio_label.text = lab
	else:
		_radio_label.text = "—"

func _on_bag_slot(slot_i: int) -> void:
	GameState.ensure_bag()
	if slot_i < 0 or slot_i >= GameState.bag.size():
		return
	var item_id: String = str(GameState.bag[slot_i])
	if item_id.is_empty():
		return
	if GameState.equip_from_bag(slot_i):
		_refresh_gear()
		_refresh_bag()
		toast_requested.emit("Equipped %s." % GameState.item_display_name(item_id))
	else:
		# misc / unequippable — soft toast via host if connected
		toast_requested.emit("Cannot equip that.")

func _on_gear_slot_pressed(slot: String) -> void:
	## Worn → unequip to bag. Empty → re-equip first matching bag item.
	var worn: String = ""
	match slot:
		"neck":
			worn = GameState.gear_neck
		"arm_l":
			worn = GameState.gear_arm_l
		"arm_r":
			worn = GameState.gear_arm_r
		"cloak":
			worn = GameState.gear_cloak
		"weapon":
			worn = GameState.gear_weapon
		"side":
			worn = GameState.gear_side
		_:
			worn = ""
	if worn.is_empty():
		if GameState.equip_first_from_bag_for_slot(slot):
			_refresh_gear()
			_refresh_bag()
			toast_requested.emit("Re-equipped.")
		else:
			toast_requested.emit("Nothing in bag for that slot — tap a bag item.")
		return
	if GameState.unequip_to_bag(slot):
		_refresh_gear()
		_refresh_bag()
	else:
		toast_requested.emit("Bag full — cannot unequip.")

func _on_unequip(slot: String) -> void:
	## Kept for compatibility; same as gear press when worn.
	_on_gear_slot_pressed(slot)

func _on_radio_next() -> void:
	if Music and Music.has_method("radio_next"):
		Music.radio_next()
	_refresh_radio()

func _on_radio_prev() -> void:
	if Music and Music.has_method("radio_prev"):
		Music.radio_prev()
	_refresh_radio()

func _on_settlement() -> void:
	if SETTLEMENT_SCENE != "" and ResourceLoader.exists(SETTLEMENT_SCENE):
		# Future: open settlement scene/panel
		_show_settlement_stub()
		return
	# No scene yet — stub panel OR toast
	_show_settlement_stub()

func _build_settlement_stub() -> void:
	_settlement_panel = PanelContainer.new()
	_settlement_panel.name = "SettlementStub"
	_settlement_panel.visible = false
	_settlement_panel.z_index = 5
	_settlement_panel.anchor_left = 0.1
	_settlement_panel.anchor_right = 0.9
	_settlement_panel.anchor_top = 0.35
	_settlement_panel.anchor_bottom = 0.65
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.14, 0.20, 0.98)
	st.corner_radius_top_left = 12
	st.corner_radius_top_right = 12
	st.corner_radius_bottom_right = 12
	st.corner_radius_bottom_left = 12
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	_settlement_panel.add_theme_stylebox_override("panel", st)
	_root.add_child(_settlement_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_settlement_panel.add_child(vb)
	var t := Label.new()
	t.text = "Settlement"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", FONT_TITLE)
	t.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	vb.add_child(t)
	var body := Label.new()
	body.text = "Settlement — four buildings later"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", FONT_BODY)
	body.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
	vb.add_child(body)
	var ok := Button.new()
	ok.text = "OK"
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(0, 44)
	ok.add_theme_font_size_override("font_size", FONT_BODY)
	ok.pressed.connect(func() -> void: _settlement_panel.visible = false)
	vb.add_child(ok)

func _show_settlement_stub() -> void:
	if _settlement_panel:
		_settlement_panel.visible = true
	toast_requested.emit("Settlement — four buildings later")

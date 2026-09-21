extends Control
## Settlement builder stub — fullscreen pannable isometric map + ghost plot labels.
## Access ONLY via Druid dialogue in tree_well_room. Back returns there.
## Empty builder: plots are non-functional ("Coming later").

const MAP_PATH := "res://assets/art/settlement/settlement_map_isometric_northstar.jpg"
const TREE_WELL := "res://scenes/tree_well_room.tscn"

## Ghost plot labels: name + normalized map position (0..1 over map texture)
const GHOST_PLOTS := [
	{"name": "Strength", "pos": Vector2(0.28, 0.42), "hint": "Coming later"},
	{"name": "Agility", "pos": Vector2(0.58, 0.36), "hint": "Coming later"},
	{"name": "Wisdom", "pos": Vector2(0.40, 0.62), "hint": "Coming later"},
	{"name": "Vitality", "pos": Vector2(0.68, 0.58), "hint": "Coming later"},
]

var _scroll: ScrollContainer = null
var _map_tex: TextureRect = null
var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _scene_leaving: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.name = "MapScroll"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 56.0
	_scroll.offset_bottom = -72.0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)

	var holder := Control.new()
	holder.name = "MapHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.add_child(holder)

	_map_tex = TextureRect.new()
	_map_tex.name = "SettlementMap"
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(MAP_PATH):
		_map_tex.texture = load(MAP_PATH) as Texture2D
	holder.add_child(_map_tex)

	# Size map larger than viewport so pan has room
	var vp := get_viewport_rect().size
	var map_w: float = maxf(vp.x * 1.55, 1400.0)
	var map_h: float = maxf(vp.y * 1.55, 900.0)
	if _map_tex.texture:
		var ts := _map_tex.texture.get_size()
		if ts.x > 1.0 and ts.y > 1.0:
			var scale_fit: float = maxf(map_w / ts.x, map_h / ts.y)
			map_w = ts.x * scale_fit
			map_h = ts.y * scale_fit
	holder.custom_minimum_size = Vector2(map_w, map_h)
	_map_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_tex.offset_left = 0.0
	_map_tex.offset_top = 0.0
	_map_tex.offset_right = 0.0
	_map_tex.offset_bottom = 0.0
	_map_tex.size = Vector2(map_w, map_h)

	_place_ghost_plots(holder, Vector2(map_w, map_h))

	# Top bar
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 56.0
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	var top_st := StyleBoxFlat.new()
	top_st.bg_color = Color(0.06, 0.05, 0.12, 0.92)
	top_st.content_margin_left = 16
	top_st.content_margin_right = 16
	top_st.content_margin_top = 10
	top_st.content_margin_bottom = 10
	top.add_theme_stylebox_override("panel", top_st)
	add_child(top)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top.add_child(top_row)

	var title := Label.new()
	title.text = "Settlement"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	top_row.add_child(title)

	var sub := Label.new()
	sub.text = "Empty builder · drag to pan · plots coming later"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.70, 0.72, 0.82, 0.9))
	top_row.add_child(sub)

	# Bottom Back
	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(160, 48)
	back.add_theme_font_size_override("font_size", 20)
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -80.0
	back.offset_right = 80.0
	back.offset_top = -64.0
	back.offset_bottom = -14.0
	back.pressed.connect(_on_back)
	add_child(back)

	# Center scroll on map middle after layout
	call_deferred("_center_map")

func _place_ghost_plots(holder: Control, map_size: Vector2) -> void:
	for plot in GHOST_PLOTS:
		var name_s: String = str(plot["name"])
		var pos: Vector2 = plot["pos"] as Vector2
		var hint: String = str(plot.get("hint", "Coming later"))

		var wrap := PanelContainer.new()
		wrap.mouse_filter = Control.MOUSE_FILTER_STOP
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.08, 0.10, 0.16, 0.72)
		st.border_color = Color(0.75, 0.70, 0.45, 0.55)
		st.border_width_left = 1
		st.border_width_top = 1
		st.border_width_right = 1
		st.border_width_bottom = 1
		st.corner_radius_top_left = 8
		st.corner_radius_top_right = 8
		st.corner_radius_bottom_right = 8
		st.corner_radius_bottom_left = 8
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 6
		st.content_margin_bottom = 6
		wrap.add_theme_stylebox_override("panel", st)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		wrap.add_child(vb)

		var lab := Label.new()
		lab.text = name_s
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 16)
		lab.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72))
		vb.add_child(lab)

		var h := Label.new()
		h.text = hint
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_theme_font_size_override("font_size", 12)
		h.add_theme_color_override("font_color", Color(0.65, 0.68, 0.78, 0.85))
		vb.add_child(h)

		# Non-functional tap
		var ghost_btn := Button.new()
		ghost_btn.flat = true
		ghost_btn.focus_mode = Control.FOCUS_NONE
		ghost_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		ghost_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		ghost_btn.pressed.connect(func() -> void: _on_ghost_tap(name_s))
		wrap.add_child(ghost_btn)

		holder.add_child(wrap)
		# Position after we know approximate size
		wrap.position = Vector2(pos.x * map_size.x - 60.0, pos.y * map_size.y - 28.0)

func _on_ghost_tap(plot_name: String) -> void:
	# Non-functional — soft feedback only
	var toast := get_node_or_null("GhostToast") as Label
	if toast == null:
		toast = Label.new()
		toast.name = "GhostToast"
		toast.anchor_left = 0.5
		toast.anchor_right = 0.5
		toast.anchor_top = 1.0
		toast.anchor_bottom = 1.0
		toast.offset_left = -200.0
		toast.offset_right = 200.0
		toast.offset_top = -110.0
		toast.offset_bottom = -80.0
		toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		toast.add_theme_font_size_override("font_size", 15)
		toast.add_theme_color_override("font_color", Color(0.92, 0.88, 0.70))
		add_child(toast)
	toast.text = "%s — Coming later" % plot_name
	toast.visible = true
	var t := get_tree().create_timer(1.4)
	t.timeout.connect(func() -> void:
		if is_instance_valid(toast):
			toast.visible = false
	)

func _center_map() -> void:
	if _scroll == null or _map_tex == null:
		return
	await get_tree().process_frame
	var hsize: Vector2 = _scroll.get_child(0).size if _scroll.get_child_count() > 0 else Vector2.ZERO
	var vis := _scroll.size
	_scroll.scroll_horizontal = int(maxf(0.0, (hsize.x - vis.x) * 0.5))
	_scroll.scroll_vertical = int(maxf(0.0, (hsize.y - vis.y) * 0.5))

func _gui_input(event: InputEvent) -> void:
	_handle_pan(event)

func _input(event: InputEvent) -> void:
	# Allow pan when pointer is over map scroll area
	if _scroll and _scroll.get_global_rect().has_point(get_global_mouse_position()):
		_handle_pan(event)

func _handle_pan(event: InputEvent) -> void:
	if _scroll == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_last = mb.position
			if mb.pressed:
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var delta: Vector2 = mm.position - _drag_last
		_drag_last = mm.position
		_scroll.scroll_horizontal = int(_scroll.scroll_horizontal - delta.x)
		_scroll.scroll_vertical = int(_scroll.scroll_vertical - delta.y)
		accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_dragging = st.pressed
		_drag_last = st.position
	elif event is InputEventScreenDrag and _dragging:
		var sd := event as InputEventScreenDrag
		_scroll.scroll_horizontal = int(_scroll.scroll_horizontal - sd.relative.x)
		_scroll.scroll_vertical = int(_scroll.scroll_vertical - sd.relative.y)
		accept_event()

func _on_back() -> void:
	if _scene_leaving:
		return
	_scene_leaving = true
	get_tree().change_scene_to_file(TREE_WELL)

extends Control
## Seeing Well — Sunrise Wheel (replaces old place-and-die tower defence).
## Well at centre. Wisps spiral inward on 8 axes (uneven pressure).
## Bottom: weighted Sunrise Wheel — flick to put Inf/Arch/Cav rune at zenith,
## tap when matching wisp hits the deadline ring to detonate it.
## Win: clear one wave. Lose: any wisp reaches the well.

const AXIS_COUNT := 8
const WAVE_WISP_COUNT := 12
const PRACTICE_COUNT := 1  ## first wisp is a slow teach shot (no instant fail)
const SPIRAL_SPEED := 0.11  ## base progress / sec (was 0.22 — unlearnable)
const SPIRAL_SPEED_MAX := 0.18  ## late-wave ceiling after ramp
const DEADLINE_PROGRESS := 0.32  ## gold ring band (slightly farther from well)
const DEADLINE_WINDOW := 0.28  ## half-width — fairer tap window (was 0.11)
const WELL_HIT_PROGRESS := 0.05
const GRACE_BEFORE_SPAWN := 5.0  ## calm seconds after Start before first wisp
const RUNE_SNAP := 3  ## Inf / Arch / Cav around the wheel
const WHEEL_FRICTION := 2.8
const WHEEL_ROCK_AMP := 0.12  ## uneven weighted rock (radians)
const FIRST_SPAWN_GAP := 2.4  ## after grace, gap before/around early wisps
const LATE_SPAWN_GAP := 1.05

enum Troop { INF, ARCH, CAV }

const TROOP_LETTER := {Troop.INF: "I", Troop.ARCH: "A", Troop.CAV: "C"}
const TROOP_NAME := {Troop.INF: "Inf", Troop.ARCH: "Arch", Troop.CAV: "Cav"}
const TROOP_COLOR := {
	Troop.INF: Color(0.35, 0.55, 0.90),
	Troop.ARCH: Color(0.20, 0.78, 0.78),
	Troop.CAV: Color(0.92, 0.50, 0.22),
}

## Uneven axis pressure weights (higher = more wisps prefer that arm).
const AXIS_WEIGHTS := [1.6, 0.7, 1.4, 0.5, 1.8, 0.9, 1.2, 0.6]

const RULES_TEXT := """SEEING WELL — SUNRISE WHEEL (quick how-to)

GOAL
• Keep wisps off the Seeing Well. Clear the wave to win.
• Lose only if a real wisp reaches the well (practice shot is safe).

HOW TO PLAY
1. Flick / drag the counterweighted disc so Inf · Arch · Cav sits at ▲ ZENITH.
2. Watch the gold ring around the well.
3. When a wisp whose letter matches the zenith rune is ON the gold ring, tap TAP Inf/Arch/Cav.
4. Matching wisps glow brighter; the tap button shows which rune is up.

BOARD
• Well at centre · eight uneven arms · gold deadline ring.
• First seconds are calm — learn the disc before pressure builds.
• One slow practice wisp opens the wave (cannot end the match).

RUNES
• Letter placeholders (I / A / C) for now — Pictish stone marks TBD.
• This is Pictish — NOT Celtic.

CONTROLS
• Flick the Sunrise Wheel · tap the zenith button on the gold ring · Start / Back / Rules.
"""


var _wisps: Array = []  ## {axis, progress, kind, angle_spin, node}
var _spawned: int = 0
var _cleared: int = 0
var _spawn_timer: float = 0.8
var _playing: bool = false
var _ended: bool = false
var _toast_t: float = 0.0
var _game_t: float = 0.0

## Wheel state — angle 0 = Inf at zenith; 2π/3 = Arch; 4π/3 = Cav.
var _wheel_angle: float = 0.0
var _wheel_vel: float = 0.0
var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _wheel_press_pos: Vector2 = Vector2.ZERO
var _wheel_moved: bool = false
var _rock_t: float = 0.0

var _well_pos: Vector2 = Vector2.ZERO
var _board: Control
var _wisp_layer: Control
var _fx_layer: Control
var _well_panel: PanelContainer
var _well_label: Label
var _wheel_panel: Control
var _wheel_disc: Panel
var _rune_labels: Array = []  ## Button x3 on disc
var _zenith_btn: Button
var _obj: Label
var _hud: Label
var _status: Label
var _toast: Label
var _result: Label
var _btn_start: Button
var _btn_back: Button
var _btn_rules: Button
var _rules_panel: Control
var _rules_visible: bool = false
var _axis_guides: Array = []
var _teach_pulse: float = 0.0
var _taught_ring: bool = false
var _taught_zenith: bool = false
var _match_hint: Label
var _deadline_ring: Panel
var _zenith_marker: Label
var _grace_left: float = 0.0
var _practice_done: bool = false
static var _rules_auto_shown: bool = false

func _ready() -> void:
	if Music and Music.has_method("play_area"):
		Music.play_area("well_defence")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_obj.text = "Seeing Well — flick disc to zenith · tap matching wisp on the gold ring"
	_show_toast("Learn the disc first — calm open, then one practice wisp.", 3.4)
	if not _rules_auto_shown:
		_rules_auto_shown = true
		call_deferred("_toggle_rules")

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and _toast:
			_toast.visible = false
	_rock_t += delta
	_update_wheel(delta)
	_draw_wheel_runes()
	_update_match_teach(delta)
	if _ended or not _playing:
		return
	_game_t += delta
	if _grace_left > 0.0:
		_grace_left = maxf(0.0, _grace_left - delta)
		_update_hud()
		return
	_spawn_tick(delta)
	_update_wisps(delta)
	_draw_wisps()
	_update_hud()

func _show_toast(msg: String, dur: float = 2.2) -> void:
	if _toast:
		_toast.text = msg
		_toast.visible = true
	_toast_t = dur

func _mk_style(bg: Color, rad: float = 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = int(rad)
	s.corner_radius_top_right = int(rad)
	s.corner_radius_bottom_right = int(rad)
	s.corner_radius_bottom_left = int(rad)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.11, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_obj = Label.new()
	_obj.add_theme_font_size_override("font_size", 15)
	_obj.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0))
	_obj.add_theme_stylebox_override("normal", _mk_style(Color(0.10, 0.08, 0.16, 0.9), 8))
	_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_obj.offset_left = 10
	_obj.offset_right = -10
	_obj.offset_top = 4
	_obj.offset_bottom = 28
	add_child(_obj)

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 13)
	_hud.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_left = 10
	_hud.offset_right = -10
	_hud.offset_top = 28
	_hud.offset_bottom = 48
	add_child(_hud)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.92))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status.offset_left = 10
	_status.offset_right = -10
	_status.offset_top = 48
	_status.offset_bottom = 68
	_status.text = "Bigger board below — flick disc so Inf/Arch/Cav is at ▲ zenith, tap on gold ring."
	add_child(_status)

	_match_hint = Label.new()
	_match_hint.add_theme_font_size_override("font_size", 14)
	_match_hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_match_hint.add_theme_stylebox_override("normal", _mk_style(Color(0.12, 0.09, 0.18, 0.88), 8))
	_match_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_match_hint.offset_left = 16
	_match_hint.offset_right = -16
	_match_hint.offset_top = 68
	_match_hint.offset_bottom = 92
	_match_hint.text = "Zenith: Inf — matching wisps glow · gold ring = tap window"
	add_child(_match_hint)

	_board = Control.new()
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.offset_left = 4
	_board.offset_right = -4
	_board.offset_top = 96
	_board.offset_bottom = -168
	_board.clip_contents = true
	add_child(_board)

	## Bottom wheel zone (compact — more room for the play board)
	_wheel_panel = Control.new()
	_wheel_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_wheel_panel.offset_left = 8
	_wheel_panel.offset_right = -8
	_wheel_panel.offset_top = -160
	_wheel_panel.offset_bottom = -4
	add_child(_wheel_panel)

	var wheel_hint := Label.new()
	wheel_hint.text = "Sunrise Wheel — flick · ▲ TOP rune = zenith (match that letter)"
	wheel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wheel_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	wheel_hint.offset_top = 0
	wheel_hint.offset_bottom = 18
	wheel_hint.add_theme_font_size_override("font_size", 11)
	wheel_hint.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	_wheel_panel.add_child(wheel_hint)

	_wheel_disc = Panel.new()
	_wheel_disc.set_anchors_preset(Control.PRESET_CENTER)
	_wheel_disc.anchor_left = 0.5
	_wheel_disc.anchor_right = 0.5
	_wheel_disc.anchor_top = 0.5
	_wheel_disc.anchor_bottom = 0.5
	_wheel_disc.offset_left = -64
	_wheel_disc.offset_right = 64
	_wheel_disc.offset_top = -48
	_wheel_disc.offset_bottom = 72
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.18, 0.12, 0.28, 0.95)
	wsb.border_color = Color(0.95, 0.75, 0.35)
	wsb.set_border_width_all(3)
	wsb.set_corner_radius_all(70)
	_wheel_disc.add_theme_stylebox_override("panel", wsb)
	_wheel_disc.gui_input.connect(_on_wheel_input)
	_wheel_panel.add_child(_wheel_disc)

	## Zenith marker (fixed at top of disc) — strong teach cue
	_zenith_marker = Label.new()
	_zenith_marker.text = "▲ ZENITH"
	_zenith_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zenith_marker.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_zenith_marker.anchor_left = 0.5
	_zenith_marker.anchor_right = 0.5
	_zenith_marker.offset_left = -56
	_zenith_marker.offset_right = 56
	_zenith_marker.offset_top = -6
	_zenith_marker.offset_bottom = 18
	_zenith_marker.add_theme_font_size_override("font_size", 13)
	_zenith_marker.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
	_zenith_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel_disc.add_child(_zenith_marker)

	for i in range(RUNE_SNAP):
		var lab := Button.new()
		lab.focus_mode = Control.FOCUS_NONE
		lab.flat = true
		lab.alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.text = TROOP_LETTER[i]
		lab.add_theme_font_size_override("font_size", 22)
		lab.mouse_filter = Control.MOUSE_FILTER_STOP
		lab.size = Vector2(44, 36)
		lab.pressed.connect(_on_tap_zenith)
		lab.gui_input.connect(_on_rune_button_input.bind(lab))
		_wheel_disc.add_child(lab)
		_rune_labels.append(lab)

	_zenith_btn = Button.new()
	_zenith_btn.focus_mode = Control.FOCUS_NONE
	_zenith_btn.text = "TAP RUNE"
	_zenith_btn.custom_minimum_size = Vector2(150, 48)
	_zenith_btn.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_zenith_btn.anchor_left = 1.0
	_zenith_btn.anchor_right = 1.0
	_zenith_btn.anchor_top = 0.5
	_zenith_btn.anchor_bottom = 0.5
	_zenith_btn.offset_left = -168
	_zenith_btn.offset_right = -8
	_zenith_btn.offset_top = -24
	_zenith_btn.offset_bottom = 24
	_zenith_btn.add_theme_font_size_override("font_size", 15)
	_zenith_btn.pressed.connect(_on_tap_zenith)
	_wheel_panel.add_child(_zenith_btn)

	_btn_start = Button.new()
	_btn_start.focus_mode = Control.FOCUS_NONE
	_btn_start.text = "Start wave"
	_btn_start.custom_minimum_size = Vector2(130, 44)
	_btn_start.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_btn_start.anchor_left = 0.0
	_btn_start.anchor_right = 0.0
	_btn_start.anchor_top = 0.5
	_btn_start.anchor_bottom = 0.5
	_btn_start.offset_left = 8
	_btn_start.offset_right = 138
	_btn_start.offset_top = -22
	_btn_start.offset_bottom = 22
	_btn_start.add_theme_font_size_override("font_size", 14)
	_btn_start.pressed.connect(_on_start)
	_wheel_panel.add_child(_btn_start)

	_btn_back = Button.new()
	_btn_back.focus_mode = Control.FOCUS_NONE
	_btn_back.text = "Back"
	_btn_back.custom_minimum_size = Vector2(90, 40)
	_btn_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_btn_back.offset_left = 12
	_btn_back.offset_right = 102
	_btn_back.offset_top = -44
	_btn_back.offset_bottom = -4
	_btn_back.pressed.connect(_on_back)
	_wheel_panel.add_child(_btn_back)

	_btn_rules = Button.new()
	_btn_rules.focus_mode = Control.FOCUS_NONE
	_btn_rules.text = "Help / Rules"
	_btn_rules.custom_minimum_size = Vector2(118, 40)
	_btn_rules.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_btn_rules.offset_left = -130
	_btn_rules.offset_right = -8
	_btn_rules.offset_top = -44
	_btn_rules.offset_bottom = -4
	_btn_rules.add_theme_font_size_override("font_size", 15)
	_btn_rules.pressed.connect(_toggle_rules)
	_wheel_panel.add_child(_btn_rules)

	_toast = Label.new()
	_toast.visible = false
	_toast.z_index = 30
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 15)
	_toast.add_theme_color_override("font_color", Color(0.95, 0.9, 1.0))
	_toast.add_theme_stylebox_override("normal", _mk_style(Color(0.12, 0.08, 0.18, 0.94), 8))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 94
	_toast.offset_bottom = 128
	add_child(_toast)

	_result = Label.new()
	_result.visible = false
	_result.z_index = 25
	_result.set_anchors_preset(Control.PRESET_CENTER)
	_result.offset_left = -220
	_result.offset_right = 220
	_result.offset_top = -30
	_result.offset_bottom = 30
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 18)
	_result.add_theme_stylebox_override("normal", _mk_style(Color(0.10, 0.08, 0.16, 0.95), 10))
	add_child(_result)

	_build_rules_panel()
	call_deferred("_build_board")

func _axis_dir(axis: int) -> Vector2:
	var ang := float(axis) * TAU / float(AXIS_COUNT) - PI * 0.5
	return Vector2(cos(ang), sin(ang))

func _build_board() -> void:
	for child in _board.get_children():
		child.queue_free()
	_axis_guides.clear()

	var bw := maxf(_board.size.x, 400.0)
	var bh := maxf(_board.size.y, 380.0)
	_well_pos = Vector2(bw * 0.5, bh * 0.50)
	var rim_r := minf(bw, bh) * 0.46  ## larger play radius — board was cramped

	## Axis ribbons (uneven opacity by weight)
	for axis in range(AXIS_COUNT):
		var d := _axis_dir(axis)
		var line := ColorRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := float(AXIS_WEIGHTS[axis])
		line.color = Color(0.45, 0.25, 0.70, 0.12 + w * 0.08)
		line.size = Vector2(10.0 + w * 4.0, rim_r)
		line.pivot_offset = Vector2(line.size.x * 0.5, rim_r)
		line.position = _well_pos - Vector2(line.size.x * 0.5, rim_r)
		line.rotation = d.angle() + PI * 0.5
		_board.add_child(line)
		_axis_guides.append(line)

		## Deadline ring tick
		var tick := ColorRect.new()
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.color = Color(1.0, 0.85, 0.35, 0.55)
		tick.size = Vector2(14, 4)
		var dpos := _well_pos + d * (rim_r * DEADLINE_PROGRESS / 1.0)
		## progress 1 at rim, 0 at well → distance = rim_r * progress
		dpos = _well_pos + d * (rim_r * DEADLINE_PROGRESS)
		tick.position = dpos - Vector2(7, 2)
		_board.add_child(tick)

	## Gold deadline ring — thicker / clearer teach target
	_deadline_ring = Panel.new()
	_deadline_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rr := rim_r * DEADLINE_PROGRESS
	_deadline_ring.position = _well_pos - Vector2(rr, rr)
	_deadline_ring.size = Vector2(rr * 2.0, rr * 2.0)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(1.0, 0.85, 0.30, 0.06)
	rsb.border_color = Color(1.0, 0.88, 0.35, 0.70)
	rsb.set_border_width_all(4)
	rsb.set_corner_radius_all(int(rr))
	_deadline_ring.add_theme_stylebox_override("panel", rsb)
	_board.add_child(_deadline_ring)
	var ring_lab := Label.new()
	ring_lab.text = "GOLD RING — tap here"
	ring_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ring_lab.add_theme_font_size_override("font_size", 11)
	ring_lab.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45, 0.85))
	ring_lab.position = Vector2(0, -18)
	ring_lab.size = Vector2(rr * 2.0, 16)
	_deadline_ring.add_child(ring_lab)
	_board.set_meta("rim_r", rim_r)

	## Centre well
	_well_panel = PanelContainer.new()
	_well_panel.position = _well_pos - Vector2(42, 42)
	_well_panel.size = Vector2(84, 84)
	var ws := StyleBoxFlat.new()
	ws.bg_color = Color(0.35, 0.15, 0.70, 0.95)
	ws.border_color = Color(0.85, 0.50, 1.0)
	ws.set_border_width_all(3)
	ws.set_corner_radius_all(42)
	_well_panel.add_theme_stylebox_override("panel", ws)
	_well_label = Label.new()
	_well_label.text = "Seeing\nWell"
	_well_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_well_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_well_label.add_theme_font_size_override("font_size", 13)
	_well_label.add_theme_color_override("font_color", Color(0.95, 0.88, 1.0))
	_well_panel.add_child(_well_label)
	_board.add_child(_well_panel)

	_wisp_layer = Control.new()
	_wisp_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wisp_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.add_child(_wisp_layer)

	_fx_layer = Control.new()
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.add_child(_fx_layer)

	_draw_wheel_runes()
	_update_hud()

func _wisp_pos(axis: int, progress: float) -> Vector2:
	var rim_r: float = float(_board.get_meta("rim_r", 160.0))
	return _well_pos + _axis_dir(axis) * (rim_r * progress)

func _pick_weighted_axis() -> int:
	var total := 0.0
	for w in AXIS_WEIGHTS:
		total += float(w)
	var r := randf() * total
	var acc := 0.0
	for i in range(AXIS_COUNT):
		acc += float(AXIS_WEIGHTS[i])
		if r <= acc:
			return i
	return 0

func _on_start() -> void:
	if _ended or _playing:
		return
	if _board.get_child_count() == 0:
		_build_board()
	_playing = true
	_spawned = 0
	_cleared = 0
	_practice_done = false
	_grace_left = GRACE_BEFORE_SPAWN
	_spawn_timer = 0.15
	_game_t = 0.0
	_wisps.clear()
	for c in _wisp_layer.get_children():
		c.queue_free()
	_btn_start.disabled = true
	_btn_start.text = "Wave running…"
	_obj.text = "Calm open — practice the disc · then match letters on the gold ring"
	_show_toast("Calm moment — flick Inf/Arch/Cav to ▲ zenith. First wisp is practice.", 4.2)
	_update_hud()

func _spawn_tick(delta: float) -> void:
	if _spawned >= WAVE_WISP_COUNT:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	## Slow early ramp → denser late (still fairer than old 0.85 cadence)
	var t := float(_spawned) / float(max(1, WAVE_WISP_COUNT - 1))
	var gap := lerpf(FIRST_SPAWN_GAP, LATE_SPAWN_GAP, t) + randf() * 0.35
	_spawn_timer = gap
	var axis := _pick_weighted_axis()
	var kind := Troop.INF
	var practice := _spawned < PRACTICE_COUNT
	if practice:
		kind = Troop.INF
		axis = 0  ## top arm — easiest to see
	else:
		var roll := randf()
		var real_i := _spawned - PRACTICE_COUNT
		if real_i < 3:
			kind = Troop.INF if roll < 0.55 else (Troop.ARCH if roll < 0.85 else Troop.CAV)
		elif real_i < 7:
			kind = Troop.ARCH if roll < 0.40 else (Troop.INF if roll < 0.70 else Troop.CAV)
		else:
			kind = Troop.CAV if roll < 0.40 else (Troop.ARCH if roll < 0.70 else Troop.INF)
	_wisps.append({
		"axis": axis,
		"progress": 1.0,
		"kind": kind,
		"spin": randf() * TAU,
		"node": null,
		"practice": practice,
		"speed_mul": 0.55 if practice else (0.70 if _spawned < PRACTICE_COUNT + 2 else (0.85 if _spawned < PRACTICE_COUNT + 5 else 1.0)),
	})
	_spawned += 1
	if practice:
		_show_toast("PRACTICE Inf — flick Inf to ▲ zenith, tap when it hits the gold ring", 3.5)
	elif _spawned == PRACTICE_COUNT + 1:
		_show_toast("Real wisps now — clear the wave. Miss the well and you lose.", 2.8)

func _wisp_speed(w: Dictionary) -> float:
	## Ramp: slow open → modest late pressure (never old instant-kill pace)
	var ramp := clampf(float(_cleared) / 8.0, 0.0, 1.0)
	var base := lerpf(SPIRAL_SPEED, SPIRAL_SPEED_MAX, ramp)
	var axis_f := 0.90 + float(AXIS_WEIGHTS[int(w["axis"]) % AXIS_COUNT]) * 0.08
	return base * axis_f * float(w.get("speed_mul", 1.0))

func _update_wisps(delta: float) -> void:
	for i in range(_wisps.size()):
		var w: Dictionary = _wisps[i]
		w["spin"] = float(w["spin"]) + delta * 1.1
		w["progress"] = float(w["progress"]) - _wisp_speed(w) * delta
		if float(w["progress"]) <= WELL_HIT_PROGRESS:
			if bool(w.get("practice", false)):
				## Practice miss: bounce back to rim, keep teaching — no lose
				w["progress"] = 1.0
				_show_toast("Practice miss — flick Inf to zenith, tap on the gold ring", 2.4)
			else:
				_lose()
				return
	if _spawned >= WAVE_WISP_COUNT and _wisps.is_empty() and not _ended:
		_win()

func _draw_wisps() -> void:
	var zen := _zenith_troop()
	for w in _wisps:
		var node: Panel = w.get("node")
		var kind: int = int(w["kind"])
		var col: Color = TROOP_COLOR[kind]
		var matches := kind == zen
		var practice := bool(w.get("practice", false))
		if node == null or not is_instance_valid(node):
			node = Panel.new()
			node.custom_minimum_size = Vector2(44, 44)
			node.size = Vector2(44, 44)
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(22)
			sb.set_border_width_all(3)
			sb.border_color = Color(1, 1, 1, 0.85)
			node.add_theme_stylebox_override("panel", sb)
			var lab := Label.new()
			lab.name = "L"
			lab.text = TROOP_LETTER[kind]
			lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lab.add_theme_font_size_override("font_size", 19)
			lab.add_theme_color_override("font_color", Color(0.05, 0.04, 0.08))
			lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.add_child(lab)
			if practice:
				var tag := Label.new()
				tag.name = "P"
				tag.text = "PRACTICE"
				tag.position = Vector2(-8, -14)
				tag.size = Vector2(60, 14)
				tag.add_theme_font_size_override("font_size", 9)
				tag.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
				tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
				node.add_child(tag)
			_wisp_layer.add_child(node)
			w["node"] = node
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = col.lightened(0.12) if practice else col
		sb2.set_corner_radius_all(22)
		if matches:
			sb2.border_color = Color(1.0, 0.92, 0.30, 1.0)
			sb2.set_border_width_all(4)
		else:
			sb2.border_color = Color(1, 1, 1, 0.40)
			sb2.set_border_width_all(2)
		node.add_theme_stylebox_override("panel", sb2)
		var base := _wisp_pos(int(w["axis"]), float(w["progress"]))
		var tang := Vector2(-_axis_dir(int(w["axis"])).y, _axis_dir(int(w["axis"])).x)
		var wobble := sin(float(w["spin"])) * 10.0 * float(w["progress"])
		node.position = base + tang * wobble - Vector2(22, 22)
		var p := float(w["progress"])
		var in_window := absf(p - DEADLINE_PROGRESS) <= DEADLINE_WINDOW
		if in_window and matches:
			node.modulate = Color(1.45, 1.35, 0.85, 1.0)
			node.scale = Vector2(1.30, 1.30)
		elif matches:
			node.modulate = Color(1.22, 1.15, 1.0, 1.0)
			node.scale = Vector2(1.14, 1.14)
		elif in_window:
			node.modulate = Color(1.08, 1.05, 0.95, 0.95)
			node.scale = Vector2(1.08, 1.08)
		else:
			node.modulate = Color(0.82, 0.82, 0.86, 0.88)
			node.scale = Vector2.ONE

func _zenith_troop() -> int:
	## Rune i is drawn at (-PI/2 + i*step + wheel_angle). Find which is nearest zenith.
	var step := TAU / float(RUNE_SNAP)
	var best := 0
	var best_d := 999.0
	for i in range(RUNE_SNAP):
		var ang := fposmod(float(i) * step + _wheel_angle, TAU)
		var d := absf(angle_difference(0.0, ang))
		if d < best_d:
			best_d = d
			best = i
	return best  ## 0 Inf, 1 Arch, 2 Cav

func _draw_wheel_runes() -> void:
	if _rune_labels.is_empty() or _wheel_disc == null:
		return
	var cx := _wheel_disc.size.x * 0.5
	var cy := _wheel_disc.size.y * 0.5
	var radius := 48.0
	## Uneven rock: disc tilts slightly
	var rock := sin(_rock_t * 1.7) * WHEEL_ROCK_AMP + sin(_rock_t * 0.9) * WHEEL_ROCK_AMP * 0.5
	_wheel_disc.rotation = rock * 0.35
	var zen := _zenith_troop()
	for i in range(RUNE_SNAP):
		var lab: Button = _rune_labels[i]
		var ang := -PI * 0.5 + float(i) * TAU / float(RUNE_SNAP) + _wheel_angle
		lab.text = TROOP_LETTER[i]
		lab.add_theme_color_override("font_color", TROOP_COLOR[i])
		lab.position = Vector2(cx + cos(ang) * radius - 22.0, cy + sin(ang) * radius - 18.0)
		if i == zen:
			lab.add_theme_font_size_override("font_size", 28)
			lab.modulate = Color(1.3, 1.2, 0.85, 1.0)
		else:
			lab.add_theme_font_size_override("font_size", 18)
			lab.modulate = Color(0.75, 0.75, 0.8, 0.85)
	if _zenith_marker:
		var zen_pulse := 0.82 + 0.18 * sin(_rock_t * 4.2)
		_zenith_marker.modulate = Color(1.0, 0.95, 0.4, zen_pulse)
		_zenith_marker.text = "▲ ZENITH · %s" % TROOP_NAME[zen]
	if _zenith_btn:
		var z := zen
		_zenith_btn.text = "TAP %s" % TROOP_NAME[z]
		var ready := false
		for w in _wisps:
			if int(w["kind"]) == z and absf(float(w["progress"]) - DEADLINE_PROGRESS) <= DEADLINE_WINDOW:
				ready = true
				break
		if ready:
			_teach_pulse += 0.12
			var tap_pulse := 0.85 + 0.15 * sin(_teach_pulse * 6.0)
			_zenith_btn.modulate = Color(1.2, 1.05, 0.55, 1.0) * tap_pulse
			_zenith_btn.text = "TAP %s NOW" % TROOP_NAME[z]
			if not _taught_zenith:
				_taught_zenith = true
		else:
			_zenith_btn.modulate = TROOP_COLOR[z].lightened(0.25)

func _update_wheel(delta: float) -> void:
	if not _dragging:
		## Weighted rock + friction on spin
		_wheel_vel = lerpf(_wheel_vel, 0.0, clampf(WHEEL_FRICTION * delta, 0.0, 1.0))
		## Soft bias toward nearest rune (uneven detent)
		var step := TAU / float(RUNE_SNAP)
		var nearest := roundf(_wheel_angle / step) * step
		var pull := angle_difference(_wheel_angle, nearest) * 1.8
		_wheel_vel += pull * delta
		_wheel_angle += _wheel_vel * delta
	_wheel_angle = fposmod(_wheel_angle, TAU)

func _on_wheel_input(event: InputEvent) -> void:
	if _ended:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_begin_wheel_press(st.position)
		else:
			_finish_wheel_press(st.position, true)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_drag_wheel_to(sd.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_wheel_press(mb.position)
			else:
				_finish_wheel_press(mb.position, true)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_wheel_to(mm.position)

func _on_rune_button_input(event: InputEvent, button: Button) -> void:
	## Rune buttons own their short taps; forward drags so the disc remains spin-able.
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var pos := button.position + st.position
		if st.pressed:
			_begin_wheel_press(pos)
		else:
			_finish_wheel_press(pos, false)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_drag_wheel_to(button.position + sd.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var pos := button.position + mb.position
			if mb.pressed:
				_begin_wheel_press(pos)
			else:
				_finish_wheel_press(pos, false)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_wheel_to(button.position + mm.position)

func _begin_wheel_press(pos: Vector2) -> void:
	_dragging = true
	_drag_last = pos
	_wheel_press_pos = pos
	_wheel_moved = false
	_wheel_vel = 0.0

func _finish_wheel_press(pos: Vector2, tap_on_release: bool) -> void:
	var short_tap := not _wheel_moved and _wheel_press_pos.distance_to(pos) < 12.0
	_dragging = false
	if tap_on_release and short_tap:
		_on_tap_zenith()

func _drag_wheel_to(pos: Vector2) -> void:
	if _wheel_press_pos.distance_to(pos) >= 12.0:
		_wheel_moved = true
	_apply_drag(pos)

func _apply_drag(local_pos: Vector2) -> void:
	var centre := _wheel_disc.size * 0.5
	var a0 := (_drag_last - centre).angle()
	var a1 := (local_pos - centre).angle()
	var da := angle_difference(a0, a1)
	_wheel_angle = fposmod(_wheel_angle + da, TAU)
	_wheel_vel = da * 18.0
	_drag_last = local_pos

func _on_tap_zenith() -> void:
	if _ended or not _playing:
		_show_toast("Start the wave first — open Help / Rules if needed", 1.6)
		return
	var zen := _zenith_troop()
	var best_i := -1
	var best_dist := 999.0
	for i in range(_wisps.size()):
		var w: Dictionary = _wisps[i]
		if int(w["kind"]) != zen:
			continue
		var dist := absf(float(w["progress"]) - DEADLINE_PROGRESS)
		if dist <= DEADLINE_WINDOW and dist < best_dist:
			best_dist = dist
			best_i = i
	if best_i < 0:
		_show_toast("No %s on the gold ring — wait for glow, or flick to match" % TROOP_NAME[zen], 1.6)
		## Soft miss after teach clears only
		if _cleared >= 3:
			for w in _wisps:
				if int(w["kind"]) == zen and not bool(w.get("practice", false)):
					w["progress"] = maxf(WELL_HIT_PROGRESS + 0.04, float(w["progress"]) - 0.025)
					break
		return
	_detonate(best_i)

func _detonate(idx: int) -> void:
	if idx < 0 or idx >= _wisps.size():
		return
	var w: Dictionary = _wisps[idx]
	var pos := _wisp_pos(int(w["axis"]), float(w["progress"]))
	_flash_at(pos, TROOP_COLOR[int(w["kind"])])
	if w.get("node") != null and is_instance_valid(w["node"]):
		w["node"].queue_free()
	_wisps.remove_at(idx)
	var was_practice := bool(w.get("practice", false))
	if was_practice:
		_practice_done = true
	_cleared += 1
	if was_practice:
		_show_toast("Practice cleared — real wisps next. Same flick + tap.", 2.4)
	else:
		_show_toast("Detonated %s! (%d/%d)" % [TROOP_NAME[int(w["kind"])], _cleared, WAVE_WISP_COUNT], 1.2)
	_update_hud()
	if _spawned >= WAVE_WISP_COUNT and _wisps.is_empty() and not _ended:
		_win()

func _flash_at(pos: Vector2, col: Color) -> void:
	if _fx_layer == null:
		return
	var f := ColorRect.new()
	f.size = Vector2(36, 36)
	f.position = pos - Vector2(18, 18)
	f.color = col
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(f)
	var tw := create_tween()
	tw.tween_property(f, "modulate:a", 0.0, 0.35)
	tw.tween_callback(f.queue_free)

func _update_hud() -> void:
	var zname: String = TROOP_NAME[_zenith_troop()]
	_hud.text = "Cleared %d/%d · On board %d · Zenith %s" % [
		_cleared, WAVE_WISP_COUNT, _wisps.size(), zname
	]
	if not _playing and not _ended:
		_status.text = "Help / Rules opens first · flick the disc · Start when ready"
	elif _playing and _grace_left > 0.0:
		_status.text = "Calm open — %.0fs left · put a rune under ▲ zenith before wisps" % _grace_left
	elif _playing and not _ended:
		_status.text = "Glow = match to zenith · tap TAP %s when it hits the gold ring" % zname

func _win() -> void:
	if _ended:
		return
	_ended = true
	_playing = false
	_result.visible = true
	_result.text = "Well held! Sunrise clears the shadow — Back"
	_result.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	_obj.text = "Victory — the Seeing Well is safe"
	_show_toast("The glow steadies. Well held!", 3.5)
	if GameState:
		GameState.well_defence_won = true
	_zenith_btn.disabled = true
	_btn_start.disabled = true

func _lose() -> void:
	if _ended:
		return
	_ended = true
	_playing = false
	_result.visible = true
	_result.text = "A wisp drank the well — Back to try again"
	_result.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_obj.text = "Defeat — the Seeing Well fell"
	_show_toast("Shadow drinks the well…", 3.5)
	_zenith_btn.disabled = true
	_btn_start.disabled = true

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/tree_well_room.tscn")

func _build_rules_panel() -> void:
	_rules_panel = Control.new()
	_rules_panel.visible = false
	_rules_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rules_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_rules_panel.z_index = 40
	add_child(_rules_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_toggle_rules()
	)
	_rules_panel.add_child(dim)

	var sheet := PanelContainer.new()
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.anchor_left = 0.5
	sheet.anchor_right = 0.5
	sheet.anchor_top = 0.5
	sheet.anchor_bottom = 0.5
	sheet.offset_left = -200
	sheet.offset_right = 200
	sheet.offset_top = -280
	sheet.offset_bottom = 280
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.14, 0.98)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.75, 0.65, 0.40)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sheet.add_theme_stylebox_override("panel", sb)
	_rules_panel.add_child(sheet)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	sheet.add_child(v)

	var hdr := Label.new()
	hdr.text = "Help / Rules"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
	v.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	var body := Label.new()
	body.text = RULES_TEXT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
	scroll.add_child(body)
	body.custom_minimum_size = Vector2(360, 0)

	var close_btn := Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_toggle_rules)
	v.add_child(close_btn)


func _update_match_teach(_delta: float) -> void:
	## Live disc/zenith/gold-ring coach line (learnable, not dead in ~3s).
	if _match_hint == null:
		return
	var z := _zenith_troop()
	var zname: String = TROOP_NAME[z]
	if not _playing:
		_match_hint.text = "Flick the disc so a letter sits under ▲ ZENITH — then Start"
		_match_hint.modulate = Color(0.9, 0.9, 1.0, 1.0)
		return
	if _grace_left > 0.0:
		_match_hint.text = "Calm open (%.0fs) — practice lining %s under ▲ ZENITH" % [_grace_left, zname]
		_match_hint.modulate = Color(0.85, 0.95, 1.0, 1.0)
		return
	var in_ring := false
	var ring_kind := -1
	for w in _wisps:
		if absf(float(w["progress"]) - DEADLINE_PROGRESS) <= DEADLINE_WINDOW:
			in_ring = true
			ring_kind = int(w["kind"])
			if int(w["kind"]) == z:
				break
	if in_ring and ring_kind == z:
		_match_hint.text = "NOW — %s on gold ring matches zenith · TAP RUNE" % zname
		_match_hint.modulate = Color(1.15, 1.05, 0.55, 1.0)
		if _deadline_ring:
			_deadline_ring.modulate = Color(1.25, 1.15, 0.7, 1.0)
		if _zenith_marker:
			_zenith_marker.modulate = Color(1.3, 1.2, 0.6, 1.0)
	elif in_ring:
		_match_hint.text = "Wisp on gold ring — flick disc to %s under ▲ ZENITH" % TROOP_NAME[ring_kind]
		_match_hint.modulate = Color(1.0, 0.85, 0.55, 1.0)
		if _deadline_ring:
			_deadline_ring.modulate = Color(1.1, 1.0, 0.8, 1.0)
	else:
		var match_n := 0
		for w2 in _wisps:
			if int(w2["kind"]) == z:
				match_n += 1
		if match_n > 0:
			_match_hint.text = "Match the glowing %s wisp — tap when it reaches the gold ring" % zname
		else:
			_match_hint.text = "Zenith: %s — flick disc if you need another letter" % zname
		_match_hint.modulate = Color(1.0, 0.92, 0.55, 1.0)
		if _deadline_ring:
			_deadline_ring.modulate = Color(1, 1, 1, 1)
		if _zenith_marker:
			_zenith_marker.modulate = Color(1, 1, 1, 1)


func _toggle_rules() -> void:
	_rules_visible = not _rules_visible
	if _rules_panel:
		_rules_panel.visible = _rules_visible
	if _btn_rules:
		_btn_rules.text = "Close Help" if _rules_visible else "Help / Rules"


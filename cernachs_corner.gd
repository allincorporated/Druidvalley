extends Control
## Cernach's Corner — Inf/Arch/Cav duel with simultaneous resolve.
## Six troop moves have distinct code paths (not label reskins).
## Triangle Inf > Cav > Arch > Inf. Going second is viable.

const YARD_SCENE := "res://scenes/druid_yard.tscn"
const PLAYER_MAX_HP := 100
const ENEMY_MAX_HP := 100
const STRIKE_BASE := 8
const BUFF_DURATION := 2
const MAX_HIT := 16
const MIN_HIT := 4
const RALLY_HEAL := 10
const RALLY_CHIP := 3
## March strength push added to Strike this resolve / while buff lives.
const MARCH_STRIKE_BONUS := 4
## Charge spike on top of Strike base (before def mods).
const CHARGE_SPIKE := 7
## Flank chip returned when foe March/Volley lands.
const FLANK_CHIP := 3
## Volley pierce fraction vs Shield Wall reduction.
const VOLLEY_SHIELD_PIERCE := 0.55

## Each move: label, group, kind, short rules blurb. Effects live in resolve code.
const TROOP_BUFFS := {
	"march": {
		"label": "March", "stat": "str", "kind": "atk", "group": "inf",
		"icon": "⚔", "beats": "cav", "counters": "",
		"blurb": "Strength push — +Strike damage this turn; telegraphs advance.",
	},
	"shield": {
		"label": "Shield Wall", "stat": "str", "kind": "def", "group": "inf",
		"icon": "🛡", "beats": "", "counters": "cav",
		"blurb": "Hard cut vs Charge/March; weak vs Volley pierce.",
	},
	"volley": {
		"label": "Volley", "stat": "agi", "kind": "atk", "group": "arch",
		"icon": "🏹", "beats": "inf", "counters": "",
		"blurb": "Ranged — partially ignores Shield Wall; soft vs Flank.",
	},
	"skirmish": {
		"label": "Skirmish", "stat": "agi", "kind": "def", "group": "arch",
		"icon": "↺", "beats": "", "counters": "inf",
		"blurb": "Cuts hit chance/dmg from March & Charge; little vs Volley.",
	},
	"charge": {
		"label": "Charge", "stat": "str", "kind": "atk", "group": "cav",
		"icon": "🐴", "beats": "arch", "counters": "",
		"blurb": "Spike damage; strong vs Archers; blunted hard by Shield Wall.",
	},
	"flank": {
		"label": "Flank", "stat": "wis", "kind": "def", "group": "cav",
		"icon": "↗", "beats": "", "counters": "arch",
		"blurb": "If foe March/Volley: chip back & cut their bonus; weak vs Shield grind.",
	},
}

const TROOP_ORDER: PackedStringArray = ["march", "shield", "volley", "skirmish", "charge", "flank"]
const STAT_LABELS := {"str": "Strength", "agi": "Agility", "wis": "Wisdom"}
const GENERAL_ACTIONS := ["strike", "rally", "hold"]

const RULES_TEXT := """CERNACH'S CORNER — RULES

HOW A TURN WORKS
• Pick one troop move + one General action, then tap Resolve.
• Both sides choose and act together (simultaneous). Going second does not auto-lose.
• Buffs last 2 turns; picking the same move again stacks its bonus.

TROOP MOVES (one offence + one defence per type)

Infantry
• March (offence): Strength push — bonus Strike damage this turn; telegraphs advance.
• Shield Wall (defence): Cuts incoming hard vs Charge/March; weaker vs Volley.

Archer
• Volley (offence): Ranged — damage that partially ignores Shield Wall; softer vs Flank.
• Skirmish (defence): Reduces hit chance / damage from March & Charge; little help vs Volley.

Cavalry
• Charge (offence): Big spike damage; strong vs Archers; blunted hard by Shield Wall.
• Flank (defence): If foe March/Volley — chip damage back and cut their bonus; weak vs Shield Wall grind.

TRIANGLE (on top of move effects)
Infantry > Cavalry > Archer > Infantry

GENERAL ACTIONS
• Strike — Deal damage using your active troop offence + stats.
• Rally — Heal +10 HP and deal a light chip.
• Hold — No Strike; gain a defender bonus this resolve (tanking is viable).

Resolve toasts name what changed the numbers (e.g. “Shield Wall blunted Charge”)."""

var _player_hp: int = PLAYER_MAX_HP
var _enemy_hp: int = ENEMY_MAX_HP
## id -> {bonus:int, turns:int, kind:String, stat:String, group:String, ...}
var _player_buffs: Dictionary = {}
var _enemy_buffs: Dictionary = {}
var _selected_buff: String = ""
var _selected_general: String = "strike"
var _busy: bool = false
var _ended: bool = false
var _toast_t: float = 0.0
var _turn: int = 1
var _player_last_offense: String = ""
var _enemy_last_offense: String = ""
## This-resolve pick ids (for move-specific paths).
var _player_pick_id: String = ""
var _enemy_pick_id: String = ""

var _title: Label
var _status: Label
var _player_hp_lbl: Label
var _enemy_hp_lbl: Label
var _player_bar: ProgressBar
var _enemy_bar: ProgressBar
var _player_buff_lbl: Label
var _enemy_buff_lbl: Label
var _player_stats_lbl: Label
var _enemy_stats_lbl: Label
var _toast: Label
var _btn_strike: Button
var _btn_rally: Button
var _btn_hold: Button
var _btn_flee: Button
var _btn_rules: Button
var _troop_btns: Dictionary = {}
var _general_btns: Dictionary = {}
var _rules_panel: Control
var _rules_visible: bool = false
static var _rules_auto_shown: bool = false

var _troop_figs: Dictionary = {"inf": [], "arch": [], "cav": []}
var _enemy_figs: Dictionary = {"inf": [], "arch": [], "cav": []}
var _fig_pulse: Dictionary = {}

func _ready() -> void:
	if Music and Music.has_method("play_area"):
		Music.play_area("chess")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_on_pick_buff("march")
	_refresh_all()
	_show_toast("Simultaneous duel — Help / Rules opens once. Pick troop + General, then Resolve.", 3.0)
	if not _rules_auto_shown:
		_rules_auto_shown = true
		call_deferred("_toggle_rules")

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and _toast:
			_toast.visible = false
	var drop: Array = []
	for fig in _fig_pulse.keys():
		if not is_instance_valid(fig):
			drop.append(fig)
			continue
		_fig_pulse[fig] = float(_fig_pulse[fig]) - delta
		var t := clampf(float(_fig_pulse[fig]) / 0.45, 0.0, 1.0)
		fig.scale = Vector2.ONE * (1.0 + 0.35 * t)
		fig.modulate = Color(1.0 + 0.4 * t, 1.0 + 0.2 * t, 0.85, 1.0)
		fig.position.y = -10.0 * t
		if float(_fig_pulse[fig]) <= 0.0:
			fig.scale = Vector2.ONE
			fig.modulate = Color(1, 1, 1, 1)
			fig.position.y = 0.0
			drop.append(fig)
	for fig in drop:
		_fig_pulse.erase(fig)

func _show_toast(msg: String, dur: float = 2.8) -> void:
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
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.10, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_title = Label.new()
	_title.text = "Cernach's Corner"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
	_title.add_theme_stylebox_override("normal", _mk_style(Color(0.12, 0.09, 0.16, 0.92), 8))
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_left = 24
	_title.offset_right = -24
	_title.offset_top = 8
	_title.offset_bottom = 46
	add_child(_title)

	_status = Label.new()
	_status.text = "Turn 1 — pick troop move + General, then Resolve (simultaneous)."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(0.82, 0.84, 0.92))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status.offset_left = 16
	_status.offset_right = -16
	_status.offset_top = 50
	_status.offset_bottom = 78
	add_child(_status)

	var stage := HBoxContainer.new()
	stage.set_anchors_preset(Control.PRESET_CENTER_TOP)
	stage.anchor_left = 0.5
	stage.anchor_right = 0.5
	stage.offset_left = -420
	stage.offset_right = 420
	stage.offset_top = 82
	stage.offset_bottom = 200
	stage.add_theme_constant_override("separation", 24)
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(stage)

	stage.add_child(_build_troop_panel("Your host", _troop_figs, Color(0.22, 0.38, 0.55), true))
	stage.add_child(_build_troop_panel("Cernach's host", _enemy_figs, Color(0.55, 0.22, 0.22), false))

	var hp_panel := VBoxContainer.new()
	hp_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hp_panel.anchor_left = 0.5
	hp_panel.anchor_right = 0.5
	hp_panel.offset_left = -280
	hp_panel.offset_right = 280
	hp_panel.offset_top = 206
	hp_panel.offset_bottom = 360
	hp_panel.add_theme_constant_override("separation", 3)
	add_child(hp_panel)

	_player_hp_lbl = Label.new()
	_player_hp_lbl.add_theme_font_size_override("font_size", 15)
	_player_hp_lbl.add_theme_color_override("font_color", Color(0.75, 0.95, 0.80))
	hp_panel.add_child(_player_hp_lbl)

	_player_bar = ProgressBar.new()
	_player_bar.min_value = 0
	_player_bar.max_value = PLAYER_MAX_HP
	_player_bar.value = PLAYER_MAX_HP
	_player_bar.custom_minimum_size = Vector2(0, 16)
	_player_bar.show_percentage = false
	hp_panel.add_child(_player_bar)

	_player_stats_lbl = Label.new()
	_player_stats_lbl.add_theme_font_size_override("font_size", 13)
	_player_stats_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.55))
	hp_panel.add_child(_player_stats_lbl)

	_player_buff_lbl = Label.new()
	_player_buff_lbl.add_theme_font_size_override("font_size", 11)
	_player_buff_lbl.add_theme_color_override("font_color", Color(0.70, 0.88, 0.95))
	_player_buff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hp_panel.add_child(_player_buff_lbl)

	_enemy_hp_lbl = Label.new()
	_enemy_hp_lbl.add_theme_font_size_override("font_size", 15)
	_enemy_hp_lbl.add_theme_color_override("font_color", Color(0.95, 0.70, 0.70))
	hp_panel.add_child(_enemy_hp_lbl)

	_enemy_bar = ProgressBar.new()
	_enemy_bar.min_value = 0
	_enemy_bar.max_value = ENEMY_MAX_HP
	_enemy_bar.value = ENEMY_MAX_HP
	_enemy_bar.custom_minimum_size = Vector2(0, 16)
	_enemy_bar.show_percentage = false
	hp_panel.add_child(_enemy_bar)

	_enemy_stats_lbl = Label.new()
	_enemy_stats_lbl.add_theme_font_size_override("font_size", 13)
	_enemy_stats_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.55))
	hp_panel.add_child(_enemy_stats_lbl)

	_enemy_buff_lbl = Label.new()
	_enemy_buff_lbl.add_theme_font_size_override("font_size", 11)
	_enemy_buff_lbl.add_theme_color_override("font_color", Color(0.95, 0.78, 0.70))
	_enemy_buff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hp_panel.add_child(_enemy_buff_lbl)

	var side := VBoxContainer.new()
	side.set_anchors_preset(Control.PRESET_CENTER)
	side.anchor_left = 0.5
	side.anchor_right = 0.5
	side.anchor_top = 0.5
	side.anchor_bottom = 0.5
	side.offset_left = -250
	side.offset_right = 250
	side.offset_top = 55
	side.offset_bottom = 400
	side.add_theme_constant_override("separation", 4)
	add_child(side)

	var troop_hdr := Label.new()
	troop_hdr.text = "1) Troop move  (⚔ offence · 🛡 defence)  Inf>Cav>Arch>Inf"
	troop_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	troop_hdr.add_theme_font_size_override("font_size", 12)
	troop_hdr.add_theme_color_override("font_color", Color(0.90, 0.85, 0.70))
	troop_hdr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(troop_hdr)

	var troop_button_labels := {
		"march": "INF March",
		"shield": "INF Shield",
		"volley": "ARCH Volley",
		"skirmish": "ARCH Skirmish",
		"charge": "CAV Charge",
		"flank": "CAV Flank",
	}
	for id in TROOP_ORDER:
		var info: Dictionary = TROOP_BUFFS[id]
		var b := _mk_order_btn("%s %s" % [info["icon"], troop_button_labels[String(id)]], true)
		var buff_id := String(id)
		b.pressed.connect(func() -> void: _on_pick_buff(buff_id))
		side.add_child(b)
		_troop_btns[buff_id] = b

	var gen_hdr := Label.new()
	gen_hdr.text = "2) General  →  Resolve (both sides act together)"
	gen_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gen_hdr.add_theme_font_size_override("font_size", 12)
	gen_hdr.add_theme_color_override("font_color", Color(0.90, 0.85, 0.70))
	side.add_child(gen_hdr)

	_btn_strike = _mk_order_btn("Strike  (base %d + move effects)" % STRIKE_BASE, true)
	_btn_strike.pressed.connect(func() -> void: _on_pick_general("strike"))
	side.add_child(_btn_strike)
	_general_btns["strike"] = _btn_strike

	_btn_rally = _mk_order_btn("Rally  (+%d HP, light chip)" % RALLY_HEAL, true)
	_btn_rally.pressed.connect(func() -> void: _on_pick_general("rally"))
	side.add_child(_btn_rally)
	_general_btns["rally"] = _btn_rally

	_btn_hold = _mk_order_btn("Hold  (+def this resolve · no Strike)", true)
	_btn_hold.pressed.connect(func() -> void: _on_pick_general("hold"))
	side.add_child(_btn_hold)
	_general_btns["hold"] = _btn_hold

	var resolve_btn := _mk_order_btn("Resolve turn  (simultaneous)", true)
	resolve_btn.custom_minimum_size = Vector2(0, 42)
	resolve_btn.add_theme_font_size_override("font_size", 16)
	resolve_btn.pressed.connect(_on_resolve)
	side.add_child(resolve_btn)
	_general_btns["resolve"] = resolve_btn

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_child(row)

	_btn_rules = Button.new()
	_btn_rules.focus_mode = Control.FOCUS_NONE
	_btn_rules.custom_minimum_size = Vector2(140, 40)
	_btn_rules.text = "Help / Rules"
	_btn_rules.add_theme_font_size_override("font_size", 16)
	_btn_rules.pressed.connect(_toggle_rules)
	row.add_child(_btn_rules)

	_btn_flee = Button.new()
	_btn_flee.focus_mode = Control.FOCUS_NONE
	_btn_flee.custom_minimum_size = Vector2(160, 40)
	_btn_flee.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_flee.text = "Flee / Leave"
	_btn_flee.add_theme_font_size_override("font_size", 16)
	_btn_flee.pressed.connect(_return_to_yard)
	row.add_child(_btn_flee)

	_toast = Label.new()
	_toast.visible = false
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 14)
	_toast.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_toast.add_theme_stylebox_override("normal", _mk_style(Color(0.12, 0.08, 0.18, 0.94), 8))
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_left = 24
	_toast.offset_right = -24
	_toast.offset_top = -96
	_toast.offset_bottom = -16
	add_child(_toast)

	_build_rules_panel()

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
	## Width hint so wrap works inside ScrollContainer.
	body.custom_minimum_size = Vector2(360, 0)

	var close_btn := Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_toggle_rules)
	v.add_child(close_btn)

func _toggle_rules() -> void:
	_rules_visible = not _rules_visible
	if _rules_panel:
		_rules_panel.visible = _rules_visible
	if _btn_rules:
		_btn_rules.text = "Close Help" if _rules_visible else "Help / Rules"

func _build_troop_panel(title: String, store: Dictionary, accent: Color, _friend: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 108)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25, 0.85)
	sb.set_border_width_all(2)
	sb.border_color = accent
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var hdr := Label.new()
	hdr.text = title
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", Color(0.92, 0.9, 0.8))
	v.add_child(hdr)

	var rows := HBoxContainer.new()
	rows.add_theme_constant_override("separation", 18)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(rows)

	for group in ["inf", "arch", "cav"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var gl := Label.new()
		gl.text = {"inf": "Inf", "arch": "Arch", "cav": "Cav"}[group]
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.add_theme_font_size_override("font_size", 11)
		gl.add_theme_color_override("font_color", Color(0.8, 0.82, 0.9))
		col.add_child(gl)
		var fig_row := HBoxContainer.new()
		fig_row.add_theme_constant_override("separation", 3)
		fig_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var count := 3 if group != "cav" else 2
		var letters := {"inf": "I", "arch": "A", "cav": "C"}
		for _i in range(count):
			var fig := _mk_troop_fig(String(letters[group]), accent)
			fig_row.add_child(fig)
			store[group].append(fig)
		col.add_child(fig_row)
		rows.add_child(col)
	return panel

func _mk_troop_fig(letter: String, accent: Color) -> Panel:
	var fig := Panel.new()
	fig.custom_minimum_size = Vector2(28, 36)
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.lightened(0.15)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = accent.darkened(0.25)
	fig.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.text = letter
	lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(0.05, 0.04, 0.04))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fig.add_child(lab)
	fig.pivot_offset = Vector2(14, 36)
	return fig

func _pulse_group(store: Dictionary, group: String) -> void:
	if not store.has(group):
		return
	for fig in store[group]:
		if is_instance_valid(fig):
			_fig_pulse[fig] = 0.45

func _mk_order_btn(label: String, enabled: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	b.text = label
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 13)
	if not enabled:
		b.modulate = Color(0.55, 0.55, 0.58, 0.85)
	return b

func _stat_total(buffs: Dictionary, stat: String) -> int:
	var n := 0
	for id in buffs.keys():
		var e: Dictionary = buffs[id]
		if String(e.get("stat", "")) == stat and int(e.get("turns", 0)) > 0:
			n += int(e.get("bonus", 0))
	return n

func _has_buff(buffs: Dictionary, buff_id: String) -> bool:
	return buffs.has(buff_id) and int(buffs[buff_id].get("turns", 0)) > 0

func _buff_bonus(buffs: Dictionary, buff_id: String) -> int:
	if not _has_buff(buffs, buff_id):
		return 0
	return int(buffs[buff_id].get("bonus", 0))

func _apply_buff(buffs: Dictionary, buff_id: String) -> void:
	var info: Dictionary = TROOP_BUFFS[buff_id]
	var kind := String(info["kind"])
	var stat := String(info["stat"])
	var bonus := 2 if (buffs.has(buff_id) and int(buffs[buff_id].get("turns", 0)) > 0) else 1
	buffs[buff_id] = {
		"bonus": bonus,
		"turns": BUFF_DURATION,
		"kind": kind,
		"stat": stat,
		"group": String(info["group"]),
		"beats": String(info.get("beats", "")),
		"counters": String(info.get("counters", "")),
	}

func _tick_buffs(buffs: Dictionary) -> void:
	var drop: Array = []
	for id in buffs.keys():
		buffs[id]["turns"] = int(buffs[id]["turns"]) - 1
		if int(buffs[id]["turns"]) <= 0:
			drop.append(id)
	for id in drop:
		buffs.erase(id)

func _stats_line(buffs: Dictionary, who: String) -> String:
	return "%s  STR %d · AGI %d · WIS %d" % [
		who,
		_stat_total(buffs, "str"),
		_stat_total(buffs, "agi"),
		_stat_total(buffs, "wis"),
	]

func _buff_summary(buffs: Dictionary, who: String) -> String:
	if buffs.is_empty():
		return "%s buffs: (none)" % who
	var parts: PackedStringArray = []
	for id in TROOP_ORDER:
		if not buffs.has(id):
			continue
		var e: Dictionary = buffs[id]
		var info: Dictionary = TROOP_BUFFS[id]
		var stacked := "×2" if int(e["bonus"]) >= 2 else "+%d" % int(e["bonus"])
		var sn: String = STAT_LABELS.get(String(e.get("stat", "")), "?")
		parts.append("%s%s %s→%s (%dt)" % [info["icon"], info["label"], stacked, sn, int(e["turns"])])
	return "%s: %s" % [who, ", ".join(parts)]

func _active_offense_id(buffs: Dictionary, just_picked: String) -> String:
	## Prefer this turn's pick if offence; else any live atk buff id.
	if just_picked != "" and TROOP_BUFFS.has(just_picked):
		var info: Dictionary = TROOP_BUFFS[just_picked]
		if String(info["kind"]) == "atk":
			return just_picked
	for id in TROOP_ORDER:
		if _has_buff(buffs, id) and String(buffs[id].get("kind", "")) == "atk":
			return String(id)
	return ""

func _active_offense_group(buffs: Dictionary, just_picked: String) -> String:
	var oid := _active_offense_id(buffs, just_picked)
	if oid == "":
		return ""
	return String(TROOP_BUFFS[oid]["group"])

func _matchup_bonus(my_off_group: String, foe_off_group: String) -> int:
	## Triangle Inf > Cav > Arch > Inf → +3
	if my_off_group == "" or foe_off_group == "":
		return 0
	if my_off_group == "inf" and foe_off_group == "cav":
		return 3
	if my_off_group == "cav" and foe_off_group == "arch":
		return 3
	if my_off_group == "arch" and foe_off_group == "inf":
		return 3
	return 0

## Resolve one side's outgoing damage with move-specific paths.
## Returns {dmg:int, notes:PackedStringArray, flank_chip:int}
func _resolve_attack(
	attacker_buffs: Dictionary,
	defender_buffs: Dictionary,
	attacker_pick: String,
	_defender_pick: String,
	defender_offense_group: String,
	defender_held: bool,
	attacker_general: String
) -> Dictionary:
	var notes: PackedStringArray = []
	var flank_chip := 0

	if attacker_general == "hold":
		notes.append("Hold — no Strike")
		return {"dmg": 0, "notes": notes, "flank_chip": 0}

	var atk_off_id := _active_offense_id(attacker_buffs, attacker_pick)
	var atk_off_group := ""
	if atk_off_id != "":
		atk_off_group = String(TROOP_BUFFS[atk_off_id]["group"])

	## --- Base by General ---
	var raw := 0
	if attacker_general == "rally":
		raw = RALLY_CHIP + maxi(0, int(floor(float(_stat_total(attacker_buffs, "str") + _stat_total(attacker_buffs, "agi")) * 0.2)))
		notes.append("Rally chip")
	else:
		## Strike base
		raw = STRIKE_BASE
		## Lightweight wisdom soak (Flank / Hold-adjacent) — small, not the main def.
		raw += _stat_total(attacker_buffs, "str")
		raw += int(floor(float(_stat_total(attacker_buffs, "agi")) * 0.5))
		raw -= int(floor(float(_stat_total(defender_buffs, "wis")) * 0.5))

	## ========== OFFENCE PATHS (distinct) ==========
	match atk_off_id:
		"march":
			## Strength push — bonus Strike this turn / while March lives.
			var push := MARCH_STRIKE_BONUS * maxi(1, _buff_bonus(attacker_buffs, "march"))
			raw += push
			notes.append("March +%d Strike" % push)
		"volley":
			## Agility/ranged — AGI-weighted; pierce handled under Shield Wall.
			var agi_push := 2 + _buff_bonus(attacker_buffs, "volley") * 2
			raw += agi_push
			## Slightly less raw vs pure STR; identity is pierce + triangle.
			notes.append("Volley +%d ranged" % agi_push)
		"charge":
			## Big spike; triangle vs Arch handled below.
			var spike := CHARGE_SPIKE * maxi(1, _buff_bonus(attacker_buffs, "charge"))
			raw += spike
			notes.append("Charge spike +%d" % spike)
		_:
			## Defence pick this turn / no live offence — Strike still hits for base.
			if attacker_general == "strike" and atk_off_id == "":
				notes.append("No offence buff")

	## Triangle on top
	var tri := _matchup_bonus(atk_off_group, defender_offense_group)
	if tri > 0:
		raw += tri
		var names := {"inf": "Inf", "cav": "Cav", "arch": "Arch"}
		notes.append("Triangle %s>%s +%d" % [
			names.get(atk_off_group, "?"), names.get(defender_offense_group, "?"), tri
		])

	## ========== DEFENCE PATHS (distinct) ==========
	## Order matters: Shield Wall vs Charge/March/Volley, Skirmish vs March/Charge,
	## Flank vs March/Volley (chip + cut), Hold flat cut.

	## Shield Wall: hard vs Charge/March; weak vs Volley (pierce).
	if _has_buff(defender_buffs, "shield"):
		var wall_pow := float(_buff_bonus(defender_buffs, "shield"))
		if atk_off_id == "charge":
			## Blunted hard.
			var before := raw
			raw = int(floor(float(raw) * (0.30 - 0.05 * (wall_pow - 1.0))))
			notes.append("Shield Wall blunted Charge (%d→%d)" % [before, raw])
		elif atk_off_id == "march":
			var before2 := raw
			raw = int(floor(float(raw) * (0.40 - 0.05 * (wall_pow - 1.0))))
			notes.append("Shield Wall held vs March (%d→%d)" % [before2, raw])
		elif atk_off_id == "volley":
			## Volley partially ignores Shield Wall.
			var full_cut := float(raw) * 0.55  ## what a hard wall would do
			var pierced := full_cut * (1.0 - VOLLEY_SHIELD_PIERCE)
			var before3 := raw
			raw = int(floor(float(raw) - pierced))
			notes.append("Volley pierced armour (%d→%d)" % [before3, raw])
		else:
			## Mild soak vs non-matched strikes.
			raw = int(floor(float(raw) * 0.85))
			notes.append("Shield Wall mild soak")

	## Skirmish: reduce hit chance / dmg from March & Charge; little vs Volley.
	if _has_buff(defender_buffs, "skirmish"):
		var sk := _buff_bonus(defender_buffs, "skirmish")
		if atk_off_id == "march" or atk_off_id == "charge":
			## Hit-chance style: 30% miss (0 dmg) else cut damage.
			var miss_chance := 0.22 + 0.08 * float(sk)
			if randf() < miss_chance:
				notes.append("Skirmish slipped %s (miss)" % TROOP_BUFFS[atk_off_id]["label"])
				raw = 0
			else:
				var before4 := raw
				raw = int(floor(float(raw) * (0.55 - 0.05 * float(sk - 1))))
				notes.append("Skirmish cut %s (%d→%d)" % [
					TROOP_BUFFS[atk_off_id]["label"], before4, raw
				])
		elif atk_off_id == "volley":
			var before5 := raw
			raw = maxi(0, raw - 1)  ## almost no help
			if before5 != raw:
				notes.append("Skirmish weak vs Volley (%d→%d)" % [before5, raw])
		else:
			raw = int(floor(float(raw) * 0.90))

	## Flank: counter-posture — if foe March/Volley, chip back + cut their bonus.
	## Weak vs Shield Wall grind (attacker grinding behind Shield).
	if _has_buff(defender_buffs, "flank"):
		if atk_off_id == "march" or atk_off_id == "volley":
			var before6 := raw
			var grind := _has_buff(attacker_buffs, "shield")
			if grind:
				## Flank struggles to punish a Shield Wall grind.
				raw = int(floor(float(raw) * 0.92))
				flank_chip = maxi(1, int(floor(float(FLANK_CHIP) * 0.35)))
				notes.append("Flank weak vs Shield grind (%d→%d, chip %d)" % [before6, raw, flank_chip])
			else:
				raw = int(floor(float(raw) * 0.70))
				flank_chip = FLANK_CHIP * maxi(1, _buff_bonus(defender_buffs, "flank"))
				notes.append("Flank cut %s (%d→%d)" % [TROOP_BUFFS[atk_off_id]["label"], before6, raw])
				notes.append("Flank chip-back %d" % flank_chip)
		elif atk_off_id == "charge":
			## Flank does not specially counter Charge (that's Shield's job).
			notes.append("Flank no special vs Charge")

	## Defender Hold — flat tank bonus (going second viable).
	if defender_held:
		var before7 := raw
		raw -= 4
		notes.append("Hold braced (%d→%d)" % [before7, maxi(0, raw)])

	## Soft clamp
	if attacker_general == "strike":
		if raw > 0:
			raw = clampi(raw, MIN_HIT, MAX_HIT)
		else:
			raw = 0
	else:
		raw = clampi(raw, 0, MAX_HIT)

	return {"dmg": maxi(0, raw), "notes": notes, "flank_chip": flank_chip}

func _refresh_all() -> void:
	_player_hp_lbl.text = "You  %d / %d" % [_player_hp, PLAYER_MAX_HP]
	_enemy_hp_lbl.text = "Cernach  %d / %d" % [_enemy_hp, ENEMY_MAX_HP]
	_player_bar.value = _player_hp
	_enemy_bar.value = _enemy_hp
	_player_stats_lbl.text = _stats_line(_player_buffs, "You")
	_enemy_stats_lbl.text = _stats_line(_enemy_buffs, "Cernach")
	_player_buff_lbl.text = _buff_summary(_player_buffs, "You")
	_enemy_buff_lbl.text = _buff_summary(_enemy_buffs, "Cernach")
	_highlight_selection()

func _highlight_selection() -> void:
	for id in _troop_btns.keys():
		var b: Button = _troop_btns[id]
		if _busy or _ended:
			b.disabled = true
			b.modulate = Color(0.55, 0.55, 0.58, 0.85)
		elif id == _selected_buff:
			b.disabled = false
			b.modulate = Color(1.15, 1.05, 0.75, 1.0)
		else:
			b.disabled = false
			b.modulate = Color(1, 1, 1, 1)
	for gid in _general_btns.keys():
		var gb: Button = _general_btns[gid]
		if gid == "resolve":
			var can := (not _busy) and (not _ended) and _selected_buff != "" and _selected_general != ""
			gb.disabled = not can
			gb.modulate = Color(1.1, 1.05, 0.85, 1.0) if can else Color(0.55, 0.55, 0.58, 0.85)
			continue
		if _busy or _ended:
			gb.disabled = true
			gb.modulate = Color(0.55, 0.55, 0.58, 0.85)
		elif gid == _selected_general:
			gb.disabled = false
			gb.modulate = Color(1.15, 1.05, 0.75, 1.0)
		else:
			gb.disabled = false
			gb.modulate = Color(1, 1, 1, 1)

func _on_pick_buff(buff_id: String) -> void:
	if _busy or _ended:
		return
	_selected_buff = buff_id
	var info: Dictionary = TROOP_BUFFS[buff_id]
	_status.text = "Turn %d — %s: %s" % [_turn, info["label"], info["blurb"]]
	_highlight_selection()

func _on_pick_general(action: String) -> void:
	if _busy or _ended:
		return
	_selected_general = action
	_status.text = "Turn %d — General: %s. Resolve when ready." % [_turn, action.capitalize()]
	_highlight_selection()

func _enemy_choose(player_pick: String) -> Dictionary:
	## Mildly smart AI: sometimes counter player's offense, sometimes push triangle.
	var p_info: Dictionary = TROOP_BUFFS[player_pick]
	var p_group := String(p_info["group"])
	var p_kind := String(p_info["kind"])
	var pick: String = String(TROOP_ORDER[randi() % TROOP_ORDER.size()])
	var roll := randf()
	if p_kind == "atk" and roll < 0.45:
		## Matching defence vs that offence group.
		if p_group == "cav":
			pick = "shield"  ## Shield hard-counters Charge
		elif p_group == "inf":
			pick = "skirmish"  ## Skirmish vs March
		elif p_group == "arch":
			pick = "flank"  ## Flank vs Volley
	elif roll < 0.70:
		var want := ""
		if p_group == "inf":
			want = "arch"
		elif p_group == "arch":
			want = "cav"
		elif p_group == "cav":
			want = "inf"
		for id in TROOP_ORDER:
			var inf: Dictionary = TROOP_BUFFS[id]
			if String(inf["kind"]) == "atk" and String(inf["group"]) == want:
				pick = id
				break
	var gen := "strike"
	var groll := randf()
	if _enemy_hp < 40 and groll < 0.35:
		gen = "rally"
	elif groll < 0.20:
		gen = "hold"
	return {"buff": pick, "general": gen}

func _join_notes(notes: PackedStringArray, limit: int = 3) -> String:
	if notes.is_empty():
		return ""
	var use: PackedStringArray = []
	for i in range(mini(limit, notes.size())):
		use.append(notes[i])
	return "; ".join(use)

func _on_resolve() -> void:
	if _busy or _ended:
		return
	if _selected_buff == "":
		_show_toast("Pick a troop move first", 1.8)
		return
	if _selected_general == "":
		return
	_busy = true
	_highlight_selection()

	var p_pick := _selected_buff
	var p_gen := _selected_general
	_selected_buff = ""
	_player_pick_id = p_pick

	var enemy_choice := _enemy_choose(p_pick)
	var e_pick: String = String(enemy_choice["buff"])
	var e_gen: String = String(enemy_choice["general"])
	_enemy_pick_id = e_pick

	## Apply both buffs first (shared initiative / simultaneous).
	_apply_buff(_player_buffs, p_pick)
	_apply_buff(_enemy_buffs, e_pick)
	var p_info: Dictionary = TROOP_BUFFS[p_pick]
	var e_info: Dictionary = TROOP_BUFFS[e_pick]
	_pulse_group(_troop_figs, String(p_info["group"]))
	_pulse_group(_enemy_figs, String(e_info["group"]))

	var p_off := _active_offense_group(_player_buffs, p_pick)
	var e_off := _active_offense_group(_enemy_buffs, e_pick)
	_player_last_offense = p_off
	_enemy_last_offense = e_off

	## Heals before damage (Rally).
	if p_gen == "rally":
		_player_hp = mini(PLAYER_MAX_HP, _player_hp + RALLY_HEAL)
	if e_gen == "rally":
		_enemy_hp = mini(ENEMY_MAX_HP, _enemy_hp + RALLY_HEAL)

	var p_held := p_gen == "hold"
	var e_held := e_gen == "hold"

	var you_hit := _resolve_attack(_player_buffs, _enemy_buffs, p_pick, e_pick, e_off, e_held, p_gen)
	var foe_hit := _resolve_attack(_enemy_buffs, _player_buffs, e_pick, p_pick, p_off, p_held, e_gen)

	var dmg_to_enemy: int = int(you_hit["dmg"])
	var dmg_to_player: int = int(foe_hit["dmg"])
	## Flank chip is dealt by the defender to the attacker (simultaneous).
	var chip_from_enemy_flank: int = int(you_hit["flank_chip"])
	var chip_from_your_flank: int = int(foe_hit["flank_chip"])

	dmg_to_player += chip_from_enemy_flank
	dmg_to_enemy += chip_from_your_flank

	## Simultaneous HP apply.
	_enemy_hp = maxi(0, _enemy_hp - dmg_to_enemy)
	_player_hp = maxi(0, _player_hp - dmg_to_player)
	_refresh_all()

	var you_notes: PackedStringArray = you_hit["notes"]
	var foe_notes: PackedStringArray = foe_hit["notes"]
	var flavor := _join_notes(you_notes, 2)
	var flavor2 := _join_notes(foe_notes, 2)
	if chip_from_your_flank > 0:
		flavor += (" · " if flavor != "" else "") + "Your Flank +%d" % chip_from_your_flank
	if chip_from_enemy_flank > 0:
		flavor2 += (" · " if flavor2 != "" else "") + "Cernach Flank +%d" % chip_from_enemy_flank

	_status.text = "You %s/%s → %d dmg · Cernach %s/%s → %d dmg" % [
		p_info["label"], p_gen.capitalize(), dmg_to_enemy,
		e_info["label"], e_gen.capitalize(), dmg_to_player,
	]
	var toast_msg := "You deal %d" % dmg_to_enemy
	if flavor != "":
		toast_msg += " (%s)" % flavor
	toast_msg += " · take %d" % dmg_to_player
	if flavor2 != "":
		toast_msg += " (%s)" % flavor2
	_show_toast(toast_msg, 3.4)

	await get_tree().create_timer(0.85).timeout
	if _ended:
		return

	if _enemy_hp <= 0 and _player_hp <= 0:
		_win()
		return
	if _enemy_hp <= 0:
		_win()
		return
	if _player_hp <= 0:
		_lose()
		return

	_tick_buffs(_player_buffs)
	_tick_buffs(_enemy_buffs)
	_turn += 1
	_busy = false
	_selected_general = "strike"
	_refresh_all()
	_status.text = "Turn %d — pick troop + General, then Resolve." % _turn

func _win() -> void:
	_ended = true
	_busy = true
	_highlight_selection()
	_status.text = "Victory — Cernach yields the corner."
	_show_toast("You win! Returning to the yard…", 2.4)
	await get_tree().create_timer(1.8).timeout
	_return_to_yard()

func _lose() -> void:
	_ended = true
	_busy = true
	_highlight_selection()
	_status.text = "Defeat — the corner holds."
	_show_toast("You fall! Returning to the yard…", 2.4)
	await get_tree().create_timer(1.8).timeout
	_return_to_yard()

func _return_to_yard() -> void:
	if GameState and GameState.has_method("go_to"):
		GameState.go_to(YARD_SCENE, "from_cernach", "cernachs_corner")
	else:
		get_tree().change_scene_to_file(YARD_SCENE)

extends Node3D
## Travel Road greybox — bridge / path / crossroads. Doors: Yard, North, Coast, Hostel.
## Patch 3: realtime combat — ground thugs + stairs to 2nd floor elite.

const FoeScript = preload("res://scripts/crossroads_foe.gd")

@onready var _player: CharacterBody3D = $Player
@onready var _toast: Label = $UI/Toast
@onready var _hint: Label = $UI/HintLabel
@onready var _objective: Label = $UI/ObjectiveLabel
@onready var _action_btn: Button = $UI/ActionButton
@onready var _jump_btn: Button = $UI/JumpButton

var _near: String = ""
var _leaving: bool = false
var _toast_t: float = 0.0
var _hp_label: Label
var _light_btn: Button
var _heavy_btn: Button
var _block_btn: Button
var _pending_swing_btn: Button
var _button_flicks: Dictionary = {}
var _foes_alive: int = 0

const SPAWNS := {
	"default": Vector3(0.0, 0.4, 0.0),
	"from_yard": Vector3(0.0, 0.4, 12.0),
	"from_north": Vector3(-12.0, 0.4, 0.0),
	"from_coast": Vector3(0.0, 0.4, -14.0),
	"from_hostel": Vector3(12.0, 0.4, 0.0),
}

func _ready() -> void:
	Music.play_area("road")
	_build_world()
	_wire_hud()
	_ensure_combat_hud()
	_ensure_back_yard_btn()
	if _hint:
		_hint.text = "WASD · Jump · Light/Heavy · Block (hold=shield / tap=parry on foe wind-up) · Action at doors"
	if _objective:
		_objective.text = "Crossroads — clear thugs · stairs → elite · Yard/Glade/Coast/Hostel"
	_place_player()
	_spawn_foes()
	LomnasBanner.attach(self, "Lomnas: Crossroads thugs block the way. Staff ready — block, parry, climb for the elite.")
	_show_toast("Crossroads — doors: Yard · Glade · Coast · Hostel", 2.4)
	if _player and _player.has_signal("hp_changed"):
		_player.hp_changed.connect(_on_player_hp)
		_on_player_hp(_player.hp, _player.max_hp)
	if _player and _player.has_signal("blocked"):
		_player.blocked.connect(_on_player_blocked)
	if _player and _player.has_signal("swing_result"):
		_player.swing_result.connect(_on_swing_result)
	if _player and _player.has_signal("parry_cooldown_changed"):
		_player.parry_cooldown_changed.connect(_on_parry_cooldown)
	if _player and _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	if _player and _player.has_signal("stick_hit"):
		_player.stick_hit.connect(func (_h: bool) -> void:
			_show_toast("Thwack!", 0.7))
	if _player and _player.has_signal("stick_miss"):
		_player.stick_miss.connect(func () -> void:
			_show_toast("Miss", 0.55))

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and _toast:
			_toast.visible = false

func _wire_hud() -> void:
	if _action_btn:
		_action_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_action_btn.z_index = 40
		if not _action_btn.pressed.is_connected(_on_action):
			_action_btn.pressed.connect(_on_action)
		_action_btn.visible = false
	if _jump_btn:
		_jump_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_jump_btn.z_index = 40
		_jump_btn.pressed.connect(func () -> void:
			if _player and _player.has_method("try_jump"):
				_player.try_jump())

func _ensure_combat_hud() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	# HP label
	_hp_label = ui.get_node_or_null("CombatHp") as Label
	if _hp_label == null:
		_hp_label = Label.new()
		_hp_label.name = "CombatHp"
		_hp_label.z_index = 42
		_hp_label.anchor_left = 0.0
		_hp_label.anchor_right = 0.0
		_hp_label.anchor_top = 0.0
		_hp_label.anchor_bottom = 0.0
		_hp_label.offset_left = 16.0
		_hp_label.offset_top = 12.0
		_hp_label.offset_right = 220.0
		_hp_label.offset_bottom = 44.0
		_hp_label.add_theme_font_size_override("font_size", 18)
		_hp_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.8))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.12, 0.1, 0.75)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_right = 8
		sb.corner_radius_bottom_left = 8
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		_hp_label.add_theme_stylebox_override("normal", sb)
		ui.add_child(_hp_label)

	# Yard-matching combat cluster:
	#   [Heavy] [Block]
	#   [Light] [Jump]
	# Jump already exists in travel_road.tscn; Light/Heavy/Block created if missing.
	var light := ui.get_node_or_null("LightButton") as Button
	if light == null:
		light = Button.new()
		light.name = "LightButton"
		light.text = "Light"
		light.z_index = 40
		light.focus_mode = Control.FOCUS_NONE
		light.mouse_filter = Control.MOUSE_FILTER_STOP
		light.anchor_left = 1.0
		light.anchor_right = 1.0
		light.anchor_top = 1.0
		light.anchor_bottom = 1.0
		light.offset_left = -248.0
		light.offset_right = -140.0
		light.offset_top = -96.0
		light.offset_bottom = -28.0
		light.add_theme_font_size_override("font_size", 18)
		var lsb := StyleBoxFlat.new()
		lsb.bg_color = Color(0.55, 0.28, 0.22, 0.95)
		lsb.corner_radius_top_left = 14
		lsb.corner_radius_top_right = 14
		lsb.corner_radius_bottom_right = 14
		lsb.corner_radius_bottom_left = 14
		light.add_theme_stylebox_override("normal", lsb)
		ui.add_child(light)
	if not light.pressed.is_connected(_on_light):
		light.pressed.connect(_on_light)
	_light_btn = light

	var heavy := ui.get_node_or_null("HeavyButton") as Button
	if heavy == null:
		heavy = Button.new()
		heavy.name = "HeavyButton"
		heavy.text = "Heavy"
		heavy.z_index = 40
		heavy.focus_mode = Control.FOCUS_NONE
		heavy.mouse_filter = Control.MOUSE_FILTER_STOP
		heavy.anchor_left = 1.0
		heavy.anchor_right = 1.0
		heavy.anchor_top = 1.0
		heavy.anchor_bottom = 1.0
		heavy.offset_left = -248.0
		heavy.offset_right = -140.0
		heavy.offset_top = -168.0
		heavy.offset_bottom = -104.0
		heavy.add_theme_font_size_override("font_size", 18)
		var hsb := StyleBoxFlat.new()
		hsb.bg_color = Color(0.48, 0.22, 0.18, 0.95)
		hsb.corner_radius_top_left = 14
		hsb.corner_radius_top_right = 14
		hsb.corner_radius_bottom_right = 14
		hsb.corner_radius_bottom_left = 14
		heavy.add_theme_stylebox_override("normal", hsb)
		ui.add_child(heavy)
	if not heavy.pressed.is_connected(_on_heavy):
		heavy.pressed.connect(_on_heavy)
	_heavy_btn = heavy

	# Hide legacy single Attack if present (replaced by Light/Heavy)
	var legacy_atk := ui.get_node_or_null("AttackButton") as Button
	if legacy_atk:
		legacy_atk.visible = false

	# Block — above Jump (right column); tap=parry / hold=shield
	var blk := ui.get_node_or_null("BlockButton") as Button
	if blk == null:
		blk = Button.new()
		blk.name = "BlockButton"
		blk.text = "Block"
		blk.z_index = 40
		blk.focus_mode = Control.FOCUS_NONE
		blk.mouse_filter = Control.MOUSE_FILTER_STOP
		blk.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		blk.anchor_left = 1.0
		blk.anchor_right = 1.0
		blk.anchor_top = 1.0
		blk.anchor_bottom = 1.0
		blk.add_theme_font_size_override("font_size", 20)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.22, 0.38, 0.55, 0.95)
		bsb.corner_radius_top_left = 14
		bsb.corner_radius_top_right = 14
		bsb.corner_radius_bottom_right = 14
		bsb.corner_radius_bottom_left = 14
		blk.add_theme_stylebox_override("normal", bsb)
		ui.add_child(blk)
	blk.offset_left = -132.0
	blk.offset_right = -24.0
	blk.offset_top = -168.0
	blk.offset_bottom = -104.0
	_block_btn = blk
	if not blk.button_down.is_connected(_on_block_down):
		blk.button_down.connect(_on_block_down)
	if not blk.button_up.is_connected(_on_block_up):
		blk.button_up.connect(_on_block_up)

func _on_light() -> void:
	if _player and _player.has_method("do_light_swing"):
		if not _player.has_method("can_start_swing") or _player.can_start_swing():
			_pending_swing_btn = _light_btn
			_player.do_light_swing()

func _on_heavy() -> void:
	if _player and _player.has_method("do_heavy_swing"):
		if not _player.has_method("can_start_swing") or _player.can_start_swing():
			_pending_swing_btn = _heavy_btn
			_player.do_heavy_swing()

func _on_swing_result(hit: bool, heavy: bool) -> void:
	var btn := _pending_swing_btn
	_pending_swing_btn = null
	if btn == null or not is_instance_valid(btn):
		return
	var hit_color := Color(0.35, 1.0, 0.55)
	var miss_color := Color(0.72, 0.46, 0.46)
	_flick_btn(btn, "Hit" if hit else "Miss", hit_color if hit else miss_color, 0.5)

func _flick_btn(btn: Button, temp_text: String, temp_color: Color, secs: float) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var state: Dictionary = _button_flicks.get(btn, {})
	if state.is_empty():
		state = {"text": btn.text, "color": btn.get_theme_color("font_color"), "token": 0}
	_button_flicks[btn] = state
	var token := int(state.get("token", 0)) + 1
	state["token"] = token
	btn.text = temp_text
	btn.add_theme_color_override("font_color", temp_color)
	await get_tree().create_timer(secs).timeout
	if not is_instance_valid(btn):
		return
	var current: Dictionary = _button_flicks.get(btn, {})
	if int(current.get("token", -1)) != token:
		return
	btn.text = String(current.get("text", btn.text))
	btn.add_theme_color_override("font_color", current.get("color", Color.WHITE))
	_button_flicks.erase(btn)

func _on_block_down() -> void:
	if _player and _player.has_method("set_block_held"):
		_player.set_block_held(true)

func _on_block_up() -> void:
	if _player and _player.has_method("set_block_held"):
		_player.set_block_held(false)

func _on_player_hp(h: int, mx: int) -> void:
	if _hp_label:
		_hp_label.text = "HP  %d / %d" % [h, mx]

func _on_player_blocked(parry: bool) -> void:
	if parry:
		_show_toast("Parry!", 0.9)
		_flick_btn(_block_btn, "Parry", Color(0.2, 0.95, 1.0), 0.5)
	else:
		_show_toast("Blocked!", 0.7)

func _on_parry_cooldown(active: bool) -> void:
	if _block_btn == null or not is_instance_valid(_block_btn):
		return
	# Keep the button usable for hold-shield, but make the parry lockout visible.
	_block_btn.modulate = Color(0.62, 0.68, 0.74) if active else Color.WHITE

func _on_player_died() -> void:
	_show_toast("Downed — returning to Yard…", 2.0)
	await get_tree().create_timer(1.4).timeout
	_go("res://scenes/druid_yard.tscn", "from_road")

func _ensure_back_yard_btn() -> void:
	## Soft-lock escape: always-visible return to Yard (does not require door stand).
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var btn := ui.get_node_or_null("BackYardBtn") as Button
	if btn == null:
		btn = Button.new()
		btn.name = "BackYardBtn"
		btn.text = "Back to Yard"
		btn.z_index = 45
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.anchor_left = 1.0
		btn.anchor_right = 1.0
		btn.anchor_top = 0.0
		btn.anchor_bottom = 0.0
		btn.offset_left = -168.0
		btn.offset_right = -16.0
		btn.offset_top = 12.0
		btn.offset_bottom = 52.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.25, 0.42, 0.28, 0.95)
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_right = 10
		sb.corner_radius_bottom_left = 10
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", sb)
		ui.add_child(btn)
	if not btn.pressed.is_connected(_back_to_yard):
		btn.pressed.connect(_back_to_yard)

func _back_to_yard() -> void:
	_go("res://scenes/druid_yard.tscn", "from_road")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E):
		if _near != "":
			_on_action()
			get_viewport().set_input_as_handled()

func _place_player() -> void:
	if _player == null:
		return
	var key := GameState.take_spawn_point("from_yard")
	if not SPAWNS.has(key):
		key = "default"
	_player.global_position = SPAWNS[key]
	if _player.has_method("configure_interior"):
		_player.configure_interior(false)

func _show_toast(msg: String, dur: float = 2.0) -> void:
	if _toast:
		_toast.text = msg
		_toast.visible = true
	_toast_t = dur

func _set_near(kind: String, label: String) -> void:
	_near = kind
	if _action_btn:
		_action_btn.text = label
		_action_btn.visible = true

func _clear_near(kind: String) -> void:
	if _near == kind:
		_near = ""
		if _action_btn:
			_action_btn.visible = false

func _on_action() -> void:
	match _near:
		"to_yard":
			_go("res://scenes/druid_yard.tscn", "from_road")
		"to_north":
			_go("res://scenes/north_holy.tscn", "from_road")
		"to_coast":
			_go("res://scenes/coast.tscn", "from_road")
		"to_hostel":
			_go("res://scenes/hostel.tscn", "from_road")

func _go(path: String, spawn: String) -> void:
	if _leaving:
		return
	_leaving = true
	GameState.go_to(path, spawn, "travel_road")

func _spawn_foes() -> void:
	var parent: Node3D = $World
	# Ground thugs (1–3) around crossroads
	var spots := [
		Vector3(4.5, 0.4, -3.0),
		Vector3(-5.0, 0.4, 2.5),
		Vector3(3.0, 0.4, 5.5),
	]
	var n := 2 + (randi() % 2)  # 2 or 3
	for i in range(n):
		var foe := _make_foe(false, 3 + (i % 2))  # 3–4 HP
		# add_child BEFORE global_position (avoids !is_inside_tree)
		parent.add_child(foe)
		foe.global_position = spots[i % spots.size()]
		_foes_alive += 1
		foe.died.connect(_on_foe_died)
	# Elite on 2nd floor platform
	var elite := _make_foe(true, 6)
	parent.add_child(elite)
	elite.global_position = Vector3(-8.0, 4.6, -8.0)
	_foes_alive += 1
	elite.died.connect(_on_foe_died)

func _make_foe(is_elite: bool, hp: int) -> CharacterBody3D:
	var foe := CharacterBody3D.new()
	foe.set_script(FoeScript)
	foe.set("elite", is_elite)
	foe.set("max_hp", hp)
	if is_elite:
		foe.set("move_speed", 3.2)
		foe.set("contact_damage", 2)
	return foe

func _on_foe_died() -> void:
	_foes_alive = maxi(0, _foes_alive - 1)
	if _foes_alive <= 0:
		_show_toast("Crossroads clear — roads open.", 2.2)

func _build_world() -> void:
	var world: Node3D = $World
	for c in world.get_children():
		c.queue_free()

	var dirt := WalkAreaKit.mat(Color(0.42, 0.36, 0.24))
	WalkAreaKit.box(world, Vector3(44, 0.4, 44), Vector3(0, -0.2, 0), dirt, "Ground")
	WalkAreaKit.cyl(world, 3.5, 0.5, Vector3(-7.0, 0.05, -7.0), WalkAreaKit.mat(Color(0.40, 0.38, 0.28)), "SoftMound", 14, false)
	WalkAreaKit.cyl(world, 3.0, 0.42, Vector3(8.0, 0.02, 4.0), WalkAreaKit.mat(Color(0.38, 0.40, 0.30)), "SoftMound2", 14, false)
	# Crossroads paths
	WalkAreaKit.box(world, Vector3(4.0, 0.12, 36), Vector3(0, 0.06, 0), WalkAreaKit.mat(Color(0.62, 0.50, 0.34)), "PathNS")
	WalkAreaKit.box(world, Vector3(36, 0.12, 4.0), Vector3(0, 0.06, 0), WalkAreaKit.mat(Color(0.62, 0.50, 0.34)), "PathEW")
	# Bridge over ditch
	WalkAreaKit.box(world, Vector3(10, 0.8, 3.2), Vector3(0, -0.5, 6), WalkAreaKit.mat(Color(0.3, 0.4, 0.5)), "Ditch", false)
	WalkAreaKit.box(world, Vector3(4.5, 0.35, 5.0), Vector3(0, 0.35, 6), WalkAreaKit.mat(Color(0.5, 0.4, 0.3)), "BridgeDeck")
	WalkAreaKit.box(world, Vector3(0.3, 1.0, 5.0), Vector3(-2.0, 0.9, 6), WalkAreaKit.mat(Color(0.4, 0.32, 0.24)), "RailL")
	WalkAreaKit.box(world, Vector3(0.3, 1.0, 5.0), Vector3(2.0, 0.9, 6), WalkAreaKit.mat(Color(0.4, 0.32, 0.24)), "RailR")
	# Crossroads markers
	for i in range(4):
		var ang := float(i) * PI * 0.5
		var p := Vector3(sin(ang) * 3.5, 1.0, cos(ang) * 3.5)
		WalkAreaKit.cyl(world, 0.25, 2.0, p, WalkAreaKit.mat(Color(0.55, 0.52, 0.48)), "Marker%d" % i)
	WalkAreaKit.box(world, Vector3(2.5, 1.2, 2.5), Vector3(5, 0.6, 5), WalkAreaKit.mat(Color(0.5, 0.4, 0.3)), "JumpCrate")

	_build_stairs_and_upper(world)

	var stone := WalkAreaKit.mat(Color(0.5, 0.48, 0.44))
	WalkAreaKit.door_frame(world, Vector3(0, 0, 18), "To Yard", stone)
	# body_entered/exited pass Node — lambdas bind door kind (fixes Object→String)
	WalkAreaKit.door_area(world, "DoorYard", Vector3(0, 1.0, 17.5), 2.4,
		func(b: Node) -> void: _enter("to_yard", "Enter Yard", b),
		func(b: Node) -> void: _exit("to_yard", b))
	WalkAreaKit.door_frame(world, Vector3(0, 0, -18), "To Coast", stone)
	WalkAreaKit.door_area(world, "DoorCoast", Vector3(0, 1.0, -18), 2.4,
		func(b: Node) -> void: _enter("to_coast", "Enter Coast", b),
		func(b: Node) -> void: _exit("to_coast", b))
	WalkAreaKit.door_frame(world, Vector3(-18, 0, 0), "Druid Glade", stone, PI * 0.5)
	WalkAreaKit.door_area(world, "DoorNorth", Vector3(-18, 1.0, 0), 2.4,
		func(b: Node) -> void: _enter("to_north", "Enter Glade", b),
		func(b: Node) -> void: _exit("to_north", b))
	WalkAreaKit.door_frame(world, Vector3(18, 0, 0), "To Hostel", stone, -PI * 0.5)
	WalkAreaKit.door_area(world, "DoorHostel", Vector3(18, 1.0, 0), 2.4,
		func(b: Node) -> void: _enter("to_hostel", "Enter Hostel", b),
		func(b: Node) -> void: _exit("to_hostel", b))

	WalkAreaKit.sun_env(world, Color(0.55, 0.58, 0.5), Color(0.6, 0.55, 0.45), 1.1)
	WalkAreaKit.label3d(world, "CROSSROADS", Vector3(0, 5.0, 0), Color(0.95, 0.88, 0.7), 52)

func _build_stairs_and_upper(world: Node3D) -> void:
	## Stairs NW → 2nd-floor platform with elite.
	var plank := WalkAreaKit.mat(Color(0.48, 0.38, 0.28))
	var stone := WalkAreaKit.mat(Color(0.42, 0.40, 0.38))
	# Stair steps from (~-3,0,-6) climbing toward (-8,4,-8)
	var steps := 8
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		var pos := Vector3(lerpf(-3.0, -7.2, t), 0.25 + float(i) * 0.5, lerpf(-5.5, -7.5, t))
		WalkAreaKit.box(world, Vector3(2.2, 0.28, 1.1), pos, plank, "Step%d" % i)
	# Upper deck
	WalkAreaKit.box(world, Vector3(8.0, 0.4, 8.0), Vector3(-8.0, 4.0, -8.0), stone, "UpperDeck")
	# Low rails
	WalkAreaKit.box(world, Vector3(8.2, 0.7, 0.25), Vector3(-8.0, 4.55, -12.0), plank, "RailN")
	WalkAreaKit.box(world, Vector3(8.2, 0.7, 0.25), Vector3(-8.0, 4.55, -4.0), plank, "RailS")
	WalkAreaKit.box(world, Vector3(0.25, 0.7, 8.2), Vector3(-12.0, 4.55, -8.0), plank, "RailW")
	WalkAreaKit.box(world, Vector3(0.25, 0.7, 5.0), Vector3(-4.0, 4.55, -9.5), plank, "RailE")
	# Support pillars
	WalkAreaKit.cyl(world, 0.35, 4.0, Vector3(-10.5, 2.0, -10.5), stone, "PillarA")
	WalkAreaKit.cyl(world, 0.35, 4.0, Vector3(-5.5, 2.0, -10.5), stone, "PillarB")
	WalkAreaKit.cyl(world, 0.35, 4.0, Vector3(-10.5, 2.0, -5.5), stone, "PillarC")
	WalkAreaKit.label3d(world, "2ND FLOOR", Vector3(-8.0, 5.6, -8.0), Color(1.0, 0.55, 0.4), 40)
	WalkAreaKit.label3d(world, "STAIRS", Vector3(-3.5, 1.8, -5.2), Color(0.9, 0.85, 0.7), 32)

func _enter(kind: String, label: String, body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_set_near(kind, label)

func _exit(kind: String, body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_clear_near(kind)

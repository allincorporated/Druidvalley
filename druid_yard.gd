extends Node3D
## Main 3D yard — Pictish hub rebuild: wide clear path, low stone walls, roundhouses,
## World Tree + purple portal, sunny daylight. Symbol stones / northern roundhouses / knot marks.
## Chess + Cernach via Action on buildings. Far doors: Ahead Crossroads · Left Glade · Right Hostel.

@onready var _toast: Label = $UI/Toast
@onready var _hint: Label = $UI/HintLabel
@onready var _objective: Label = $UI/ObjectiveLabel
@onready var _action_btn: Button = $UI/ActionButton
@onready var _progress: Label = $UI/ProgressLabel
@onready var _jump_btn: Button = $UI/JumpButton
@onready var _light_btn: Button = $UI/LightButton
@onready var _heavy_btn: Button = $UI/HeavyButton
@onready var _player: CharacterBody3D = $Player

const C_STONE := Color(0.48, 0.50, 0.52)
const C_THATCH := Color(0.42, 0.32, 0.18)
const C_WALL := Color(0.55, 0.50, 0.42)
const C_GRASS := Color(0.34, 0.55, 0.28)
const C_DIRT := Color(0.28, 0.20, 0.12)
const C_TRUNK := Color(0.28, 0.18, 0.10)
const C_FOLIAGE := Color(0.22, 0.38, 0.20)
const C_WOOD := Color(0.40, 0.28, 0.16)
const C_ROBE := Color(0.22, 0.28, 0.42)
const C_BRICK_FALLBACK := Color(0.55, 0.42, 0.32)

## Landmark world positions (rebuild)
## Spawn: (0, 0.35, 14)
## Path spine: x≈0, z 14 → −16 (clear run/jump/swing lane)
## World Tree + portal: (0, 0, −14)
## Crossroads ahead behind tree: (0, 0, −28)
## Druid Glade LEFT: (−16, 0, −20)
## Hostel RIGHT: (16, 0, −20)
## War-board house (Action): (11.5, 0, −6)
## Cernach house (Action): (12.0, 0, −14)
## Coast: via Crossroads chain (no freestanding yard door spam)

var _phase: String = "walk"
var _druid_talked: bool = false
var _warboard_done: bool = false
var _climb_taps: int = 0
var _scene_leaving: bool = false
var _toast_timer: float = 0.0
var _dialogue: Control = null
var _dialogue_body: Label = null
var _pending_swing_btn: Button
var _button_flicks: Dictionary = {}

var _general_panel = null  # GeneralPanel (CanvasLayer)

## "" | "chess" | "cernach" | "steps" | "climb_tree" | "dummy" | "druid" | "portal" | "exit" | "door_north" | "door_hostel" | "door_coast"
var _near: String = ""

func _ready() -> void:
	Music.play_area("yard")
	_build_world()
	if _hint:
		_hint.text = "WASD / stick · Jump · Light/Heavy swing · Action when near"
	if _toast:
		_toast.visible = false
	_hide_action()
	if _progress:
		_progress.visible = false
	_wire_hud()
	_build_dialogue_ui()
	if GameState.warboard_visited:
		_warboard_done = true
	if GameState.druid_talked:
		_druid_talked = true
	_refresh_objective()
	if _player:
		var sp := "from_tree" if GameState.spawn_at_tree else GameState.take_spawn_point("default")
		GameState.spawn_at_tree = false
		match sp:
			"from_tree":
				_player.global_position = Vector3(0.0, 0.35, -11.2)
				_show_toast("Back beneath the World Tree.", 2.5)
			"from_road":
				_player.global_position = Vector3(0.0, 0.35, -20.0)
				_show_toast("Returned from the Crossroads.", 2.2)
			"from_north":
				_player.global_position = Vector3(-12.5, 0.35, -17.0)
				_show_toast("Returned from the Druid Glade.", 2.2)
			"from_coast":
				# Coast is via Crossroads — land near Crossroads gate
				_player.global_position = Vector3(0.0, 0.35, -20.0)
				_show_toast("Returned toward the yard from the coast road.", 2.2)
			"from_hostel":
				_player.global_position = Vector3(12.0, 0.35, -17.0)
				_show_toast("Returned from the Hostel.", 2.2)
			"from_chess":
				_player.global_position = Vector3(8.5, 0.35, -5.0)
				_show_toast("Returned from the war-board.", 2.2)
			"from_cernach":
				_player.global_position = Vector3(10.0, 0.35, -12.5)
				_show_toast("Returned from Cernach's Corner.", 2.2)
			_:
				_player.global_position = Vector3(0.0, 0.35, 14.0)
		if _player.has_method("configure_interior"):
			_player.configure_interior(false)
		if _player.has_signal("stick_hit"):
			_player.stick_hit.connect(_on_stick_hit)
		if _player.has_signal("swing_result"):
			_player.swing_result.connect(_on_swing_result)
	LomnasBanner.attach(self, "Lomnas: The yard holds the World Tree, war-board, Glade, Crossroads, and Hostel. Walk the labelled doors.")
	if get_node_or_null("UI"):
		_general_panel = GeneralPanel.attach(self, $UI as CanvasLayer, _player)
		if _general_panel and _general_panel.has_signal("toast_requested"):
			if not _general_panel.toast_requested.is_connected(_on_general_toast):
				_general_panel.toast_requested.connect(_on_general_toast)

func _wire_hud() -> void:
	if _action_btn:
		_action_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_action_btn.z_index = 40
		_action_btn.pressed.connect(_on_action_pressed)
	if _jump_btn:
		_jump_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_jump_btn.z_index = 40
		_jump_btn.pressed.connect(_on_jump_pressed)
	if _light_btn:
		_light_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_light_btn.z_index = 40
		_light_btn.pressed.connect(_on_light_pressed)
	if _heavy_btn:
		_heavy_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_heavy_btn.z_index = 40
		_heavy_btn.pressed.connect(_on_heavy_pressed)

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and _toast:
			_toast.visible = false

func _mat(color: Color, rough: float = 0.9, emis: Color = Color(0, 0, 0, 1), emis_e: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	return m

func _tex_mat(path: String, color: Color = Color(1, 1, 1), uv_scale: float = 4.0, rough: float = 0.9, triplanar: bool = false, sharp: float = 6.0) -> StandardMaterial3D:
	## Yard albedo helper. Optional triplanar helps cylinders/cones (thatch, grass mounds, walls).
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	var tex := load(path) as Texture2D
	if tex:
		m.albedo_texture = tex
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if triplanar:
			m.uv1_triplanar = true
			m.uv1_triplanar_sharpness = sharp
	return m

func _grass_mat() -> StandardMaterial3D:
	## Prefer look_pass grass (large world UV for floors); else painterly meadow.
	var lp := LookPassMats.grass()
	if lp:
		return lp
	var m := _tex_mat("res://assets/textures/grass_pictish.jpg", Color(0.96, 0.98, 0.90), 9.0, 0.92, true, 4.0)
	if m.albedo_texture == null:
		m = _tex_mat("res://assets/textures/grass_dirt.jpg", Color(0.70, 0.82, 0.52), 8.0, 0.92, true, 4.0)
	if m.albedo_texture == null:
		m.albedo_color = C_GRASS
	return m

func _grass_bank_mat() -> StandardMaterial3D:
	## Bank / berm sides — slightly denser UV so vertical faces still read.
	var lp := LookPassMats.grass_bank()
	if lp:
		return lp
	var g := _grass_mat().duplicate() as StandardMaterial3D
	g.uv1_scale = Vector3(6.0, 6.0, 6.0)
	return g

func _portal_look_mat(energy: float = 9.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := load("res://assets/textures/portal_almond.jpg") as Texture2D
	if tex == null:
		tex = load("res://assets/textures/portal_emissive.jpg") as Texture2D
	m.albedo_color = Color(1.25, 0.75, 1.40)
	if tex:
		m.albedo_texture = tex
		m.emission_texture = tex
	m.roughness = 0.22
	m.emission_enabled = true
	m.emission = Color(1.0, 0.35, 1.1)
	m.emission_energy_multiplier = energy
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _wall_mat() -> StandardMaterial3D:
	## Prefer look_pass wall tile; else painterly dry-stone + triplanar for CSG.
	var lp := LookPassMats.wall()
	if lp:
		return lp
	var m := _tex_mat("res://assets/textures/stone_wall_pictish.jpg", Color(0.93, 0.91, 0.87), 1.85, 0.90, true, 6.0)
	if m.albedo_texture == null:
		m = _tex_mat("res://assets/textures/stone_wall.jpg", Color(0.90, 0.89, 0.86), 1.7, 0.90, true, 6.0)
	if m.albedo_texture == null:
		m.albedo_color = C_STONE
	return m

func _thatch_mat() -> StandardMaterial3D:
	## Prefer look_pass thatch tile; else fibrous painterly thatch (triplanar cones).
	var lp := LookPassMats.thatch()
	if lp:
		return lp
	var m := _tex_mat("res://assets/textures/thatch.jpg", Color(0.98, 0.84, 0.58), 1.15, 0.96, true, 7.0)
	if m.albedo_texture == null:
		m.albedo_color = C_THATCH
	return m

func _purple_root_mat(tint: Color = Color(0.72, 0.48, 0.90)) -> StandardMaterial3D:
	var m := _tex_mat("res://assets/textures/root_purple.jpg", tint, 2.0, 0.72)
	m.emission_enabled = true
	m.emission = Color(0.55, 0.22, 0.95)
	m.emission_energy_multiplier = 0.55
	return m

func _magic_roots_mat() -> StandardMaterial3D:
	var m := _tex_mat("res://assets/textures/magic_roots.jpg", Color(0.98, 0.82, 1.08), 1.0, 0.65)
	m.emission_enabled = true
	var etex := load("res://assets/textures/magic_roots.jpg") as Texture2D
	if etex:
		m.emission_texture = etex
	m.emission = Color(0.72, 0.28, 1.0)
	m.emission_energy_multiplier = 1.6
	return m

func _brick_mat() -> StandardMaterial3D:
	## Prefer look_pass path stone; else etched X / pictish / cobble. ~4 tiles / ~5m.
	var lp := LookPassMats.path_stone()
	if lp:
		return lp
	var m := StandardMaterial3D.new()
	var tex := load("res://assets/textures/path_x_tile.jpg") as Texture2D
	if tex == null:
		tex = load("res://assets/textures/path_pictish_tile.jpg") as Texture2D
	if tex == null:
		tex = load("res://assets/textures/cobble_path.jpg") as Texture2D
	if tex:
		m.albedo_texture = tex
		m.albedo_color = Color(0.94, 0.93, 0.90)
		m.uv1_scale = Vector3(4.5, 4.5, 1.0)
	else:
		m.albedo_color = C_BRICK_FALLBACK
	m.roughness = 0.84
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

func _heather_mat() -> StandardMaterial3D:
	## Olive meadow with subtle dusty-purple flecks (not neon purple spheres).
	var m := _tex_mat("res://assets/textures/heather.jpg", Color(0.88, 0.95, 0.82), 1.1, 0.88, true, 4.0)
	if m.albedo_texture == null:
		m.albedo_color = Color(0.40, 0.48, 0.34)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _door_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := load("res://assets/textures/roundhouse_door.jpg") as Texture2D
	m.albedo_color = Color(0.85, 0.72, 0.55)
	if tex:
		m.albedo_texture = tex
	else:
		m.albedo_color = C_WOOD
	m.roughness = 0.88
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _facade_mat() -> StandardMaterial3D:
	## Weathered vertical timber for roundhouse walls (art palette).
	var m := StandardMaterial3D.new()
	var tex := load("res://assets/textures/roundhouse_facade.jpg") as Texture2D
	m.albedo_color = Color(0.90, 0.80, 0.68)
	if tex:
		m.albedo_texture = tex
		m.uv1_scale = Vector3(1.4, 1.4, 1.4)
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 6.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	else:
		m.albedo_color = C_WOOD
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _window_mat() -> StandardMaterial3D:
	var win_tex := load("res://assets/textures/roundhouse_window.jpg") as Texture2D
	var win_m := StandardMaterial3D.new()
	win_m.albedo_color = Color(1.05, 0.78, 0.42)
	if win_tex:
		win_m.albedo_texture = win_tex
		win_m.emission_texture = win_tex
	win_m.emission_enabled = true
	win_m.emission = Color(1.05, 0.68, 0.28)
	win_m.emission_energy_multiplier = 3.5
	win_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return win_m

func _magic_vein_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := load("res://assets/textures/magic_veins.jpg") as Texture2D
	if tex == null:
		tex = load("res://assets/textures/magic_roots.jpg") as Texture2D
	m.albedo_color = Color(1.05, 0.75, 1.15)
	if tex:
		m.albedo_texture = tex
		m.emission_texture = tex
	m.roughness = 0.55
	m.emission_enabled = true
	m.emission = Color(0.82, 0.28, 1.05)
	m.emission_energy_multiplier = 2.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _bark_mat() -> StandardMaterial3D:
	var m := _tex_mat("res://assets/textures/tree_bark_pictish.jpg", Color(0.95, 0.88, 0.82), 1.2, 0.9)
	if m.albedo_texture == null:
		return _purple_root_mat(Color(0.55, 0.34, 0.45))
	return m

func _dirt_path_mat() -> StandardMaterial3D:
	var m := _tex_mat("res://assets/textures/grass_dirt.jpg", Color(0.52, 0.42, 0.28), 1.8, 0.94, true, 5.0)
	if m.albedo_texture == null:
		m.albedo_color = C_DIRT
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, n: String = "Box") -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = n
	b.size = size
	b.position = pos
	b.material = mat
	b.use_collision = true
	parent.add_child(b)
	return b

func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, n: String = "Cyl", sides: int = 18, cone: bool = false) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.name = n
	c.radius = radius
	c.height = height
	c.sides = sides
	c.cone = cone
	c.position = pos
	c.material = mat
	c.use_collision = true
	parent.add_child(c)
	return c

func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, n: String = "Sphere", collide: bool = false) -> CSGSphere3D:
	var s := CSGSphere3D.new()
	s.name = n
	s.radius = radius
	s.radial_segments = 16
	s.rings = 8
	s.position = pos
	s.material = mat
	s.use_collision = collide
	parent.add_child(s)
	return s

func _label3d(parent: Node3D, text: String, pos: Vector3, col: Color = Color(1, 0.95, 0.85), size: int = 40) -> Label3D:
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = size
	lab.pixel_size = 0.012
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = col
	lab.outline_size = 6
	lab.position = pos
	parent.add_child(lab)
	return lab

func _area(parent: Node3D, name: String, pos: Vector3, radius: float, on_enter: Callable, on_exit: Callable = Callable()) -> Area3D:
	var area := Area3D.new()
	area.name = name
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	cs.shape = sph
	area.add_child(cs)
	parent.add_child(area)
	area.body_entered.connect(on_enter)
	if on_exit.is_valid():
		area.body_exited.connect(on_exit)
	return area

func _set_objective(text: String) -> void:
	if _objective:
		_objective.text = text

func _on_general_toast(msg: String) -> void:
	_show_toast(msg, 2.2)

func _show_toast(msg: String, dur: float = 2.5) -> void:
	if _toast:
		_toast.text = msg
		_toast.visible = true
		_toast.modulate.a = 1.0
	_toast_timer = dur

func _show_action(label: String) -> void:
	if _action_btn:
		_action_btn.text = label
		_action_btn.visible = true
		_action_btn.disabled = false
		_action_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_action_btn.z_index = 40

func _hide_action() -> void:
	if _action_btn:
		_action_btn.visible = false
	if _progress:
		_progress.visible = false

func _set_near(kind: String, label: String, toast_msg: String = "") -> void:
	_near = kind
	_show_action(label)
	if toast_msg != "":
		_show_toast(toast_msg, 2.0)

func _clear_near(kind: String) -> void:
	if _near == kind:
		_near = ""
		_hide_action()

func _on_jump_pressed() -> void:
	if _player and _player.has_method("try_jump"):
		_player.try_jump()

func _on_light_pressed() -> void:
	if _player and _player.has_method("do_light_swing"):
		if not _player.has_method("can_start_swing") or _player.can_start_swing():
			_pending_swing_btn = _light_btn
			_player.do_light_swing()

func _on_heavy_pressed() -> void:
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

func _on_action_pressed() -> void:
	match _near:
		"chess":
			_on_chess_play()
		"cernach":
			_on_cernach_play()
		"steps":
			_on_climb_tap()
		"climb_tree":
			_show_toast("Climb — you scramble into the branches.", 2.5)
		"dummy":
			if _player and _player.has_method("do_light_swing"):
				_player.do_light_swing()
		"druid":
			_open_druid_dialogue()
		"portal":
			_enter_portal()
		"exit":
			_leave_area()
		"door_north":
			_go_north()
		"door_hostel":
			_go_hostel()
		"door_coast":
			_go_coast()
		_:
			pass

func _on_stick_hit(heavy: bool) -> void:
	if heavy:
		_show_toast("Heavy blow!", 1.6)
	else:
		_show_toast("Thwack!", 1.4)

func _build_world() -> void:
	var world: Node3D = $World
	for child in world.get_children():
		child.queue_free()

	_build_landscape_ground(world)
	_build_meadow_mesh(world)
	_build_clear_path(world)
	_build_low_stone_walls(world)
	_build_side_stairs(world)
	_build_heather_sides(world)
	_build_side_boulders(world)
	_build_deep_backdrop(world)
	_build_sunny_sky(world)

	# Roundhouses flanking path — keep |x| >= ~9 so spine stays clear
	_roundhouse(world, Vector3(-11.5, 0.55, 11.0), 2.15, "HouseNW", false)
	_roundhouse(world, Vector3(11.8, 0.55, 10.5), 2.05, "HouseNE", false)
	_roundhouse(world, Vector3(-12.2, 0.6, 3.5), 2.0, "HouseMidL", false)
	_roundhouse(world, Vector3(11.5, 0.55, -6.0), 2.1, "HouseWarBoard", false)  # Chess Action
	_roundhouse(world, Vector3(-11.8, 0.65, -8.0), 1.95, "HouseMidL2", false)
	_roundhouse(world, Vector3(12.0, 0.6, -14.0), 2.0, "HouseCernach", false)  # Cernach Action
	_roundhouse(world, Vector3(-13.5, 0.7, -15.5), 1.7, "HouseFarL", false)
	_roundhouse(world, Vector3(-10.5, 0.55, -12.5), 2.15, "HouseMagic", true)

	# Training / agility OFF the path lane
	_build_steps(world, Vector3(-10.5, 0, 12.5))
	_build_climb_tree(world, Vector3(10.5, 0, 4.0))
	_build_dummy(world, Vector3(-10.8, 0, -1.0))

	_world_tree(world, Vector3(0, 0, -14.0))
	_build_druid(world, Vector3(3.8, 0, -11.0))

	# Chess + Cernach via Action on buildings (no freestanding door spam)
	_build_building_action(world, Vector3(11.5, 0, -4.2), "War-board", "chess", "Enter War-board", Color(0.95, 0.85, 0.55))
	_build_building_action(world, Vector3(12.0, 0, -12.2), "Cernach", "cernach", "Corner him", Color(0.9, 0.75, 0.55))

	# Three far doors
	_build_exit_gate(world, Vector3(0, 0, -28.0))           # Ahead behind tree
	_build_north_door(world, Vector3(-16.0, 0, -20.0))      # LEFT Glade
	_build_hostel_door(world, Vector3(16.0, 0, -20.0))     # RIGHT Hostel
	# Discreet secondary coast spur near Crossroads (labelled small, not door spam)
	_build_coast_spur(world, Vector3(6.5, 0, -26.5))

	# Pictish symbol stones — spiral / double-disc beside path (not in lane)
	var spiral := load("res://assets/textures/pictish_spiral.png") as Texture2D
	var disc := load("res://assets/textures/pictish_double_disc.png") as Texture2D
	var stone_spots: Array = [
		Vector3(-4.2, 0.9, 8.0), Vector3(4.4, 0.9, 6.5),
		Vector3(-4.5, 0.95, -2.0), Vector3(4.6, 0.95, -5.0),
		Vector3(-5.0, 1.0, -12.0), Vector3(5.0, 1.0, -15.0),
	]
	for i in range(stone_spots.size()):
		var pos: Vector3 = stone_spots[i]
		var sm := _wall_mat()
		sm.albedo_color = Color(0.82, 0.80, 0.76)
		var tex := spiral if (i % 2 == 0) else disc
		if tex:
			sm.albedo_texture = tex
			sm.uv1_scale = Vector3(1, 1, 1)
		var stone := _box(world, Vector3(0.5, 1.7, 0.32), pos, sm, "SymbolStone%d" % i)
		stone.rotation.y = deg_to_rad(float(i) * 18.0 - 40.0)

	# Warm sunny daylight — no surreal purple fill as primary
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-25, -140, 0)
	fill.light_color = Color(0.72, 0.82, 0.95)
	fill.light_energy = 0.28
	world.add_child(fill)

	var portal_fill := OmniLight3D.new()
	portal_fill.name = "PortalFill"
	portal_fill.position = Vector3(0, 2.4, -11.2)
	portal_fill.light_color = Color(0.95, 0.4, 1.05)
	portal_fill.light_energy = 4.2
	portal_fill.omni_range = 14.0
	world.add_child(portal_fill)

	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	# Sunny procedural sky — NOT sky-eyes / rainbow surreal default
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.35, 0.58, 0.92)
	psky.sky_horizon_color = Color(0.72, 0.82, 0.95)
	psky.ground_bottom_color = Color(0.28, 0.36, 0.22)
	psky.ground_horizon_color = Color(0.55, 0.62, 0.45)
	psky.sun_angle_max = 35.0
	psky.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = psky
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = Color(0.95, 0.92, 0.85)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.32
	e.glow_bloom = 0.18
	e.glow_hdr_threshold = 0.98
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.04
	e.adjustment_contrast = 1.02
	e.fog_enabled = true
	e.fog_light_color = Color(0.85, 0.88, 0.92)
	e.fog_density = 0.0028
	e.fog_aerial_perspective = 0.22
	e.fog_sky_affect = 0.08
	env_node.environment = e
	world.add_child(env_node)

func _build_landscape_ground(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "LandscapeGround"
	parent.add_child(root)
	var gm := _grass_mat()
	# Flat clear valley under path (no shin lips)
	_box(root, Vector3(14, 0.28, 52), Vector3(0, -0.28, -6), gm, "ValleyFloor")
	# Side banks — rounded feel, away from lane
	var bank_specs: Array = [
		[Vector3(-12.5, 0.08, 8), Vector3(8.5, 0.85, 12)],
		[Vector3(-13.0, 0.12, -4), Vector3(9.0, 0.95, 14)],
		[Vector3(-12.0, 0.15, -16), Vector3(8.5, 1.0, 12)],
		[Vector3(12.5, 0.08, 7), Vector3(8.5, 0.85, 12)],
		[Vector3(13.0, 0.12, -5), Vector3(9.0, 0.95, 14)],
		[Vector3(12.0, 0.15, -17), Vector3(8.5, 1.0, 12)],
	]
	for i in range(bank_specs.size()):
		var spec: Array = bank_specs[i]
		var bm := _grass_bank_mat()
		bm = bm.duplicate() as StandardMaterial3D
		bm.albedo_color = Color(0.92, 0.96, 0.84) if (i % 2 == 0) else Color(0.88, 0.94, 0.80)
		_box(root, spec[1], spec[0], bm, "Bank%d" % i)
	_box(root, Vector3(50, 0.8, 12), Vector3(0, 0.15, -34), gm, "RearRise")
	_box(root, Vector3(22, 0.28, 8), Vector3(0, -0.22, 15), gm, "SpawnApron")
	_box(root, Vector3(80, 0.45, 90), Vector3(0, -0.55, -4), gm, "OuterSkirt")

func _build_meadow_mesh(parent: Node3D) -> void:
	## Soft undulation OFF the path corridor (|x| > 3.2)
	var root := Node3D.new()
	root.name = "MeadowMesh"
	parent.add_child(root)
	var mi := MeshInstance3D.new()
	mi.name = "SoftMeadow"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 24
	var rows := 34
	var size_x := 28.0
	var size_z := 42.0
	var ox := -size_x * 0.5
	var oz := -22.0
	for z in range(rows):
		for x in range(cols):
			var u := float(x) / float(cols - 1)
			var v := float(z) / float(rows - 1)
			var px := ox + u * size_x
			var pz := oz + v * size_z
			var path_w := 1.0 - clampf(absf(px) / 3.4, 0.0, 1.0)
			var h := sin(px * 0.28) * 0.38 + cos(pz * 0.18) * 0.42 + sin((px + pz) * 0.14) * 0.22
			h *= (1.0 - path_w * 0.98)
			h = maxf(h, -0.02)
			var nrm := Vector3(-cos(px * 0.4) * 0.1, 1.0, sin(pz * 0.25) * 0.08).normalized()
			st.set_normal(nrm)
			st.set_uv(Vector2(u * 4.0, v * 6.0))
			st.add_vertex(Vector3(px, 0.02 + h, pz))
	for z in range(rows - 1):
		for x in range(cols - 1):
			var i0 := z * cols + x
			var i1 := i0 + 1
			var i2 := i0 + cols
			var i3 := i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	st.generate_normals()
	mi.mesh = st.commit()
	var gm := _grass_mat().duplicate() as StandardMaterial3D
	gm.albedo_color = Color(0.97, 0.99, 0.92)
	mi.material_override = gm
	root.add_child(mi)

func _build_clear_path(parent: Node3D) -> void:
	## Wide paved spine — dead clear for run / jump / swing (no shin clutter)
	var root := Node3D.new()
	root.name = "BrickPath"
	parent.add_child(root)
	var brick_mat := _brick_mat()
	var dirt_mat := _dirt_path_mat()
	var pts: Array[Vector3] = []
	var z := 15.0
	while z >= -24.0:
		pts.append(Vector3(0.0, 0.06, z))
		z -= 2.4
	var chunk_w := 5.2
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var mid := (a + b) * 0.5
		var dir := b - a
		var length := maxf(dir.length(), 0.5)
		var w := chunk_w
		if i < 2:
			w = 5.6
		elif i > pts.size() - 5:
			w = 5.8
		# Dirt verge (low — step lip ~0.08m under cobble)
		var verge := StaticBody3D.new()
		verge.name = "PathVerge%d" % i
		verge.position = mid + Vector3(0, -0.02, 0)
		verge.collision_layer = 1
		var vmi := MeshInstance3D.new()
		var vbm := BoxMesh.new()
		vbm.size = Vector3(w + 1.6, 0.06, length + 0.2)
		vmi.mesh = vbm
		vmi.material_override = dirt_mat
		verge.add_child(vmi)
		var vcs := CollisionShape3D.new()
		var vsh := BoxShape3D.new()
		vsh.size = Vector3(w + 1.6, 0.06, length + 0.2)
		vcs.shape = vsh
		verge.add_child(vcs)
		root.add_child(verge)
		# Cobble top — lip ~0.12m above verge (well under 0.4m step-up)
		var body := StaticBody3D.new()
		body.name = "PathChunk%d" % i
		body.position = mid + Vector3(0, 0.04, 0)
		body.collision_layer = 1
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, 0.10, length + 0.15)
		mi.mesh = bm
		var mat_i := brick_mat.duplicate() as StandardMaterial3D
		mat_i.uv1_offset = Vector3(float(i) * 0.13, float(i % 3) * 0.09, 0)
		mi.material_override = mat_i
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(w, 0.10, length + 0.15)
		cs.shape = sh
		body.add_child(cs)
		root.add_child(body)
	_label3d(root, "Path → Tree", Vector3(0, 1.5, 13.5), Color(0.95, 0.85, 0.55), 34)

func _build_low_stone_walls(parent: Node3D) -> void:
	## Low Pictish stone walls flanking path (northstar path_and_wall) — ~0.55m high
	var root := Node3D.new()
	root.name = "LowStoneWalls"
	parent.add_child(root)
	var wm := _wall_mat()
	wm.albedo_color = Color(0.90, 0.89, 0.86)
	for side in [-1.0, 1.0]:
		var z := 13.5
		var seg := 0
		while z > -22.0:
			var wh := 0.48 + float(seg % 3) * 0.06
			var ww := 0.42 + float(seg % 2) * 0.08
			var wl := 1.55
			# Skip gap for stairs (~z 7 to 9)
			if not (z < 9.5 and z > 6.5):
				_box(root, Vector3(ww, wh, wl), Vector3(side * 3.15, wh * 0.5, z), wm, "Wall%d_%d" % [int(side), seg])
			z -= 1.65
			seg += 1

func _build_side_stairs(parent: Node3D) -> void:
	## Wooden stairs from path down to side grass (northstar) — both sides
	var root := Node3D.new()
	root.name = "SideStairs"
	parent.add_child(root)
	var wood := _mat(Color(0.38, 0.26, 0.16), 0.92)
	for side in [-1.0, 1.0]:
		var side_f: float = float(side)
		var base := Vector3(side_f * 3.4, 0.0, 8.0)
		for si in range(4):
			var t: float = float(si)
			var step_h: float = 0.12  # small lips — walkable
			var sx: float = side_f * (0.55 + t * 0.55)
			var sy: float = 0.08 - t * step_h
			var sz: float = 0.0
			_box(root, Vector3(1.1, 0.1, 1.35), base + Vector3(sx, sy, sz), wood, "Step%d_%d" % [int(side_f), si])
		# Rail posts
		for ri in range(3):
			_cyl(root, 0.07, 0.85, base + Vector3(side_f * (0.9 + float(ri) * 0.7), 0.35, -0.7), wood, "Rail%d_%d" % [int(side_f), ri], 8, false)
			_box(root, Vector3(0.08, 0.06, 0.85), base + Vector3(side * (1.25 + float(ri) * 0.35), 0.72, -0.35), wood, "RailBar%d_%d" % [int(side), ri])

func _build_heather_sides(parent: Node3D) -> void:
	## Heather / meadow clumps ONLY outside path walls (|x| > 3.6)
	var root := Node3D.new()
	root.name = "Heather"
	parent.add_child(root)
	var hm := _heather_mat()
	var spots: Array[Vector3] = []
	for z_i in range(18):
		var z := 12.0 - float(z_i) * 1.6
		spots.append(Vector3(-5.2 - float(z_i % 3) * 0.4, 0.12, z))
		spots.append(Vector3(5.3 + float(z_i % 3) * 0.35, 0.12, z - 0.3))
	var extras: Array[Vector3] = [
		Vector3(-7.5, 0.2, 9.0), Vector3(7.8, 0.2, 7.5),
		Vector3(-8.5, 0.25, 1.0), Vector3(8.2, 0.25, -3.0),
		Vector3(-7.0, 0.28, -10.0), Vector3(7.2, 0.28, -12.0),
		Vector3(-9.5, 0.35, 5.0), Vector3(9.8, 0.35, -8.0),
	]
	for e in extras:
		spots.append(e)
	for i in range(spots.size()):
		var p: Vector3 = spots[i]
		if absf(p.x) < 3.8:
			continue
		# Olive / sage bush volumes — subtle dusty purple only on alternate fleck tint
		var col := Color(0.36, 0.46, 0.30) if (i % 2 == 0) else Color(0.40, 0.48, 0.34)
		if i % 5 == 0:
			col = Color(0.42, 0.40, 0.44)  # dusty mauve fleck, not neon purple
		var blob_mat := _heather_mat().duplicate() as StandardMaterial3D
		blob_mat.albedo_color = col
		_sphere(root, 0.45 + float(i % 4) * 0.08, p, blob_mat, "HeatherBlob%d" % i, false)
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.4, 0.7)
		quad.mesh = qm
		quad.position = p + Vector3(0, 0.25, 0)
		quad.rotation_degrees = Vector3(-70, float(i * 37 % 80) - 40.0, 0)
		quad.material_override = hm
		root.add_child(quad)

func _build_side_boulders(parent: Node3D) -> void:
	## Mossy stones off the lane only
	var root := Node3D.new()
	root.name = "MossyBoulders"
	parent.add_child(root)
	var bm := StandardMaterial3D.new()
	var tex := load("res://assets/textures/moss_boulder.jpg") as Texture2D
	if tex:
		bm.albedo_texture = tex
		bm.albedo_color = Color(0.92, 0.95, 0.88)
	else:
		bm.albedo_color = Color(0.45, 0.48, 0.42)
	bm.roughness = 0.92
	var spots: Array = [
		[Vector3(-6.5, 0.2, 10.0), 0.55],
		[Vector3(6.8, 0.18, 9.0), 0.5],
		[Vector3(-7.5, 0.25, 2.0), 0.7],
		[Vector3(7.2, 0.22, -1.0), 0.65],
		[Vector3(-8.0, 0.3, -9.0), 0.75],
		[Vector3(8.2, 0.28, -11.0), 0.7],
		[Vector3(-6.0, 0.2, -18.0), 0.5],
		[Vector3(6.2, 0.2, -19.0), 0.48],
	]
	for i in range(spots.size()):
		var data: Array = spots[i]
		var p: Vector3 = data[0]
		var r: float = data[1]
		var body := StaticBody3D.new()
		body.name = "Boulder%d" % i
		body.position = p
		body.collision_layer = 1
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.5
		sm.radial_segments = 12
		sm.rings = 8
		mi.mesh = sm
		mi.scale = Vector3(1.1, 0.7, 1.0)
		mi.material_override = bm.duplicate()
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = r * 0.8
		cs.shape = sh
		body.add_child(cs)
		root.add_child(body)

func _build_deep_backdrop(parent: Node3D) -> void:
	## Prefer look_pass settlement backdrop; else sunny hills northstar crop.
	var root := Node3D.new()
	root.name = "DeepBackdrop"
	parent.add_child(root)
	var mat := LookPassMats.settlement_backdrop()
	if mat == null:
		var tex := load("res://assets/textures/backdrop_deep_horizon.jpg") as Texture2D
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 1, 1)
		if tex:
			mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_receive_shadows = true
		mat.render_priority = -20
	var plate := MeshInstance3D.new()
	plate.name = "DeepHorizonPlate"
	var qm := QuadMesh.new()
	qm.size = Vector2(100, 55)
	plate.mesh = qm
	plate.position = Vector3(0, 16.0, -55)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.material_override = mat
	root.add_child(plate)
	for side in [-1, 1]:
		var wrap := MeshInstance3D.new()
		wrap.name = "DeepWrap%d" % side
		var wq := QuadMesh.new()
		wq.size = Vector2(55, 48)
		wrap.mesh = wq
		wrap.position = Vector3(float(side) * 52.0, 14.0, -42)
		wrap.rotation_degrees = Vector3(0, float(-side) * 28.0, 0)
		wrap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var wm := mat.duplicate() as StandardMaterial3D
		wm.albedo_color = Color(1, 1, 1, 0.7)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wrap.material_override = wm
		root.add_child(wrap)
	# Soft side hills
	var hill_m := _grass_mat()
	hill_m.albedo_color = Color(0.55, 0.65, 0.42)
	_sphere(root, 5.5, Vector3(-22, 0.4, -32), hill_m, "HillL", false)
	_sphere(root, 5.0, Vector3(22, 0.35, -34), hill_m, "HillR", false)

func _build_sunny_sky(parent: Node3D) -> void:
	## Soft sky billboard from sunny northstar crop — NO sky-eyes / rainbow
	var root := Node3D.new()
	root.name = "SkyDome"
	parent.add_child(root)
	var tex := load("res://assets/art/look/standard/MAIN_hills_sky_codia.jpg") as Texture2D
	if tex == null:
		return
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = tex
	sm.albedo_color = Color(1, 1, 1, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.render_priority = -6
	var rear := MeshInstance3D.new()
	rear.name = "SkyBand"
	var qm := QuadMesh.new()
	qm.size = Vector2(90, 28)
	rear.mesh = qm
	rear.position = Vector3(0, 38.0, -62)
	rear.material_override = sm
	root.add_child(rear)

func _build_steps(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "AgilityHill"
	root.position = pos
	parent.add_child(root)
	var grass := _grass_mat()
	var mound := CSGSphere3D.new()
	mound.name = "Mound"
	mound.radius = 2.2
	mound.radial_segments = 16
	mound.rings = 10
	mound.position = Vector3(0.0, 0.12, 0.0)
	mound.scale = Vector3(1.4, 0.4, 1.2)
	mound.material = grass
	mound.use_collision = false
	root.add_child(mound)
	var berm := CSGCylinder3D.new()
	berm.radius = 2.6
	berm.height = 0.32
	berm.sides = 14
	berm.position = Vector3(0, 0.05, 0)
	berm.material = grass
	berm.use_collision = true
	root.add_child(berm)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var foot := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.4
	cyl.height = 0.4
	foot.shape = cyl
	foot.position = Vector3(0, 0.1, 0)
	body.add_child(foot)
	root.add_child(body)
	_label3d(root, "Agility", Vector3(0, 2.0, 0), Color(0.7, 0.9, 1.0), 34)
	_area(parent, "StepsZone", pos + Vector3(0, 0.9, 0), 2.8, _on_steps_enter, _on_steps_exit)

func _build_climb_tree(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "ClimbTree"
	root.position = pos
	parent.add_child(root)
	_cyl(root, 0.32, 3.8, Vector3(0, 1.9, 0), _mat(C_TRUNK), "Trunk", 12, false)
	_sphere(root, 1.6, Vector3(0, 4.0, 0), _mat(C_FOLIAGE), "Foliage", false)
	_label3d(root, "Climb", Vector3(0, 5.0, 0), Color(0.75, 1.0, 0.7), 36)
	_area(parent, "ClimbTreeZone", pos + Vector3(0, 1.0, 0), 2.0, _on_climb_tree_enter, _on_climb_tree_exit)

func _build_dummy(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "TrainingDummy"
	root.position = pos
	parent.add_child(root)
	var wood := _mat(C_WOOD)
	_cyl(root, 0.18, 2.2, Vector3(0, 1.1, 0), wood, "Post", 10, false)
	_box(root, Vector3(1.6, 0.18, 0.18), Vector3(0, 1.7, 0), wood, "Crossbar")
	_box(root, Vector3(0.35, 0.5, 0.25), Vector3(0, 1.35, 0), _mat(Color(0.55, 0.45, 0.35)), "Pad")
	_label3d(root, "Strength", Vector3(0, 2.6, 0), Color(1.0, 0.75, 0.55), 34)
	_area(parent, "DummyZone", pos + Vector3(0, 1.0, 0), 2.0, _on_dummy_enter, _on_dummy_exit)
	var hurt := Area3D.new()
	hurt.name = "DummyHurt"
	hurt.position = Vector3(0, 1.35, 0)
	hurt.collision_layer = 4
	hurt.collision_mask = 0
	hurt.monitoring = false
	hurt.monitorable = true
	hurt.add_to_group("hittable")
	var hcs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(1.4, 1.6, 0.8)
	hcs.shape = hbox
	hurt.add_child(hcs)
	root.add_child(hurt)

func _build_druid(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Druid"
	root.position = pos
	parent.add_child(root)
	_cyl(root, 0.38, 1.5, Vector3(0, 0.85, 0), _mat(C_ROBE), "Robe", 14, false)
	_cyl(root, 0.42, 0.55, Vector3(0, 1.55, 0), _mat(Color(0.18, 0.22, 0.35)), "Hood", 12, true)
	_sphere(root, 0.22, Vector3(0, 1.55, 0.12), _mat(Color(0.82, 0.68, 0.52)), "Face", false)
	_label3d(root, "Druid", Vector3(0, 2.5, 0), Color(0.85, 0.9, 1.0), 40)
	_area(parent, "DruidZone", pos + Vector3(0, 0.9, 0), 2.2, _on_druid_enter, _on_druid_exit)

func _build_building_action(parent: Node3D, pos: Vector3, label: String, near_kind: String, action_label: String, col: Color) -> void:
	## Action hotspot on a roundhouse — banner + area (no freestanding door frame spam)
	var root := Node3D.new()
	root.name = "BuildingAction_%s" % near_kind
	root.position = pos
	parent.add_child(root)
	var wood := _mat(C_WOOD)
	_cyl(root, 0.08, 3.2, Vector3(0, 1.6, 0.9), wood, "BannerPole", 8, false)
	var banner := MeshInstance3D.new()
	banner.name = "Banner"
	var bq := QuadMesh.new()
	bq.size = Vector2(1.1, 1.8)
	banner.mesh = bq
	banner.position = Vector3(0.55, 2.2, 0.9)
	var bm := _mat(Color(0.18, 0.12, 0.28))
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	banner.material_override = bm
	root.add_child(banner)
	_label3d(root, label, Vector3(0.55, 2.5, 1.05), col, 36)
	var on_enter := _on_chess_enter if near_kind == "chess" else _on_cernach_enter
	var on_exit := _on_chess_exit if near_kind == "chess" else _on_cernach_exit
	_area(parent, "Zone_%s" % near_kind, pos + Vector3(0, 1.0, 1.0), 2.6, on_enter, on_exit)

func _roundhouse(parent: Node3D, pos: Vector3, radius: float, n: String, magic: bool = false) -> void:
	var root := Node3D.new()
	root.name = n
	root.position = pos
	parent.add_child(root)
	var skirt := _grass_mat()
	skirt.albedo_color = Color(0.82, 0.90, 0.70)
	_cyl(root, radius * 1.55, 0.45, Vector3(0, -0.08, 0), skirt, "MoundSkirt", 18, false)
	var wall_h := 1.55
	var wall_mat := _magic_roots_mat() if magic else _wall_mat()
	# Darker timber-feel for northern roundhouse walls
	if not magic:
		wall_mat = _facade_mat()
		wall_mat.albedo_color = Color(0.52, 0.40, 0.30)
	var combiner := CSGCombiner3D.new()
	combiner.name = "WallCSG"
	combiner.use_collision = true
	root.add_child(combiner)
	var wall := CSGCylinder3D.new()
	wall.radius = radius
	wall.height = wall_h
	wall.sides = 22
	wall.position = Vector3(0, wall_h * 0.5, 0)
	wall.material = wall_mat
	combiner.add_child(wall)
	var door_cut := CSGBox3D.new()
	door_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	door_cut.size = Vector3(0.9, 1.2, 0.8)
	door_cut.position = Vector3(0, 0.6, radius * 0.78)
	combiner.add_child(door_cut)
	var roof_h := radius * 2.35
	var thatch := _thatch_mat()
	if magic:
		thatch.emission_enabled = true
		thatch.emission = Color(0.55, 0.25, 0.85)
		thatch.emission_energy_multiplier = 0.35
	_cyl(root, radius * 1.28, roof_h, Vector3(0, wall_h + roof_h * 0.42, 0), thatch, "Roof", 22, true)
	var door_quad := MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(0.78, 1.1)
	door_quad.mesh = dq
	door_quad.position = Vector3(0, 0.55, radius * 0.55)
	door_quad.material_override = _door_mat()
	root.add_child(door_quad)
	var win_m := _window_mat()
	for wi in range(2):
		var side := 1.0 if wi == 0 else -1.0
		var win := MeshInstance3D.new()
		var wq := QuadMesh.new()
		wq.size = Vector2(0.42, 0.36)
		win.mesh = wq
		win.position = Vector3(side * radius * 0.5, 0.9, radius * 0.58)
		win.rotation_degrees = Vector3(0, side * -22.0, 0)
		win.material_override = win_m
		root.add_child(win)

func _world_tree(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "WorldTree"
	root.position = pos
	parent.add_child(root)
	var bark := _bark_mat()
	_cyl(root, 1.9, 13.0, Vector3(0, 6.5, 0), bark, "Trunk", 18, false)
	_cyl(root, 2.5, 1.5, Vector3(0, 0.5, 0), bark, "RootBole", 18, false)
	for i in range(5):
		var a := deg_to_rad(float(i) * 72.0)
		_cyl(root, 0.45, 2.2, Vector3(sin(a) * 2.3, 0.4, cos(a) * 2.3), bark, "Root%d" % i, 10, false)
	_sphere(root, 6.8, Vector3(0, 14.5, 0), _mat(Color(0.28, 0.52, 0.26)), "Foliage", false)
	_sphere(root, 4.2, Vector3(3.0, 13.0, 1.5), _mat(Color(0.24, 0.46, 0.22)), "Foliage2", false)
	_sphere(root, 3.8, Vector3(-2.8, 12.8, -1.2), _mat(Color(0.30, 0.50, 0.24)), "Foliage3", false)
	# Purple portal almond in trunk face (+z toward spawn)
	_cyl(root, 1.65, 0.35, Vector3(0, 2.1, 2.55), _mat(Color(0.22, 0.14, 0.1)), "AlmondBark", 28, false)
	var almond_shell := MeshInstance3D.new()
	var ash := SphereMesh.new()
	ash.radius = 1.1
	ash.height = 2.2
	almond_shell.mesh = ash
	almond_shell.position = Vector3(0, 2.1, 2.82)
	almond_shell.scale = Vector3(0.68, 1.7, 0.26)
	almond_shell.material_override = _mat(Color(0.65, 0.18, 0.85), 0.35, Color(0.9, 0.35, 1.05), 3.2)
	root.add_child(almond_shell)
	_cyl(root, 1.4, 0.12, Vector3(0, 2.1, 2.98), _mat(Color(0.98, 0.38, 0.95), 0.3, Color(1.0, 0.45, 1.0), 4.0), "PortalRing", 32, false)
	var portal_mat := _portal_look_mat(9.5)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.2, 3.8)
	quad.mesh = qm
	quad.position = Vector3(0, 2.1, 3.15)
	quad.material_override = portal_mat
	root.add_child(quad)
	var glow := CSGSphere3D.new()
	glow.radius = 1.1
	glow.position = Vector3(0, 2.1, 2.98)
	glow.scale = Vector3(0.9, 1.6, 0.35)
	var glow_m := _mat(Color(0.98, 0.42, 1.05, 0.6), 0.12, Color(1.0, 0.48, 1.05), 10.0)
	glow_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material = glow_m
	glow.use_collision = false
	root.add_child(glow)
	var enter := Label3D.new()
	enter.text = "Enter tree"
	enter.font_size = 48
	enter.pixel_size = 0.012
	enter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	enter.modulate = Color(1.0, 0.75, 1.0)
	enter.outline_size = 8
	enter.position = Vector3(0, 4.3, 3.2)
	root.add_child(enter)
	var portal_omni := OmniLight3D.new()
	portal_omni.position = Vector3(0, 2.1, 3.4)
	portal_omni.light_color = Color(0.92, 0.38, 1.05)
	portal_omni.light_energy = 4.8
	portal_omni.omni_range = 11.0
	root.add_child(portal_omni)
	_area(parent, "PortalZone", pos + Vector3(0, 1.0, 2.8), 2.8, _on_portal_entered, _on_portal_exited)

func _build_exit_gate(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "ExitGate"
	root.position = pos
	parent.add_child(root)
	var stone := _wall_mat()
	_box(root, Vector3(0.7, 4.0, 0.7), Vector3(-2.5, 2.0, 0), stone, "PillarL")
	_box(root, Vector3(0.7, 4.0, 0.7), Vector3(2.5, 2.0, 0), stone, "PillarR")
	_box(root, Vector3(5.6, 0.5, 0.7), Vector3(0, 4.2, 0), stone, "Lintel")
	# Low step ~0.35m — jumpable / floor_snap friendly
	_box(root, Vector3(3.2, 0.35, 1.3), Vector3(0, 0.18, 1.5), stone, "ExitStep")
	_label3d(root, "Crossroads", Vector3(0, 5.0, 0), Color(0.95, 0.9, 0.7), 42)
	_label3d(root, "Ahead · ROAD", Vector3(0, 1.8, 1.5), Color(0.85, 0.9, 1.0), 26)
	_area(parent, "ExitZone", pos + Vector3(0, 1.2, 1.2), 2.8, _on_exit_enter, _on_exit_exit)

func _build_north_door(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "NorthDoor"
	root.position = pos
	parent.add_child(root)
	var stone := _wall_mat()
	_box(root, Vector3(0.55, 3.2, 0.55), Vector3(-1.5, 1.6, 0), stone, "PostL")
	_box(root, Vector3(0.55, 3.2, 0.55), Vector3(1.5, 1.6, 0), stone, "PostR")
	_box(root, Vector3(3.6, 0.42, 0.55), Vector3(0, 3.35, 0), stone, "Lintel")
	_label3d(root, "Druid Glade", Vector3(0, 4.15, 0), Color(0.75, 0.88, 1.0), 38)
	_label3d(root, "LEFT", Vector3(0, 3.55, 0), Color(0.7, 0.82, 0.95), 26)
	_area(parent, "NorthDoorZone", pos + Vector3(0, 1.0, 0), 2.6, _on_north_enter, _on_north_exit)

func _build_hostel_door(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "HostelDoor"
	root.position = pos
	parent.add_child(root)
	var stone := _wall_mat()
	_box(root, Vector3(0.55, 3.2, 0.55), Vector3(-1.5, 1.6, 0), stone, "PostL")
	_box(root, Vector3(0.55, 3.2, 0.55), Vector3(1.5, 1.6, 0), stone, "PostR")
	_box(root, Vector3(3.6, 0.42, 0.55), Vector3(0, 3.35, 0), stone, "Lintel")
	_label3d(root, "Hostel", Vector3(0, 4.15, 0), Color(0.9, 0.78, 0.55), 38)
	_label3d(root, "RIGHT", Vector3(0, 3.55, 0), Color(0.85, 0.72, 0.5), 26)
	_area(parent, "HostelDoorZone", pos + Vector3(0, 1.0, 0), 2.5, _on_hostel_enter, _on_hostel_exit)

func _build_coast_spur(parent: Node3D, pos: Vector3) -> void:
	## Discreet secondary — small marker near Crossroads, not a third freestanding plaza
	var root := Node3D.new()
	root.name = "CoastSpur"
	root.position = pos
	parent.add_child(root)
	var stone := _wall_mat()
	_box(root, Vector3(0.35, 1.8, 0.35), Vector3(0, 0.9, 0), stone, "Marker")
	_label3d(root, "Coast road", Vector3(0, 2.3, 0), Color(0.7, 0.85, 0.95), 26)
	_area(parent, "CoastDoorZone", pos + Vector3(0, 0.8, 0), 2.0, _on_coast_enter, _on_coast_exit)


func _refresh_objective() -> void:
	if GameState.well_visited or GameState.well_defence_won:
		_phase = "leave"
		_set_objective("Tree · War-board house · Glade L · Crossroads ahead · Hostel R")
	elif _druid_talked or _warboard_done:
		_phase = "leave"
		_set_objective("Enter tree, War-board house, Glade, Crossroads, or Hostel")
	else:
		_phase = "walk"
		_set_objective("Walk the yard — path to Tree; doors ahead / left / right")

func _build_dialogue_ui() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var panel := PanelContainer.new()
	panel.name = "DialoguePanel"
	panel.visible = false
	panel.z_index = 60
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280.0
	panel.offset_right = 280.0
	panel.offset_top = -130.0
	panel.offset_bottom = 130.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.94)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 14
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Druid"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(title)

	var body := Label.new()
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	body.custom_minimum_size = Vector2(500, 80)
	vbox.add_child(body)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(_close_dialogue)
	vbox.add_child(close_btn)

	_dialogue = panel
	_dialogue_body = body

func _open_druid_dialogue() -> void:
	if _near != "druid":
		return
	var pname := GameState.display_name()
	var lines := [
		"Peace on your path, %s. The symbol stones remember." % pname,
		"%s — the war-board waits. Command as General when you are ready." % pname,
		"Root and river guide you, %s. When the yard is known, Leave by the gate." % pname,
	]
	var line: String = lines[randi() % lines.size()]
	if _dialogue_body:
		_dialogue_body.text = line
	if _dialogue:
		_dialogue.visible = true
	if not _druid_talked:
		_druid_talked = true
		GameState.druid_talked = true
		_refresh_objective()

func _close_dialogue() -> void:
	if _dialogue:
		_dialogue.visible = false

func _player_body(body: Node) -> bool:
	return body.is_in_group("player")

func _on_druid_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("druid", "Talk", "Tap Talk")

func _on_druid_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("druid")
	_close_dialogue()

func _on_steps_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_climb_taps = 0
	_set_near("steps", "Climb", "Climb the hill")
	if _progress:
		_progress.visible = true
		_progress.text = "Climb 0 / 5"

func _on_steps_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("steps")

func _on_climb_tap() -> void:
	if _near != "steps":
		return
	_climb_taps += 1
	if _progress:
		_progress.visible = true
		_progress.text = "Climb %d / 5" % mini(_climb_taps, 5)
	if _climb_taps >= 5:
		_show_toast("Agility — hill conquered!", 2.5)
		_clear_near("steps")

func _on_climb_tree_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("climb_tree", "Climb", "Climb the tree")

func _on_climb_tree_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("climb_tree")

func _on_dummy_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("dummy", "Hit", "Swing at the training post")

func _on_dummy_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("dummy")

func _on_portal_entered(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("portal", "Enter tree", "World Tree — tap Enter tree")

func _on_portal_exited(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("portal")

func _enter_portal() -> void:
	if _near != "portal" or _scene_leaving:
		return
	_scene_leaving = true
	_show_toast("Into the roots…", 0.8)
	get_tree().change_scene_to_file("res://scenes/tree_well_room.tscn")

func _on_chess_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("chess", "Enter War-board", "War-board / chess stone — tap Enter War-board")

func _on_chess_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("chess")

func _on_chess_play() -> void:
	if _near != "chess" or _scene_leaving:
		return
	_scene_leaving = true
	_warboard_done = true
	GameState.warboard_visited = true
	get_tree().change_scene_to_file("res://scenes/chess_board.tscn")

func _on_exit_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("exit", "Enter Crossroads", "Crossroads — Jump the step, then Enter Crossroads")

func _on_exit_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("exit")

func _leave_area() -> void:
	if _near != "exit" or _scene_leaving:
		return
	_scene_leaving = true
	_show_toast("Toward the Crossroads…", 1.0)
	GameState.go_to("res://scenes/travel_road.tscn", "from_yard", "yard")


func _on_cernach_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("cernach", "Corner him", "Cernach's Corner — tap Corner him")

func _on_cernach_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("cernach")

func _on_cernach_play() -> void:
	if _near != "cernach" or _scene_leaving:
		return
	_scene_leaving = true
	GameState.go_to("res://scenes/cernachs_corner.tscn", "from_yard", "yard")

func _go_north() -> void:
	if _near != "door_north" or _scene_leaving:
		return
	_scene_leaving = true
	_show_toast("Toward the Druid Glade…", 0.8)
	GameState.go_to("res://scenes/north_holy.tscn", "from_yard", "yard")

func _on_north_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("door_north", "Enter Glade", "Druid Glade / North Holy — tap Enter Glade")

func _on_north_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("door_north")




func _go_coast() -> void:
	if _near != "door_coast" or _scene_leaving:
		return
	_scene_leaving = true
	_show_toast("Toward the Coast…", 0.8)
	GameState.go_to("res://scenes/coast.tscn", "from_yard", "yard")


func _go_hostel() -> void:
	if _near != "door_hostel" or _scene_leaving:
		return
	_scene_leaving = true
	_show_toast("Toward the Hostel…", 0.8)
	GameState.go_to("res://scenes/hostel.tscn", "from_yard", "yard")


func _on_coast_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("door_coast", "Enter Coast", "Coast — tap Enter Coast")


func _on_coast_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("door_coast")


func _on_hostel_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("door_hostel", "Enter Hostel", "Hostel — tap Enter Hostel")


func _on_hostel_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("door_hostel")

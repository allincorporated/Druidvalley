extends Node3D
## Inner root chamber — FF7-style box room (B): flat floor, solid walls, open readable space.
## Fixed / mild cinematic cam framed on well — NOT in roof. Spring-arm follow disabled via configure_interior.

@onready var _toast: Label = $UI/Toast
@onready var _hint: Label = $UI/HintLabel
@onready var _objective: Label = $UI/ObjectiveLabel
@onready var _action_btn: Button = $UI/ActionButton
@onready var _jump_btn: Button = $UI/JumpButton
@onready var _player: CharacterBody3D = $Player

const C_ROOT := Color(0.18, 0.10, 0.08)
const C_BARK := Color(0.22, 0.14, 0.10)
const C_STONE := Color(0.32, 0.30, 0.38)
const C_PURPLE := Color(0.45, 0.18, 0.72)
const C_GLOW := Color(0.70, 0.35, 1.0)
const C_WATER := Color(0.35, 0.15, 0.70)
const C_ROBE := Color(0.28, 0.16, 0.42)
const C_FLOOR := Color(0.14, 0.10, 0.16)

const SETTLEMENT_SCENE := "res://scenes/settlement_stub.tscn"

var _near: String = ""
var _scene_leaving: bool = false
var _toast_timer: float = 0.0
var _dialogue: Control = null
var _dialogue_title: Label = null
var _dialogue_body: Label = null
var _dialogue_opts: VBoxContainer = null
var _water_mesh: CSGCylinder3D = null
var _column_mesh: CSGCylinder3D = null
var _motes: Array = []
var _pulse_t: float = 0.0
var _room_cam: Camera3D = null
var _cam_anchor: Vector3 = Vector3(0.0, 3.4, 5.6)
var _cam_look: Vector3 = Vector3(0.0, 1.2, 0.0)
var _cam_drift_t: float = 0.0

func _ready() -> void:
	Music.play_area("tree")
	_build_world()
	if _hint:
		_hint.text = "WASD / stick · Talk to the seer · Defend at the well · Leave tree"
	if _toast:
		_toast.visible = false
	_hide_action()
	_wire_hud()
	_build_dialogue_ui()
	_set_objective("Root chamber (box room) — Talk, Defend, Leave tree")
	if _player:
		# Clear of well rim, door posts, and root ribs — on walkable floor.
		_player.global_position = Vector3(0.0, 0.35, 4.8)
		_player.rotation.y = PI
		if _player.has_method("configure_interior"):
			_player.configure_interior(true)
	_setup_interior_camera()
	call_deferred("_ensure_room_cam")
	GameState.well_visited = true
	LomnasBanner.attach(self, "Lomnas: Under the roots the Seeing Well dreams. Defend it, or leave back to the yard.")
	_show_toast("The roots close behind you…", 2.2)

func _wire_hud() -> void:
	if _action_btn:
		_action_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_action_btn.z_index = 40
		_action_btn.pressed.connect(_on_action_pressed)
	if _jump_btn:
		_jump_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_jump_btn.z_index = 40
		_jump_btn.pressed.connect(_on_jump_pressed)

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and _toast:
			_toast.visible = false
	_pulse_t += delta
	_update_interior_camera(delta)
	if _water_mesh and _water_mesh.material is StandardMaterial3D:
		var m := _water_mesh.material as StandardMaterial3D
		m.emission_energy_multiplier = 3.4 + sin(_pulse_t * 2.4) * 1.6
	if _column_mesh and is_instance_valid(_column_mesh):
		_column_mesh.rotation.y += delta * 0.35
		if _column_mesh.material is StandardMaterial3D:
			var cm := _column_mesh.material as StandardMaterial3D
			cm.emission_energy_multiplier = 5.5 + sin(_pulse_t * 3.0) * 2.2
	for mote in _motes:
		if is_instance_valid(mote):
			mote.position.y += delta * (0.35 + float(mote.get_meta("spd", 0.4)))
			mote.position.x += sin(_pulse_t * 2.0 + float(mote.get_meta("ph", 0.0))) * delta * 0.15
			mote.position.z += cos(_pulse_t * 1.7 + float(mote.get_meta("ph", 0.0))) * delta * 0.15
			if mote.position.y > 5.5:
				mote.position.y = 0.9



func _setup_interior_camera() -> void:
	## FF7 box room cam — eye-level 3/4 on well + floor. NEVER in roof.
	var cam := Camera3D.new()
	cam.name = "InteriorCam"
	cam.fov = 52.0
	cam.near = 0.1
	cam.far = 80.0
	cam.current = true
	add_child(cam)
	_room_cam = cam
	# FF7 re-verify: eye-level 3/4 inside box (ceiling ~5.2) — never roof-cam
	_cam_anchor = Vector3(0.0, 2.25, 7.0)
	_cam_look = Vector3(0.0, 0.85, -0.2)
	_cam_drift_t = 0.0
	_room_cam.global_position = _cam_anchor
	_room_cam.look_at(_cam_look, Vector3.UP)

func _update_interior_camera(delta: float) -> void:
	if _room_cam == null or not is_instance_valid(_room_cam):
		return
	_cam_drift_t += delta
	var amp := 0.12
	var ox := sin(_cam_drift_t * 0.16) * amp
	var oz := cos(_cam_drift_t * 0.12) * (amp * 0.35)
	var oy := sin(_cam_drift_t * 0.1) * 0.03
	var pos := _cam_anchor + Vector3(ox, oy, oz)
	pos.y = clampf(pos.y, 2.05, 2.65)
	_room_cam.global_position = pos
	var look := _cam_look + Vector3(ox * 0.1, 0.0, 0.0)
	_room_cam.look_at(look, Vector3.UP)


func _ensure_room_cam() -> void:
	## Re-assert InteriorCam after player _ready race; spring stay off.
	if _player and _player.has_method("configure_interior"):
		_player.configure_interior(true)
	if _room_cam and is_instance_valid(_room_cam):
		_room_cam.current = true
		_room_cam.global_position = _cam_anchor
		_room_cam.look_at(_cam_look, Vector3.UP)

func _tex_mat(path: String, color: Color = Color(1, 1, 1), uv_scale: float = 3.0, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	var tex := load(path) as Texture2D
	if tex:
		m.albedo_texture = tex
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

func _root_mat(tint: Color = Color(0.72, 0.55, 0.48)) -> StandardMaterial3D:
	## Pass 4: root-cavern bark walls from well_room_root_cavern.jpg.
	var m := _tex_mat("res://assets/textures/well_root_wall.jpg", tint, 1.6, 0.88)
	if m.albedo_texture == null:
		m = _tex_mat("res://assets/textures/root_purple.jpg", tint, 2.0, 0.82)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.18, 0.45)
	m.emission_energy_multiplier = 0.22
	return m

func _wood_floor_mat() -> StandardMaterial3D:
	var m := _tex_mat("res://assets/textures/well_wood_floor.jpg", Color(0.95, 0.88, 0.82), 1.2, 0.78)
	if m.albedo_texture == null:
		m = _tex_mat("res://assets/textures/thatch.jpg", Color(0.55, 0.4, 0.28), 2.0, 0.85)
	return m

func _well_stone_mat(tint: Color = Color(0.88, 0.9, 0.85)) -> StandardMaterial3D:
	var m := _tex_mat("res://assets/textures/well_stone_moss.jpg", tint, 1.4, 0.9)
	if m.albedo_texture == null:
		m = _tex_mat("res://assets/textures/stone_wall.jpg", tint, 2.0, 0.9)
	return m

func _purple_glow_mat(energy: float = 6.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := load("res://assets/textures/well_purple_glow.jpg") as Texture2D
	if tex == null:
		tex = load("res://assets/textures/well_purple_core.jpg") as Texture2D
	m.albedo_color = Color(1.15, 0.7, 1.35)
	if tex:
		m.albedo_texture = tex
		m.emission_texture = tex
	m.roughness = 0.18
	m.emission_enabled = true
	m.emission = Color(0.85, 0.35, 1.1)
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

func _lantern_mat() -> StandardMaterial3D:
	var m := _tex_mat("res://assets/textures/well_lantern.jpg", Color(1.0, 0.95, 0.88), 1.0, 0.85)
	if m.albedo_texture == null:
		m = _well_stone_mat(Color(0.8, 0.78, 0.74))
	return m

func _door_wood_mat() -> StandardMaterial3D:
	var m := _tex_mat("res://assets/textures/well_door_wood.jpg", Color(0.95, 0.88, 0.8), 1.0, 0.82)
	if m.albedo_texture == null:
		m = _tex_mat("res://assets/textures/roundhouse_door.jpg", Color(0.7, 0.55, 0.4), 1.0, 0.85)
	return m

func _stone_mat(tint: Color = Color(0.85, 0.82, 0.78)) -> StandardMaterial3D:
	## Fallback / plaque stone.
	return _well_stone_mat(tint)

func _mat(color: Color, rough: float = 0.9, emis: Color = Color(0, 0, 0, 1), emis_e: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, n: String = "Box", collide: bool = true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = n
	b.size = size
	b.position = pos
	b.material = mat
	b.use_collision = collide
	parent.add_child(b)
	return b

func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, n: String = "Cyl", sides: int = 18, cone: bool = false, collide: bool = true) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.name = n
	c.radius = radius
	c.height = height
	c.sides = sides
	c.cone = cone
	c.position = pos
	c.material = mat
	c.use_collision = collide
	parent.add_child(c)
	return c

func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, n: String = "Sphere", collide: bool = false) -> CSGSphere3D:
	var s := CSGSphere3D.new()
	s.name = n
	s.radius = radius
	s.radial_segments = 14
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

func _on_action_pressed() -> void:
	match _near:
		"seer":
			_open_seer_dialogue()
		"well":
			_start_defence()
		"door":
			_leave_tree()
		_:
			pass

func _build_world() -> void:
	var world: Node3D = $World
	for child in world.get_children():
		child.queue_free()
	_motes.clear()
	_column_mesh = null
	_water_mesh = null

	# TRUE FF7 box — flat floor, four walls, door gap, flat ceiling (NOT cavern).
	var floor_m := _wood_floor_mat()
	var wall_m := _tex_mat("res://assets/textures/roundhouse_facade.jpg", Color(0.72, 0.62, 0.52), 1.4, 0.88)
	if wall_m.albedo_texture == null:
		wall_m = _mat(Color(0.42, 0.32, 0.38), 0.9)
	var ceil_m := _mat(Color(0.22, 0.16, 0.24), 0.95)

	_box(world, Vector3(15.0, 0.4, 15.0), Vector3(0, -0.2, 0), floor_m, "Floor", true)
	var wh := 5.2
	_box(world, Vector3(15.4, wh, 0.5), Vector3(0, wh * 0.5, -7.4), wall_m, "WallN", true)
	_box(world, Vector3(0.5, wh, 15.4), Vector3(-7.4, wh * 0.5, 0), wall_m, "WallW", true)
	_box(world, Vector3(0.5, wh, 15.4), Vector3(7.4, wh * 0.5, 0), wall_m, "WallE", true)
	# South wall with door gap
	_box(world, Vector3(5.4, wh, 0.5), Vector3(-5.0, wh * 0.5, 7.4), wall_m, "WallSL", true)
	_box(world, Vector3(5.4, wh, 0.5), Vector3(5.0, wh * 0.5, 7.4), wall_m, "WallSR", true)
	_box(world, Vector3(4.6, 1.4, 0.5), Vector3(0, wh - 0.7, 7.4), wall_m, "WallSLintel", true)
	# Ceiling visual only — no collision so cam never embeds in roof
	_box(world, Vector3(15.2, 0.3, 15.2), Vector3(0, wh + 0.15, 0), ceil_m, "Ceiling", false)

	for i in range(4):
		var sx := -6.2 if (i % 2 == 0) else 6.2
		var sz := -6.2 if (i < 2) else 6.2
		_box(world, Vector3(0.55, wh - 0.2, 0.55), Vector3(sx, (wh - 0.2) * 0.5, sz), wall_m, "Corner%d" % i, false)

	_build_seeing_well(world, Vector3(0, 0, 0))
	_build_lanterns(world)
	_build_seer(world, Vector3(-3.4, 0, -2.2))
	_build_door(world, Vector3(0, 0, 7.0))

	var lamp := OmniLight3D.new()
	lamp.name = "WellLamp"
	lamp.position = Vector3(0, 2.4, 0)
	lamp.light_color = Color(0.78, 0.38, 1.05)
	lamp.light_energy = 2.8
	lamp.omni_range = 12.0
	lamp.shadow_enabled = true
	world.add_child(lamp)

	var fill := OmniLight3D.new()
	fill.name = "FillLamp"
	fill.position = Vector3(2.2, 2.5, 4.2)
	fill.light_color = Color(0.45, 0.32, 0.55)
	fill.light_energy = 0.85
	fill.omni_range = 10.0
	world.add_child(fill)

	var key := OmniLight3D.new()
	key.name = "DoorKey"
	key.position = Vector3(0, 2.4, 5.5)
	key.light_color = Color(0.55, 0.4, 0.75)
	key.light_energy = 0.6
	key.omni_range = 6.0
	world.add_child(key)

	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.03, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.18, 0.38)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_bloom = 0.22
	e.glow_hdr_threshold = 0.95
	e.fog_enabled = true
	e.fog_light_color = Color(0.2, 0.1, 0.32)
	e.fog_density = 0.002
	env_node.environment = e
	world.add_child(env_node)

func _build_radial_floor(parent: Node3D) -> void:
	## Radial wood planks around the well — walkable disk + spoke wedges.
	var root := Node3D.new()
	root.name = "RadialFloor"
	parent.add_child(root)
	var fm := _wood_floor_mat()
	# Base collision disk
	_cyl(root, 7.5, 0.38, Vector3(0, -0.2, 0), fm, "FloorDisk", 32, false, true)
	# Visual radial wedges (sunburst)
	var wedges := 16
	for i in range(wedges):
		var ang := float(i) * TAU / float(wedges)
		var plank := MeshInstance3D.new()
		plank.name = "Plank%d" % i
		var bm := BoxMesh.new()
		bm.size = Vector3(1.05, 0.06, 6.8)
		plank.mesh = bm
		plank.position = Vector3(sin(ang) * 3.2, 0.02, cos(ang) * 3.2)
		plank.rotation.y = ang
		var mat_i := fm.duplicate() as StandardMaterial3D
		mat_i.uv1_offset = Vector3(float(i) * 0.07, float(i % 3) * 0.11, 0)
		mat_i.albedo_color = Color(0.92, 0.85, 0.78) if (i % 2 == 0) else Color(0.85, 0.78, 0.7)
		plank.material_override = mat_i
		root.add_child(plank)
	# Inner ring near well
	_cyl(root, 2.4, 0.08, Vector3(0, 0.04, 0), fm, "InnerRing", 24, false, false)
	# Moss patches near rim
	var moss_tex := load("res://assets/textures/well_moss.jpg") as Texture2D
	var mm := StandardMaterial3D.new()
	if moss_tex:
		mm.albedo_texture = moss_tex
	mm.albedo_color = Color(0.55, 0.75, 0.4)
	mm.roughness = 0.95
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in range(6):
		var ma := float(mi) * TAU / 6.0
		var mq := MeshInstance3D.new()
		mq.name = "FloorMoss%d" % mi
		var q := QuadMesh.new()
		q.size = Vector2(1.4, 0.9)
		mq.mesh = q
		mq.position = Vector3(sin(ma) * 2.0, 0.08, cos(ma) * 2.0)
		mq.rotation_degrees = Vector3(-90, rad_to_deg(ma), 0)
		mq.material_override = mm
		root.add_child(mq)

func _add_perimeter_walls(parent: Node3D, radius: float, segments: int) -> void:
	## Thin box segments around the room — collision only on the ring, not the interior volume.
	var mat := _root_mat(Color(0.45, 0.32, 0.3))
	var wall_h := 3.2
	var thick := 0.55
	var arc := TAU / float(segments)
	var chord := 2.0 * radius * sin(arc * 0.5) + 0.15
	for i in range(segments):
		var ang := float(i) * arc
		var x := cos(ang) * radius
		var z := sin(ang) * radius
		var b := _box(parent, Vector3(thick, wall_h, chord), Vector3(x, wall_h * 0.5, z), mat, "WallSeg%d" % i, true)
		b.rotation.y = -ang

func _build_seeing_well(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "SeeingWell"
	root.position = pos
	parent.add_child(root)

	# Mossy stone rim
	_cyl(root, 1.6, 0.9, Vector3(0, 0.48, 0), _well_stone_mat(Color(0.85, 0.88, 0.82)), "Rim", 22, false)
	_cyl(root, 1.78, 0.22, Vector3(0, 1.0, 0), _well_stone_mat(Color(0.78, 0.82, 0.76)), "RimTop", 22, false)
	# Moss collar
	var moss_m := _tex_mat("res://assets/textures/well_moss.jpg", Color(0.6, 0.85, 0.45), 1.0, 0.95)
	moss_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cyl(root, 1.72, 0.14, Vector3(0, 0.85, 0), moss_m, "MossCollar", 18, false, false)

	# Glowing purple water surface
	var water := CSGCylinder3D.new()
	water.name = "Water"
	water.radius = 1.28
	water.height = 0.2
	water.sides = 22
	water.position = Vector3(0, 0.78, 0)
	var wm := _purple_glow_mat(4.2)
	wm.roughness = 0.15
	water.material = wm
	water.use_collision = false
	root.add_child(water)
	_water_mesh = water

	# Rising purple light column
	var column := CSGCylinder3D.new()
	column.name = "PurpleColumn"
	column.radius = 0.38
	column.height = 3.2
	column.sides = 16
	column.position = Vector3(0, 2.4, 0)
	var col_m := _purple_glow_mat(7.5)
	col_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	col_m.albedo_color = Color(1.1, 0.65, 1.35, 0.55)
	column.material = col_m
	column.use_collision = false
	root.add_child(column)
	_column_mesh = column

	# Soft outer column haze
	var haze := CSGCylinder3D.new()
	haze.name = "ColumnHaze"
	haze.radius = 0.65
	haze.height = 2.8
	haze.sides = 14
	haze.position = Vector3(0, 2.2, 0)
	var hz := _purple_glow_mat(3.2)
	hz.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hz.albedo_color = Color(0.9, 0.45, 1.15, 0.22)
	haze.material = hz
	haze.use_collision = false
	root.add_child(haze)

	# Floating purple motes
	for i in range(14):
		var mote := CSGSphere3D.new()
		mote.name = "Mote%d" % i
		mote.radius = 0.06 + float(i % 3) * 0.025
		mote.radial_segments = 8
		mote.rings = 6
		var ang := float(i) * TAU / 14.0
		mote.position = Vector3(sin(ang) * (0.35 + float(i % 4) * 0.12), 1.0 + float(i % 5) * 0.55, cos(ang) * (0.35 + float(i % 3) * 0.1))
		mote.material = _mat(Color(0.85, 0.4, 1.1), 0.2, Color(0.95, 0.45, 1.15), 4.5)
		mote.use_collision = false
		mote.set_meta("spd", 0.25 + float(i % 5) * 0.12)
		mote.set_meta("ph", float(i) * 0.7)
		root.add_child(mote)
		_motes.append(mote)

	_sphere(root, 0.5, Vector3(0, 1.55, 0), _purple_glow_mat(5.0), "Mist", false)

	var well_omni := OmniLight3D.new()
	well_omni.name = "ColumnLight"
	well_omni.position = Vector3(0, 2.5, 0)
	well_omni.light_color = Color(0.85, 0.4, 1.1)
	well_omni.light_energy = 3.0
	well_omni.omni_range = 8.0
	root.add_child(well_omni)

	var spiral := load("res://assets/textures/pictish_spiral.png") as Texture2D
	if spiral:
		var plaque := CSGBox3D.new()
		plaque.name = "SpiralPlaque"
		plaque.size = Vector3(0.7, 0.7, 0.08)
		plaque.position = Vector3(0, 0.6, -1.75)
		var pm := _well_stone_mat(Color(0.7, 0.68, 0.64))
		pm.albedo_texture = spiral
		plaque.material = pm
		plaque.use_collision = false
		root.add_child(plaque)

	_label3d(root, "Seeing Well", Vector3(0, 2.6, 0), Color(0.9, 0.75, 1.05), 44)
	_area(parent, "WellZone", pos + Vector3(0, 0.8, 0), 2.4, _on_well_enter, _on_well_exit)

func _build_lanterns(parent: Node3D) -> void:
	## Pagoda-like stone lanterns with warm glow around the well.
	var root := Node3D.new()
	root.name = "Lanterns"
	parent.add_child(root)
	var spots: Array[Vector3] = [
		Vector3(3.2, 0, 2.4), Vector3(-3.2, 0, 2.2),
		Vector3(3.4, 0, -2.6), Vector3(-3.4, 0, -2.4),
		Vector3(0.2, 0, -3.8), Vector3(4.2, 0, 0.2),
	]
	for i in range(spots.size()):
		_build_one_lantern(root, spots[i], "Lantern%d" % i)

func _build_one_lantern(parent: Node3D, pos: Vector3, n: String) -> void:
	var root := Node3D.new()
	root.name = n
	root.position = pos
	parent.add_child(root)
	var stone := _lantern_mat()
	# Base pedestal
	_cyl(root, 0.32, 0.22, Vector3(0, 0.11, 0), stone, "Base", 10, false)
	_cyl(root, 0.22, 0.55, Vector3(0, 0.45, 0), stone, "Pillar", 10, false)
	# Light chamber (emissive warm)
	var chamber := _cyl(root, 0.28, 0.42, Vector3(0, 0.95, 0), _mat(Color(1.0, 0.75, 0.35), 0.35, Color(1.0, 0.7, 0.3), 3.5), "Chamber", 10, false)
	chamber.use_collision = false
	# Pagoda roof tiers
	_cyl(root, 0.42, 0.12, Vector3(0, 1.2, 0), stone, "Roof1", 10, true, false)
	_cyl(root, 0.28, 0.18, Vector3(0, 1.38, 0), stone, "Roof2", 8, true, false)
	_cyl(root, 0.08, 0.2, Vector3(0, 1.55, 0), stone, "Finial", 6, true, false)
	var ol := OmniLight3D.new()
	ol.name = "WarmGlow"
	ol.position = Vector3(0, 0.95, 0)
	ol.light_color = Color(1.0, 0.68, 0.32)
	ol.light_energy = 1.4
	ol.omni_range = 4.5
	root.add_child(ol)

func _build_seer(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Seer"
	root.position = pos
	parent.add_child(root)

	_cyl(root, 0.36, 1.45, Vector3(0, 0.8, 0), _mat(C_ROBE), "Robe", 12, false)
	_cyl(root, 0.40, 0.5, Vector3(0, 1.5, 0), _mat(Color(0.20, 0.12, 0.32)), "Hood", 10, true)
	_sphere(root, 0.20, Vector3(0, 1.48, 0.12), _mat(Color(0.78, 0.62, 0.48)), "Face", false)
	_cyl(root, 0.05, 1.8, Vector3(0.45, 1.0, 0), _root_mat(Color(0.48, 0.30, 0.45)), "Staff", 6, false, false)
	_sphere(root, 0.12, Vector3(0.45, 1.95, 0), _mat(C_PURPLE, 0.4, C_GLOW, 2.0), "StaffTip", false)

	_label3d(root, "Seer", Vector3(0, 2.45, 0), Color(0.90, 0.78, 1.0), 38)
	_area(parent, "SeerZone", pos + Vector3(0, 0.9, 0), 2.0, _on_seer_enter, _on_seer_exit)

func _build_door(parent: Node3D, pos: Vector3) -> void:
	## Arched wood door set in root wall — Leave tree back to yard.
	var root := Node3D.new()
	root.name = "RootDoor"
	root.position = pos
	parent.add_child(root)

	_box(root, Vector3(0.55, 3.2, 0.55), Vector3(-1.4, 1.6, 0), _root_mat(Color(0.55, 0.42, 0.38)), "PostL")
	_box(root, Vector3(0.55, 3.2, 0.55), Vector3(1.4, 1.6, 0), _root_mat(Color(0.55, 0.42, 0.38)), "PostR")
	_box(root, Vector3(3.4, 0.45, 0.55), Vector3(0, 3.3, 0), _root_mat(Color(0.52, 0.4, 0.36)), "Lintel")
	# Arch hint (half-sphere top)
	var arch := CSGSphere3D.new()
	arch.name = "Arch"
	arch.radius = 1.25
	arch.radial_segments = 14
	arch.rings = 8
	arch.position = Vector3(0, 2.85, 0)
	arch.scale = Vector3(1.15, 0.55, 0.35)
	arch.material = _root_mat(Color(0.5, 0.38, 0.34))
	arch.use_collision = false
	root.add_child(arch)
	# Wood door face
	var door := MeshInstance3D.new()
	door.name = "DoorFace"
	var dq := QuadMesh.new()
	dq.size = Vector2(2.0, 2.6)
	door.mesh = dq
	door.position = Vector3(0, 1.45, 0.08)
	door.material_override = _door_wood_mat()
	root.add_child(door)
	# Soft purple edge glow (exit cue)
	var portal := CSGBox3D.new()
	portal.name = "DoorGlow"
	portal.size = Vector3(2.15, 2.7, 0.06)
	portal.position = Vector3(0, 1.5, -0.02)
	var pg := _mat(Color(0.55, 0.28, 0.9, 0.45), 0.35, C_GLOW, 2.2)
	pg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	portal.material = pg
	portal.use_collision = false
	root.add_child(portal)

	_label3d(root, "Leave tree", Vector3(0, 3.9, 0), Color(0.85, 0.75, 1.0), 40)
	_area(parent, "DoorZone", pos + Vector3(0, 1.0, 0), 2.2, _on_door_enter, _on_door_exit)

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
	panel.offset_left = -320.0
	panel.offset_right = 320.0
	panel.offset_top = -200.0
	panel.offset_bottom = 200.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.12, 0.95)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 14
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.border_color = Color(0.55, 0.30, 0.85, 0.8)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "Druid"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	vbox.add_child(title)

	var body := Label.new()
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	body.custom_minimum_size = Vector2(560, 90)
	vbox.add_child(body)

	var opts := VBoxContainer.new()
	opts.name = "Options"
	opts.add_theme_constant_override("separation", 8)
	vbox.add_child(opts)

	var settle_btn := Button.new()
	settle_btn.text = "Show me the settlement"
	settle_btn.custom_minimum_size = Vector2(0, 44)
	settle_btn.focus_mode = Control.FOCUS_NONE
	settle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	settle_btn.pressed.connect(_on_dialogue_settlement)
	opts.add_child(settle_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.pressed.connect(_close_dialogue)
	opts.add_child(close_btn)

	_dialogue = panel
	_dialogue_title = title
	_dialogue_body = body
	_dialogue_opts = opts

func _open_seer_dialogue() -> void:
	## Talk opens dialogue only — settlement is a CHOICE, never auto-open.
	if _near != "seer":
		return
	var pname := GameState.display_name()
	var lines := [
		"Peace in the roots, %s. Shadow-things hunger for the Seeing Well." % pname,
		"%s — stand by the well and Defend. Flick the Sunrise Wheel — Inf, Arch, Cav runes clear the wisps." % pname,
		"Match Inf/Arch/Cav at zenith when a wisp hits the gold ring, %s. If one drinks the well, the glow fails." % pname,
	]
	if _dialogue_title:
		_dialogue_title.text = "Druid"
	if _dialogue_body:
		_dialogue_body.text = lines[randi() % lines.size()]
	if _dialogue:
		_dialogue.visible = true

func _on_dialogue_settlement() -> void:
	## Dialogue option only — player must choose this; Talk alone does not open settlement.
	if _scene_leaving:
		return
	if not ResourceLoader.exists(SETTLEMENT_SCENE):
		_show_toast("Settlement map not ready yet.", 1.6)
		return
	_scene_leaving = true
	_close_dialogue()
	_show_toast("The settlement map unfolds…", 0.7)
	get_tree().change_scene_to_file(SETTLEMENT_SCENE)

func _close_dialogue() -> void:
	if _dialogue:
		_dialogue.visible = false

func _start_defence() -> void:
	if _near != "well" or _scene_leaving:
		return
	_scene_leaving = true
	_show_toast("The well stirs — defend!", 0.8)
	get_tree().change_scene_to_file("res://scenes/well_defence.tscn")

func _player_body(body: Node) -> bool:
	return body.is_in_group("player")

func _on_seer_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("seer", "Talk", "Tap Talk")

func _on_seer_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("seer")
	_close_dialogue()

func _on_well_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("well", "Defend", "Seeing Well — tap Defend")

func _on_well_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("well")

func _on_door_enter(body: Node) -> void:
	if not _player_body(body):
		return
	_set_near("door", "Leave tree", "Return to the yard")

func _on_door_exit(body: Node) -> void:
	if not _player_body(body):
		return
	_clear_near("door")

func _leave_tree() -> void:
	if _near != "door" or _scene_leaving:
		return
	_scene_leaving = true
	# Restore yard follow cam before scene swap (yard player _ready also restores)
	if _player and _player.has_method("configure_interior"):
		_player.configure_interior(false)
	if _room_cam and is_instance_valid(_room_cam):
		_room_cam.current = false
	GameState.spawn_at_tree = true
	GameState.spawn_point = "from_tree"
	GameState.last_area = "tree"
	_show_toast("Back through the roots…", 0.8)
	get_tree().change_scene_to_file("res://scenes/druid_yard.tscn")

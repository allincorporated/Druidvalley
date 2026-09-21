extends Node3D
## Standing look — meadow tile ground, ONE mountain far wall (N),
## other walls use hills/sky plate. Native textures; no UV squash of art.

const MEADOW := "res://assets/art/look/grass_painterly_northstar.jpg"
const FAR_N := "res://assets/art/look/standard/MAIN_mountain_one_side.jpg"
const SIDE := "res://assets/art/look/standard/MAIN_hills_sky_codia.jpg"

@onready var _player: CharacterBody3D = $Player

var _near_portal: String = ""  # "" | "chess" | "cernach" | "tree" | "settlement"

func _ready() -> void:
	_build_env()
	_build_ground()
	_build_walls()
	_build_portals()
	_place_player()
	var obj := get_node_or_null("UI/ObjectiveLabel") as Label
	if obj:
		obj.text = "FunYard — War-board · Cernach · Tree · Settlement"
	var jump := get_node_or_null("UI/JumpButton") as Button
	if jump:
		jump.mouse_filter = Control.MOUSE_FILTER_STOP
		if not jump.pressed.is_connected(_on_jump_pressed):
			jump.pressed.connect(_on_jump_pressed)
	var act := get_node_or_null("UI/ActionButton") as Button
	if act:
		act.visible = false
		act.mouse_filter = Control.MOUSE_FILTER_STOP
		if not act.pressed.is_connected(_on_action_pressed):
			act.pressed.connect(_on_action_pressed)
	# Bag / General — right-side drawer so you can feel the form on phone
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui:
		GeneralPanel.attach(self, ui, _player)


func _place_player() -> void:
	if _player == null:
		return
	var sp := "default"
	if GameState:
		sp = str(GameState.spawn_point)
		GameState.spawn_point = "default"
		GameState.spawn_at_tree = false
	match sp:
		"from_chess":
			_player.global_position = Vector3(8.0, 0.5, 4.0)
		"from_cernach":
			_player.global_position = Vector3(-8.0, 0.5, 4.0)
		"from_tree":
			_player.global_position = Vector3(0.0, 0.5, -6.0)
		"from_yard":
			_player.global_position = Vector3(0.0, 0.5, 6.0)
		_:
			_player.global_position = Vector3(0.0, 0.5, 8.0)
	if _player.has_method("configure_interior"):
		_player.configure_interior(false)


func _on_jump_pressed() -> void:
	if _player and _player.has_method("try_jump"):
		_player.try_jump()


func _on_action_pressed() -> void:
	match _near_portal:
		"chess":
			if GameState:
				GameState.last_area = "yard"
			get_tree().change_scene_to_file("res://scenes/chess_board.tscn")
		"cernach":
			if GameState:
				GameState.last_area = "yard"
			get_tree().change_scene_to_file("res://scenes/cernachs_corner.tscn")
		"tree":
			if GameState:
				GameState.last_area = "yard"
			get_tree().change_scene_to_file("res://scenes/tree_well_room.tscn")
		"settlement":
			if GameState and GameState.has_method("go_to"):
				GameState.go_to("res://scenes/druid_yard.tscn", "default", "fun_yard")
			else:
				get_tree().change_scene_to_file("res://scenes/druid_yard.tscn")


func _build_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, 25, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	add_child(sun)

	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var e := Environment.new()
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.35, 0.55, 0.88)
	psky.sky_horizon_color = Color(0.72, 0.82, 0.94)
	psky.ground_bottom_color = Color(0.25, 0.38, 0.20)
	psky.ground_horizon_color = Color(0.50, 0.62, 0.40)
	var sky := Sky.new()
	sky.sky_material = psky
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = e
	add_child(env_node)


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _unshaded(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1)
	if tex:
		m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


func _build_ground() -> void:
	var world := _world()
	var tex := _tex(MEADOW)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	if tex:
		m.albedo_texture = tex
		## One baked plate across the whole yard — no tile seams
		m.uv1_scale = Vector3(1.0, 1.0, 1.0)
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var size := 56.0
	var mi := MeshInstance3D.new()
	mi.name = "MeadowFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mi.mesh = plane
	mi.material_override = m
	world.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "MeadowCollision"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.5, size)
	cs.shape = box
	cs.position = Vector3(0, -0.25, 0)
	body.add_child(cs)
	world.add_child(body)


func _world() -> Node3D:
	var world := get_node_or_null("World") as Node3D
	if world == null:
		world = Node3D.new()
		world.name = "World"
		add_child(world)
	return world


func _add_wall(parent: Node3D, tex: Texture2D, pos: Vector3, yaw_deg: float, wall_w: float, wall_h: float, name: String, uv_off: Vector3 = Vector3.ZERO) -> void:
	## Wall quad sized to image aspect so we don't stretch the painting.
	var mat := _unshaded(tex)
	mat = mat.duplicate() as StandardMaterial3D
	## Inset UV so we never sample the 1px black frame on plate edges
	mat.uv1_scale = Vector3(0.94, 0.96, 1.0)
	mat.uv1_offset = Vector3(0.03, 0.02, 0.0) + uv_off
	var mi := MeshInstance3D.new()
	mi.name = name
	var q := QuadMesh.new()
	q.size = Vector2(wall_w, wall_h)
	mi.mesh = q
	mi.position = pos
	mi.rotation_degrees = Vector3(0, yaw_deg, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = mat
	parent.add_child(mi)


func _build_walls() -> void:
	## Lower horizon ring; N = mountains only; other sides hills/sky; 3 panels each.
	var world := _world()
	var far_tex := _tex(FAR_N)
	var side_tex := _tex(SIDE)
	var aspect := 1792.0 / 1008.0
	var wall_h := 11.0
	var wall_w := wall_h * aspect
	var dist := 28.0
	var y := wall_h * 0.5 + 0.15
	var copies := 3
	## Overlap panels ~8% so black edge hairlines never meet as a gap
	var step := wall_w * 0.92
	var span := step * float(copies - 1) + wall_w

	for i in range(copies):
		var x := -span * 0.5 + wall_w * 0.5 + float(i) * step
		_add_wall(world, far_tex, Vector3(x, y, -dist), 0.0, wall_w, wall_h, "WallNorth_Mountains_%d" % i, Vector3(float(i) * 0.05, 0.0, 0))

	for i in range(copies):
		var x := -span * 0.5 + wall_w * 0.5 + float(i) * step
		_add_wall(world, side_tex, Vector3(x, y, dist), 180.0, wall_w, wall_h, "WallSouth_%d" % i, Vector3(0.08 + float(i) * 0.12, 0.0, 0))
	for i in range(copies):
		var z := -span * 0.5 + wall_w * 0.5 + float(i) * step
		_add_wall(world, side_tex, Vector3(-dist, y, z), 90.0, wall_w, wall_h, "WallWest_%d" % i, Vector3(0.28 + float(i) * 0.10, 0.03, 0))
		_add_wall(world, side_tex, Vector3(dist, y, z), -90.0, wall_w, wall_h, "WallEast_%d" % i, Vector3(0.52 + float(i) * 0.10, -0.02, 0))


func _build_portals() -> void:
	var world := _world()
	# Chess war-board — east
	_make_portal(world, Vector3(10.0, 0.0, 2.0), "chess", "War-board", Color(0.95, 0.82, 0.45))
	# Cernach — west
	_make_portal(world, Vector3(-10.0, 0.0, 2.0), "cernach", "Cernach Corner", Color(0.85, 0.55, 0.35))
	# Tree / 3rd game — north toward mountains
	_make_portal(world, Vector3(0.0, 0.0, -10.0), "tree", "World Tree", Color(0.45, 0.75, 0.55))
	# Full settlement yard (buildings · Crossroads · six areas)
	_make_portal(world, Vector3(0.0, 0.0, 12.0), "settlement", "Settlement Yard", Color(0.70, 0.78, 0.95))


func _make_portal(parent: Node3D, pos: Vector3, kind: String, title: String, col: Color) -> void:
	var root := Node3D.new()
	root.name = "Portal_%s" % kind
	root.position = pos
	parent.add_child(root)
	# Visible pad
	var pad := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.2, 0.15, 3.2)
	pad.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.35
	pad.material_override = mat
	pad.position = Vector3(0, 0.08, 0)
	root.add_child(pad)
	# Pillar marker
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.22
	cyl.height = 2.2
	pole.mesh = cyl
	pole.position = Vector3(0, 1.1, -1.2)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = col.darkened(0.25)
	pole.material_override = pm
	root.add_child(pole)
	var lab := Label3D.new()
	lab.text = title
	lab.font_size = 42
	lab.modulate = Color(1, 0.95, 0.8)
	lab.position = Vector3(0, 2.5, -1.2)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(lab)
	# Trigger — player is collision_layer 2
	var area := Area3D.new()
	area.name = "Trigger"
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 2.0
	sh.height = 3.0
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	area.add_child(cs)
	root.add_child(area)
	area.body_entered.connect(func(body: Node) -> void: _on_portal_enter(kind, title, body))
	area.body_exited.connect(func(body: Node) -> void: _on_portal_exit(kind, body))


func _on_portal_enter(kind: String, title: String, body: Node) -> void:
	if not (body is CharacterBody3D):
		return
	_near_portal = kind
	var act := get_node_or_null("UI/ActionButton") as Button
	if act:
		act.text = "Enter %s" % title
		act.visible = true
	var obj := get_node_or_null("UI/ObjectiveLabel") as Label
	if obj:
		obj.text = "Near %s — press Action" % title


func _on_portal_exit(kind: String, body: Node) -> void:
	if not (body is CharacterBody3D):
		return
	if _near_portal == kind:
		_near_portal = ""
		var act := get_node_or_null("UI/ActionButton") as Button
		if act:
			act.visible = false
		var obj := get_node_or_null("UI/ObjectiveLabel") as Label
		if obj:
			obj.text = "FunYard — War-board · Cernach · Tree · Settlement"

extends RefCounted
## CSG / door helpers for six-area greybox spine.
class_name WalkAreaKit

static func mat(color: Color, rough: float = 0.9, emis: Color = Color(0, 0, 0, 1), emis_e: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	return m

static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, n: String = "Box", collide: bool = true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = n
	b.size = size
	b.position = pos
	b.material = material
	b.use_collision = collide
	parent.add_child(b)
	return b

static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, n: String = "Cyl", sides: int = 16, cone: bool = false, collide: bool = true) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.name = n
	c.radius = radius
	c.height = height
	c.sides = sides
	c.cone = cone
	c.position = pos
	c.material = material
	c.use_collision = collide
	parent.add_child(c)
	return c

static func label3d(parent: Node3D, text: String, pos: Vector3, col: Color = Color(1, 0.95, 0.85), size: int = 40) -> Label3D:
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

static func door_area(parent: Node3D, name: String, pos: Vector3, radius: float, on_enter: Callable, on_exit: Callable = Callable()) -> Area3D:
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

static func door_frame(parent: Node3D, pos: Vector3, title: String, stone: Material, yaw: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Door_%s" % title.replace(" ", "")
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	box(root, Vector3(0.55, 3.4, 0.55), Vector3(-1.5, 1.7, 0), stone, "PostL")
	box(root, Vector3(0.55, 3.4, 0.55), Vector3(1.5, 1.7, 0), stone, "PostR")
	box(root, Vector3(3.6, 0.45, 0.55), Vector3(0, 3.5, 0), stone, "Lintel")
	label3d(root, title, Vector3(0, 4.2, 0), Color(0.95, 0.9, 0.7), 42)
	return root

static func sun_env(parent: Node3D, sky: Color, ambient: Color, sun_energy: float = 1.15) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	parent.add_child(sun)
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = e
	parent.add_child(env_node)

static func is_player(body: Node) -> bool:
	return body != null and body.is_in_group("player")


static func attach_general_panel(host: Node, ui: CanvasLayer = null, player: Node = null):
	## Shared HUD helper — opens General panel from yard (and other walk areas later).
	if host == null:
		return null
	return GeneralPanel.attach(host, ui, player)


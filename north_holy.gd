extends Node3D
## North Holy greybox — stone circle + Goblet Well + Druid fire. Doors: Yard, Road.

@onready var _player: CharacterBody3D = $Player
@onready var _toast: Label = $UI/Toast
@onready var _hint: Label = $UI/HintLabel
@onready var _objective: Label = $UI/ObjectiveLabel
@onready var _action_btn: Button = $UI/ActionButton
@onready var _jump_btn: Button = $UI/JumpButton

var _near: String = ""
var _leaving: bool = false
var _toast_t: float = 0.0

const SPAWNS := {
	"default": Vector3(0.0, 0.4, 10.0),
	"from_yard": Vector3(0.0, 0.4, 10.0),
	"from_road": Vector3(10.0, 0.4, 0.0),
	"from_coast": Vector3(-10.0, 0.4, 0.0),
}

func _ready() -> void:
	Music.play_area("north")
	_build_world()
	_wire_hud()
	if _hint:
		_hint.text = "WASD / stick · Jump · Action at doors"
	if _objective:
		_objective.text = "Druid Glade / North Holy — stone circle, Goblet Well, Druid fire"
	_place_player()
	LomnasBanner.attach(self, "Lomnas: Druid Glade — northern stones keep an older fire. Doors to Yard, Crossroads, and Coast.")
	_show_toast("Druid Glade / North Holy", 2.0)

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and _toast:
			_toast.visible = false

func _wire_hud() -> void:
	if _action_btn:
		_action_btn.pressed.connect(_on_action)
		_action_btn.visible = false
	if _jump_btn:
		_jump_btn.pressed.connect(func () -> void:
			if _player and _player.has_method("try_jump"):
				_player.try_jump())

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
			_go("res://scenes/druid_yard.tscn", "from_north")
		"to_road":
			_go("res://scenes/travel_road.tscn", "from_north")
		"to_coast":
			_go("res://scenes/coast.tscn", "from_north")

func _go(path: String, spawn: String) -> void:
	if _leaving:
		return
	_leaving = true
	GameState.go_to(path, spawn, "north_holy")

func _build_world() -> void:
	var world: Node3D = $World
	for c in world.get_children():
		c.queue_free()

	# Look-pass tiles when present; else flat greybox colours (automatic upgrade on drop-in).
	var has_lp_grass := LookPassMats.has_file("grass_tile_seamless.jpg")
	var has_lp_wall := LookPassMats.has_file("wall_tile_seamless.jpg")
	var ground_col := Color(0.40, 0.50, 0.46)
	var grass_m: StandardMaterial3D = LookPassMats.grass()
	if grass_m == null:
		grass_m = WalkAreaKit.mat(ground_col)
	var pad_m: StandardMaterial3D = LookPassMats.path_stone()
	if pad_m == null:
		pad_m = WalkAreaKit.mat(Color(0.55, 0.58, 0.62))
	else:
		# Circle pad is smaller than yard path lane — denser UV so X still reads.
		pad_m.uv1_scale = Vector3(2.8, 2.8, 1.0)
	var stone_m: StandardMaterial3D = LookPassMats.wall()
	if stone_m == null:
		stone_m = WalkAreaKit.mat(Color(0.62, 0.64, 0.68))

	WalkAreaKit.box(world, Vector3(48, 0.4, 48), Vector3(0, -0.2, 0), grass_m, "Ground")
	WalkAreaKit.box(world, Vector3(10, 0.12, 10), Vector3(0, 0.05, 0), pad_m, "CirclePad")

	for i in range(8):
		var ang := float(i) * TAU / 8.0
		var p := Vector3(sin(ang) * 6.5, 1.1, cos(ang) * 6.5)
		var st := WalkAreaKit.box(world, Vector3(0.7, 2.2, 0.45), p, stone_m, "Standing%d" % i)
		st.rotation.y = ang

	var well := Node3D.new()
	well.name = "GobletWell"
	world.add_child(well)
	var rim_m: StandardMaterial3D = stone_m
	if not has_lp_wall:
		rim_m = WalkAreaKit.mat(Color(0.5, 0.52, 0.58))
	WalkAreaKit.cyl(well, 1.4, 0.9, Vector3(0, 0.45, 0), rim_m, "Rim")
	WalkAreaKit.cyl(well, 1.05, 0.15, Vector3(0, 0.85, 0), WalkAreaKit.mat(Color(0.35, 0.55, 0.75), 0.2, Color(0.4, 0.6, 0.9), 0.6), "Water", 16, false, false)
	WalkAreaKit.label3d(well, "Goblet Well", Vector3(0, 2.4, 0), Color(0.75, 0.9, 1.0), 40)

	var fire := Node3D.new()
	fire.name = "DruidFire"
	fire.position = Vector3(4.5, 0, -3.5)
	world.add_child(fire)
	WalkAreaKit.cyl(fire, 1.1, 0.35, Vector3(0, 0.15, 0), WalkAreaKit.mat(Color(0.35, 0.28, 0.22)), "Ring")
	WalkAreaKit.cyl(fire, 0.35, 1.2, Vector3(0, 0.9, 0), WalkAreaKit.mat(Color(1.0, 0.45, 0.12), 0.4, Color(1.0, 0.5, 0.1), 3.5), "Flame", 10, true, false)
	var omni := OmniLight3D.new()
	omni.position = Vector3(0, 1.4, 0)
	omni.light_color = Color(1.0, 0.55, 0.2)
	omni.light_energy = 2.8
	omni.omni_range = 10.0
	fire.add_child(omni)
	WalkAreaKit.label3d(fire, "Druid fire", Vector3(0, 2.6, 0), Color(1.0, 0.8, 0.5), 36)

	var jump_m: StandardMaterial3D = stone_m
	if not has_lp_wall:
		jump_m = WalkAreaKit.mat(Color(0.48, 0.55, 0.6))
	WalkAreaKit.box(world, Vector3(2.2, 1.0, 2.2), Vector3(-5.0, 0.5, 4.0), jump_m, "JumpBlock")

	# Soft rounded rises — grass look_pass when present
	var mound_w := grass_m.duplicate() as StandardMaterial3D
	if has_lp_grass:
		mound_w.albedo_color = Color(0.85, 0.92, 0.78)
	else:
		mound_w.albedo_color = Color(0.38, 0.48, 0.42)
	var mound_e := grass_m.duplicate() as StandardMaterial3D
	if has_lp_grass:
		mound_e.albedo_color = Color(0.82, 0.90, 0.74)
	else:
		mound_e.albedo_color = Color(0.36, 0.46, 0.40)
	WalkAreaKit.cyl(world, 4.5, 0.7, Vector3(-8.0, 0.05, -6.0), mound_w, "MoundW", 16, false)
	WalkAreaKit.cyl(world, 3.8, 0.55, Vector3(7.5, 0.02, 5.0), mound_e, "MoundE", 16, false)

	var stone: StandardMaterial3D = stone_m
	if not has_lp_wall:
		stone = WalkAreaKit.mat(Color(0.55, 0.57, 0.6))
	WalkAreaKit.door_frame(world, Vector3(0, 0, 22), "To Yard", stone)
	WalkAreaKit.door_area(world, "DoorYard", Vector3(0, 1.0, 22), 2.4, _on_yard_enter, _on_yard_exit)
	WalkAreaKit.door_frame(world, Vector3(22, 0, 0), "To Crossroads", stone, -PI * 0.5)
	WalkAreaKit.door_area(world, "DoorRoad", Vector3(22, 1.0, 0), 2.4, _on_road_enter, _on_road_exit)
	# West — Coast (pairs with Coast LEFT/west Glade door)
	var coast_stone: StandardMaterial3D
	if has_lp_wall:
		coast_stone = stone_m.duplicate() as StandardMaterial3D
		coast_stone.albedo_color = Color(0.88, 0.82, 0.72)
	else:
		coast_stone = WalkAreaKit.mat(Color(0.55, 0.48, 0.38))
	WalkAreaKit.door_frame(world, Vector3(-22, 0, 0), "To Coast", coast_stone, PI * 0.5)
	WalkAreaKit.door_area(world, "DoorCoast", Vector3(-22, 1.0, 0), 2.4, _on_coast_enter, _on_coast_exit)

	# Glade backdrop plate when look_pass file exists (no-op otherwise)
	LookPassMats.attach_backdrop_plate(world, "glade_backdrop.jpg", Vector3(0, 14.0, -42), Vector2(88, 48), "GladeBackdrop")

	WalkAreaKit.sun_env(world, Color(0.45, 0.55, 0.68), Color(0.5, 0.58, 0.7), 1.05)
	WalkAreaKit.label3d(world, "DRUID GLADE", Vector3(0, 5.5, -8), Color(0.8, 0.9, 1.0), 52)
	WalkAreaKit.label3d(world, "North Holy", Vector3(0, 4.6, -8), Color(0.7, 0.82, 0.95), 36)

func _on_yard_enter(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_set_near("to_yard", "Enter Yard")

func _on_yard_exit(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_clear_near("to_yard")

func _on_road_enter(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_set_near("to_road", "Enter Crossroads")

func _on_road_exit(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_clear_near("to_road")

func _on_coast_enter(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_set_near("to_coast", "Enter Coast")

func _on_coast_exit(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_clear_near("to_coast")


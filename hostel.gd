extends Node3D
## Hostel — exterior pad + interior hall (one scene, door between). Doors from Coast/Road.

@onready var _player: CharacterBody3D = $Player
@onready var _toast: Label = $UI/Toast
@onready var _hint: Label = $UI/HintLabel
@onready var _objective: Label = $UI/ObjectiveLabel
@onready var _action_btn: Button = $UI/ActionButton
@onready var _jump_btn: Button = $UI/JumpButton

var _near: String = ""
var _leaving: bool = false
var _toast_t: float = 0.0
var _in_hall: bool = false
var _room_cam: Camera3D
var _cam_anchor: Vector3 = Vector3(8.0, 2.7, 13.5)  ## mild cam under ceiling
var _cam_look: Vector3 = Vector3(8.0, 1.2, 8.0)
var _cam_t: float = 0.0

const SPAWNS := {
	"default": Vector3(0.0, 0.4, 8.0),
	"from_coast": Vector3(0.0, 0.4, 10.0),
	"from_road": Vector3(-8.0, 0.4, 0.0),
	"from_yard": Vector3(-8.0, 0.4, 0.0),
	"hostel_hall": Vector3(8.0, 0.4, 10.0),
	"hostel_ext": Vector3(0.0, 0.4, 2.0),
}

func _ready() -> void:
	Music.play_area("hostel")
	_room_cam = null
	_build_world()
	_wire_hud()
	if _hint:
		_hint.text = "WASD / stick · Jump · Action at doors (hall uses mild cam)"
	if _objective:
		_objective.text = "Hostel — exterior pad + interior hall"
	_place_player()
	LomnasBanner.attach(self, "Lomnas: Timber and peat-smoke. Rest if you must — the coast and road wait outside.")
	_show_toast("Hostel grounds", 2.0)

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0 and _toast:
			_toast.visible = false
	if _in_hall and _room_cam and is_instance_valid(_room_cam):
		_cam_t += delta
		var ox := sin(_cam_t * 0.2) * 0.25
		_room_cam.global_position = _cam_anchor + Vector3(ox, 0.05 * sin(_cam_t * 0.15), 0)
		_room_cam.look_at(_cam_look, Vector3.UP)

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
	var key := GameState.take_spawn_point("from_coast")
	if not SPAWNS.has(key):
		key = "default"
	_player.global_position = SPAWNS[key]
	if key == "hostel_hall":
		_enter_hall_cam(false)
	else:
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
		"to_coast":
			_go("res://scenes/coast.tscn", "from_hostel")
		"to_road":
			_go("res://scenes/travel_road.tscn", "from_hostel")
		"to_hall":
			_warp_hall()
		"to_ext":
			_warp_ext()

func _go(path: String, spawn: String) -> void:
	if _leaving:
		return
	_leaving = true
	GameState.go_to(path, spawn, "hostel")

func _warp_hall() -> void:
	if _player:
		_player.global_position = SPAWNS["hostel_hall"]
	_enter_hall_cam(true)
	_show_toast("Hostel hall", 1.5)
	_clear_near("to_hall")

func _warp_ext() -> void:
	_leave_hall_cam()
	if _player:
		_player.global_position = SPAWNS["hostel_ext"]
	_show_toast("Hostel exterior", 1.5)
	_clear_near("to_ext")

func _enter_hall_cam(animate_toast: bool = true) -> void:
	_in_hall = true
	if _player and _player.has_method("configure_interior"):
		_player.configure_interior(true)
	if _room_cam == null or not is_instance_valid(_room_cam):
		_room_cam = Camera3D.new()
		_room_cam.name = "InteriorCam"
		_room_cam.fov = 55.0
		_room_cam.near = 0.12
		add_child(_room_cam)
	_room_cam.current = true
	_room_cam.global_position = _cam_anchor
	_room_cam.look_at(_cam_look, Vector3.UP)
	if _objective:
		_objective.text = "Hostel hall — Action to leave to exterior"
	if animate_toast:
		pass

func _leave_hall_cam() -> void:
	_in_hall = false
	if _room_cam and is_instance_valid(_room_cam):
		_room_cam.current = false
	if _player and _player.has_method("configure_interior"):
		_player.configure_interior(false)
	if _objective:
		_objective.text = "Hostel — exterior pad + interior hall"

func _build_world() -> void:
	var world: Node3D = $World
	for c in world.get_children():
		c.queue_free()

	var wood := WalkAreaKit.mat(Color(0.28, 0.18, 0.12))
	var dark := WalkAreaKit.mat(Color(0.22, 0.14, 0.1))
	# Exterior pad
	WalkAreaKit.box(world, Vector3(28, 0.4, 24), Vector3(0, -0.2, 2), WalkAreaKit.mat(Color(0.32, 0.28, 0.22)), "ExtGround")
	WalkAreaKit.box(world, Vector3(8, 0.2, 6), Vector3(0, 0.1, 2), wood, "Porch")
	# Simple hostel facade
	WalkAreaKit.box(world, Vector3(10, 4.0, 1.0), Vector3(0, 2.0, -2), wood, "Facade")
	WalkAreaKit.box(world, Vector3(2.2, 2.8, 0.2), Vector3(0, 1.4, -1.4), dark, "DoorVisual", false)
	WalkAreaKit.label3d(world, "HOSTEL", Vector3(0, 4.6, -2), Color(0.9, 0.8, 0.6), 48)

	# Interior hall (offset +X)
	WalkAreaKit.box(world, Vector3(14, 0.4, 16), Vector3(8, -0.2, 8), dark, "HallFloor")
	WalkAreaKit.box(world, Vector3(0.4, 3.5, 16), Vector3(1.2, 1.7, 8), wood, "HallWallW")
	WalkAreaKit.box(world, Vector3(0.4, 3.5, 16), Vector3(14.8, 1.7, 8), wood, "HallWallE")
	WalkAreaKit.box(world, Vector3(14, 3.5, 0.4), Vector3(8, 1.7, 0.2), wood, "HallWallS")
	WalkAreaKit.box(world, Vector3(14, 3.5, 0.4), Vector3(8, 1.7, 15.8), wood, "HallWallN")
	WalkAreaKit.box(world, Vector3(13, 0.3, 15), Vector3(8, 3.4, 8), wood, "HallCeiling", false)
	WalkAreaKit.box(world, Vector3(2.5, 0.8, 2.5), Vector3(8, 0.4, 8), WalkAreaKit.mat(Color(0.35, 0.25, 0.18)), "HallTable")
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(8, 2.8, 8)
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 2.2
	lamp.omni_range = 12.0
	world.add_child(lamp)
	WalkAreaKit.label3d(world, "Hall", Vector3(8, 3.0, 8), Color(0.95, 0.85, 0.7), 40)

	var stone := WalkAreaKit.mat(Color(0.45, 0.4, 0.35))
	WalkAreaKit.door_frame(world, Vector3(0, 0, 13), "To Coast", stone)
	WalkAreaKit.door_area(world, "DoorCoast", Vector3(0, 1.0, 13), 2.4,
		func(b: Node) -> void: _enter("to_coast", "Enter Coast", b),
		func(b: Node) -> void: _exit("to_coast", b))
	WalkAreaKit.door_frame(world, Vector3(-13, 0, 0), "To Crossroads", stone, PI * 0.5)
	WalkAreaKit.door_area(world, "DoorRoad", Vector3(-13, 1.0, 0), 2.4,
		func(b: Node) -> void: _enter("to_road", "Enter Crossroads", b),
		func(b: Node) -> void: _exit("to_road", b))
	# Ext <-> Hall
	WalkAreaKit.door_frame(world, Vector3(0, 0, -1.5), "Enter hall", stone)
	WalkAreaKit.door_area(world, "DoorHall", Vector3(0, 1.0, -1.5), 2.2,
		func(b: Node) -> void: _enter("to_hall", "Enter hall", b),
		func(b: Node) -> void: _exit("to_hall", b))
	WalkAreaKit.door_frame(world, Vector3(8, 0, 0.5), "Leave hall", stone)
	WalkAreaKit.door_area(world, "DoorExt", Vector3(8, 1.0, 0.5), 2.2,
		func(b: Node) -> void: _enter("to_ext", "Leave hall", b),
		func(b: Node) -> void: _exit("to_ext", b))

	WalkAreaKit.sun_env(world, Color(0.35, 0.32, 0.3), Color(0.45, 0.38, 0.32), 0.95)

func _enter(kind: String, label: String, body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_set_near(kind, label)

func _exit(kind: String, body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_clear_near(kind)

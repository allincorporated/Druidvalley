extends Node3D
## Coast greybox — shore + cliff. Doors: Crossroads (N), Druid Glade LEFT/west. Hostel via Yard or Crossroads.

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
	"default": Vector3(0.0, 0.4, 8.0),
	"from_road": Vector3(0.0, 0.4, 10.0),
	"from_north": Vector3(-10.0, 0.4, 0.0),
	"from_yard": Vector3(0.0, 0.4, 10.0),
	"from_hostel": Vector3(0.0, 0.4, -10.0),  # Hostel→Coast still lands on shore path
}

func _ready() -> void:
	Music.play_area("coast")
	_build_world()
	_wire_hud()
	if _hint:
		_hint.text = "WASD / stick · Jump · Action at doors"
	if _objective:
		_objective.text = "Coast — LEFT → Druid Glade · North → Crossroads"
	_place_player()
	LomnasBanner.attach(self, "Lomnas: Salt wind and cliff-edge. Left opens to the Druid Glade; the road climbs inland. Hostel is inland via Crossroads or Yard.")
	_show_toast("Coast", 2.0)

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
	var key := GameState.take_spawn_point("from_road")
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
		"to_road":
			_go("res://scenes/travel_road.tscn", "from_coast")
		"to_north":
			_go("res://scenes/north_holy.tscn", "from_coast")

func _go(path: String, spawn: String) -> void:
	if _leaving:
		return
	_leaving = true
	GameState.go_to(path, spawn, "coast")

func _build_world() -> void:
	var world: Node3D = $World
	for c in world.get_children():
		c.queue_free()

	WalkAreaKit.box(world, Vector3(40, 0.4, 36), Vector3(0, -0.2, 0), WalkAreaKit.mat(Color(0.78, 0.68, 0.48)), "Sand")
	# Soft sand mounds (light rounded touch)
	WalkAreaKit.cyl(world, 3.2, 0.55, Vector3(-7.0, 0.05, 4.0), WalkAreaKit.mat(Color(0.74, 0.64, 0.46)), "SandMoundL", 14, false)
	WalkAreaKit.cyl(world, 2.8, 0.45, Vector3(6.5, 0.02, -3.0), WalkAreaKit.mat(Color(0.76, 0.66, 0.47)), "SandMoundR", 14, false)
	WalkAreaKit.box(world, Vector3(40, 0.25, 10), Vector3(0, -0.35, 14), WalkAreaKit.mat(Color(0.25, 0.45, 0.65), 0.15, Color(0.3, 0.5, 0.8), 0.25), "Water", false)
	WalkAreaKit.box(world, Vector3(18, 4.0, 6), Vector3(-12, 1.8, -6), WalkAreaKit.mat(Color(0.55, 0.5, 0.45)), "Cliff")
	WalkAreaKit.box(world, Vector3(4, 1.0, 4), Vector3(-8, 0.5, 2), WalkAreaKit.mat(Color(0.6, 0.55, 0.48)), "RockStep")
	WalkAreaKit.box(world, Vector3(3, 1.5, 3), Vector3(-6, 0.75, 0), WalkAreaKit.mat(Color(0.58, 0.52, 0.46)), "RockJump")
	WalkAreaKit.box(world, Vector3(3.2, 0.12, 28), Vector3(0, 0.06, -2), WalkAreaKit.mat(Color(0.62, 0.55, 0.42)), "Path")

	var stone := WalkAreaKit.mat(Color(0.5, 0.48, 0.44))
	# North — Crossroads
	WalkAreaKit.door_frame(world, Vector3(0, 0, 16), "To Crossroads", stone)
	WalkAreaKit.door_area(world, "DoorRoad", Vector3(0, 1.0, 16), 2.4, _on_road_enter, _on_road_exit)
	# LEFT / west — Druid Glade (NOT Hostel). Hostel stays reachable via Yard SE + Crossroads east.
	var glade_mat := WalkAreaKit.mat(Color(0.42, 0.52, 0.58))
	WalkAreaKit.door_frame(world, Vector3(-16, 0, 0), "Druid Glade", glade_mat, PI * 0.5)
	WalkAreaKit.door_area(world, "DoorNorth", Vector3(-16, 1.0, 0), 2.4, _on_north_enter, _on_north_exit)

	WalkAreaKit.sun_env(world, Color(0.55, 0.7, 0.85), Color(0.7, 0.65, 0.55), 1.2)
	WalkAreaKit.label3d(world, "COAST", Vector3(0, 4.5, 0), Color(0.95, 0.9, 0.7), 56)
	WalkAreaKit.label3d(world, "← Glade", Vector3(-12, 3.2, 0), Color(0.75, 0.88, 1.0), 36)

func _on_road_enter(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_set_near("to_road", "Enter Crossroads")

func _on_road_exit(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_clear_near("to_road")

func _on_north_enter(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_set_near("to_north", "Enter Glade")

func _on_north_exit(body: Node) -> void:
	if WalkAreaKit.is_player(body):
		_clear_near("to_north")

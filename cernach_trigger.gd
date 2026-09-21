extends Node3D
## Drop under yard World (or any Node3D). Builds a labelled door + Area3D.
## Default: walk in to enter Cernach's Corner (auto — works without yard Action HUD).
## For Action-button "Corner him" wiring, see CERNSACH_HOOK.txt instead.

@export var door_pos: Vector3 = Vector3(9.5, 0, -8.0)
@export var door_yaw: float = -0.6
@export var radius: float = 2.2
@export var auto_enter: bool = true

const SCENE_PATH := "res://scenes/cernachs_corner.tscn"

var _leaving: bool = false
var _player_in: bool = false

func _ready() -> void:
	global_position = door_pos
	rotation.y = door_yaw
	_build()

func _build() -> void:
	var stone := WalkAreaKit.mat(Color(0.42, 0.38, 0.34), 0.88)
	WalkAreaKit.door_frame(self, Vector3.ZERO, "Cernach's Corner", stone, 0.0)
	WalkAreaKit.door_area(self, "CernachZone", Vector3(0, 1.0, 0), radius, _on_enter, _on_exit)

func _on_enter(body: Node) -> void:
	if not WalkAreaKit.is_player(body) or _leaving:
		return
	_player_in = true
	if auto_enter:
		_go()

func _on_exit(body: Node) -> void:
	if not WalkAreaKit.is_player(body):
		return
	_player_in = false

func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not _player_in or auto_enter:
		return
	if event.is_action_pressed("ui_accept"):
		_go()

func _go() -> void:
	if _leaving:
		return
	_leaving = true
	if GameState and GameState.has_method("go_to"):
		GameState.go_to(SCENE_PATH, "from_yard", "yard")
	else:
		get_tree().change_scene_to_file(SCENE_PATH)

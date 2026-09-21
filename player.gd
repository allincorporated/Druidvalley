extends CharacterBody3D
## Third-person walker: WASD / virtual joystick + spring-arm OTS follow.
## Visual: single primary Sprite3D (not a flipping card) with continuous yaw
## toward movement (lerp_angle), soft L/R swap when sideways, walk bob.
## Combat v0 (crossroads): swing 1 / jump+swing 2, hold-block + tap-parry, whiff tax.

@export var speed: float = 5.5
@export var mouse_sens: float = 0.0035
@export var jump_velocity: float = 7.5
@export var turn_speed: float = 10.0
@export var bob_amp: float = 0.045
@export var bob_hz: float = 7.5
@export var max_hp: int = 10

var _yaw: float = 0.0
var _pitch: float = -0.32

var _swinging: bool = false
var _swing_heavy: bool = false
var _swing_t: float = 0.0
var _swing_dur: float = 0.28
var _swing_damage: int = 1
var _swing_hit_done: bool = false
var _stick_base_rot: Vector3 = Vector3(0.15, 0.0, -0.35)

@onready var _pivot: Node3D = $CameraPivot
@onready var _spring: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _mesh: Node3D = $Mesh

var _stick: Node3D
var _hit_area: Area3D
var _hit_shape: CollisionShape3D
var _sprite: Sprite3D
var _tex_front: Texture2D
var _tex_back: Texture2D
var _tex_left: Texture2D
var _tex_right: Texture2D
var _facing_side: String = ""  # "" | "left" | "right" soft-swap only
var _figure_yaw: float = 0.0
var _bob_t: float = 0.0
var _sprite_base_y: float = 1.55

## Combat pose flicks (Hit = stick swing crop; Miss = peasant front)
var _tex_stick_hit: Texture2D
var _tex_stick_heavy: Texture2D
var _tex_miss_peasant: Texture2D
var _pose_flick_t: float = 0.0
var _pose_restore: Texture2D
var _pose_restore_side: String = ""
var _stick_mesh: MeshInstance3D
var _stick_trail: MeshInstance3D
var _trail_mat: StandardMaterial3D

signal stick_hit(heavy: bool)
signal stick_miss
signal swing_result(hit: bool, heavy: bool)
signal jumped
signal hp_changed(hp: int, max_hp: int)
signal blocked(parry: bool)
signal parry_cooldown_changed(active: bool)
signal took_damage(amount: int, remaining: int)
signal died

var _interior: bool = false
var _speed_default: float = 5.5

## Combat state
var hp: int = 10
var _whiff_immune: bool = false
var _whiff_t: float = 0.0
const WHIFF_TIMEOUT := 2.2

## Block / parry — same button: tap (<HOLD_THRESHOLD) = parry window; hold = shield
var _blocking: bool = false          # sustained hold shield
var _block_held: bool = false        # raw input down
var _block_press_t: float = 0.0      # time since press started
var _parry_window: float = 0.0       # remaining parry active time
var _parry_armed: bool = false       # waiting to see tap vs hold on release/threshold
var _parry_cooldown_t: float = 0.0
const HOLD_THRESHOLD := 0.18
const PARRY_DURATION := 0.32
const PARRY_COOLDOWN := 0.82
var _block_flash: MeshInstance3D
var _i_frames: float = 0.0

func _ready() -> void:
	add_to_group("player")
	_speed_default = speed
	hp = max_hp
	# A fresh player instance must never inherit a prior parry lockout.
	_parry_cooldown_t = 0.0
	_parry_window = 0.0
	if _camera:
		_camera.make_current()
	if _spring:
		_spring.spring_length = 7.25
		_spring.collision_mask = 1
	_ensure_king_sprite()
	_build_stick()
	_build_block_flash()
	hp_changed.emit(hp, max_hp)

func configure_interior(enabled: bool = true) -> void:
	## Interior: follow spring OFF — room InteriorCam takes over (not OTS follow).
	## Yard / leave tree: restore spring-arm OTS follow as current cam.
	_interior = enabled
	if enabled:
		speed = minf(_speed_default, 3.8)
		if _camera:
			_camera.current = false
		if _spring:
			_spring.spring_length = 3.2
			# Hard off: no spring collision pull / follow while InteriorCam is current
			_spring.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		speed = _speed_default
		if _spring:
			_spring.process_mode = Node.PROCESS_MODE_INHERIT
			_spring.spring_length = 7.25
			_spring.margin = 0.2
		if _camera:
			_camera.fov = 58.0
			_camera.make_current()

func _ensure_king_sprite() -> void:
	_tex_front = load("res://assets/art/character/dir_front.png") as Texture2D
	_tex_back = load("res://assets/art/character/dir_back.png") as Texture2D
	_tex_left = load("res://assets/art/character/dir_left.png") as Texture2D
	_tex_right = load("res://assets/art/character/dir_right.png") as Texture2D
	_tex_stick_hit = load("res://assets/art/character/stick_pose_swing.png") as Texture2D
	_tex_stick_heavy = load("res://assets/art/character/stick_pose_overhead.png") as Texture2D
	_tex_miss_peasant = load("res://assets/art/character/peasant_front.png") as Texture2D
	var fallback := load("res://assets/art/character/general_player.png") as Texture2D

	_sprite = _mesh.get_node_or_null("GeneralSprite") as Sprite3D
	if _sprite == null:
		_sprite = Sprite3D.new()
		_sprite.name = "GeneralSprite"
		_sprite.position = Vector3(0, 1.55, 0)
		_mesh.add_child(_sprite)
	_sprite_base_y = 1.55
	_sprite.position = Vector3(0, _sprite_base_y, 0)
	_sprite.pixel_size = 0.0040
	# Continuous yaw presence — not a camera billboard card
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.shaded = false
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.12
	_sprite.double_sided = true
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Primary pose: front (best readable presence)
	if _tex_front:
		_sprite.texture = _tex_front
	elif fallback:
		_sprite.texture = fallback
	_facing_side = ""
	_figure_yaw = 0.0
	_mesh.rotation.y = _figure_yaw
	# Hide any leftover capsule/head meshes
	for child in _mesh.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false

func _apply_primary_or_side(side: String) -> void:
	## Soft L/R only when mostly sideways; otherwise keep primary front.
	if _sprite == null:
		return
	if _pose_flick_t > 0.0:
		return  # combat pose flick owns the texture briefly
	if side == _facing_side:
		return
	_facing_side = side
	match side:
		"left":
			if _tex_left:
				_sprite.texture = _tex_left
		"right":
			if _tex_right:
				_sprite.texture = _tex_right
		_:
			if _tex_front:
				_sprite.texture = _tex_front

func _update_figure_presence(move: Vector3, delta: float) -> void:
	## Continuous yaw toward movement + optional soft side swap + walk bob.
	var moving := move.length_squared() > 0.02
	if moving:
		var target_yaw := atan2(move.x, move.z)
		_figure_yaw = lerp_angle(_figure_yaw, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
		if _mesh:
			_mesh.rotation.y = _figure_yaw
		# Soft-swap left/right only when mostly camera-sideways (less pop)
		var cam_fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var cam_right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		var mx := move.dot(cam_right)
		var mz := move.dot(cam_fwd)
		if absf(mx) > absf(mz) * 1.35 and absf(mx) > 0.35:
			_apply_primary_or_side("right" if mx > 0.0 else "left")
		else:
			_apply_primary_or_side("")
		_bob_t += delta * bob_hz * (0.65 + move.length())
		if _sprite:
			_sprite.position.y = _sprite_base_y + sin(_bob_t) * bob_amp
	else:
		# Ease bob back to rest; keep last yaw / texture
		if _sprite:
			_sprite.position.y = lerpf(_sprite.position.y, _sprite_base_y, clampf(8.0 * delta, 0.0, 1.0))

func _build_stick() -> void:
	## Visible 3D staff + arc trail + hitbox (readable swing).
	_stick = Node3D.new()
	_stick.name = "Stick"
	_stick.position = Vector3(0.38, 1.28, 0.08)
	_stick.rotation = _stick_base_rot
	_mesh.add_child(_stick)

	_stick_mesh = MeshInstance3D.new()
	_stick_mesh.name = "StickMesh"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.055
	cyl.height = 1.55
	_stick_mesh.mesh = cyl
	var wood := StandardMaterial3D.new()
	wood.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wood.albedo_color = Color(0.42, 0.26, 0.12)
	wood.emission_enabled = true
	wood.emission = Color(0.55, 0.32, 0.12)
	wood.emission_energy_multiplier = 0.55
	_stick_mesh.material_override = wood
	_stick_mesh.position = Vector3(0.0, 0.55, 0.35)
	_stick_mesh.rotation_degrees = Vector3(70, 0, -18)
	_stick.add_child(_stick_mesh)

	# Arc trail wedge — bright during swing, hidden at rest
	_stick_trail = MeshInstance3D.new()
	_stick_trail.name = "SwingTrail"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.35, 0.55)
	_stick_trail.mesh = quad
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.albedo_color = Color(1.0, 0.85, 0.35, 0.0)
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.emission_enabled = true
	_trail_mat.emission = Color(1.0, 0.75, 0.2)
	_trail_mat.emission_energy_multiplier = 2.2
	_stick_trail.material_override = _trail_mat
	_stick_trail.position = Vector3(0.15, 0.7, 0.95)
	_stick_trail.rotation_degrees = Vector3(-15, 0, 0)
	_stick_trail.visible = false
	_stick.add_child(_stick_trail)

	_hit_area = Area3D.new()
	_hit_area.name = "StickHit"
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 4  # hittables
	_hit_area.monitoring = false
	_hit_area.monitorable = false
	_hit_area.position = Vector3(0.05, 0.65, 0.95)
	_stick.add_child(_hit_area)

	_hit_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.05, 0.9, 1.35)
	_hit_shape.shape = box
	_hit_area.add_child(_hit_shape)

	_hit_area.area_entered.connect(_on_stick_area_entered)

func _build_block_flash() -> void:
	_block_flash = MeshInstance3D.new()
	_block_flash.name = "BlockFlash"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.4)
	_block_flash.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.75, 1.0, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_block_flash.material_override = mat
	_block_flash.position = Vector3(0.0, 1.0, 0.55)
	_block_flash.visible = false
	_mesh.add_child(_block_flash)

func _on_stick_area_entered(area: Area3D) -> void:
	_try_stick_hit(area)

func _try_stick_hit(area: Area3D) -> void:
	if not _swinging or _swing_hit_done:
		return
	if area == null or not area.is_in_group("hittable"):
		return
	var dmg := _swing_damage
	# Whiff tax: next successful connect deals 0 and clears
	if _whiff_immune:
		dmg = 0
		_clear_whiff_immune()
	var target: Node = null
	if area.has_meta("foe_root"):
		target = area.get_meta("foe_root") as Node
	if target == null:
		target = area.get_parent()
	if dmg > 0 and target != null and target.has_method("take_hit"):
		target.take_hit(dmg, self)
	elif dmg > 0 and area.has_method("take_hit"):
		area.take_hit(dmg, self)
	_swing_hit_done = true
	_flick_combat_pose(true, _swing_heavy)
	stick_hit.emit(_swing_heavy)
	if _hit_area:
		_hit_area.set_deferred("monitoring", false)

func _poll_stick_hits() -> void:
	## Godot does not emit area_entered for areas already overlapping when
	## monitoring flips true mid-swing — poll overlap once per swing.
	if _hit_area == null or not _swinging or _swing_hit_done:
		return
	if not _hit_area.monitoring:
		return
	for area in _hit_area.get_overlapping_areas():
		_try_stick_hit(area)
		if _swing_hit_done:
			break

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _interior:
			return  # room cam owns framing; stick still moves
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * mouse_sens
		_pitch = clampf(_pitch - mm.relative.y * mouse_sens, -1.0, 0.25)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				do_light_swing()
	elif event is InputEventKey and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_SPACE or ke.keycode == KEY_ENTER:
			if ke.pressed:
				try_jump()
		elif ke.keycode == KEY_F:
			if ke.pressed:
				do_light_swing()
		elif ke.keycode == KEY_G:
			if ke.pressed:
				do_heavy_swing()
		elif ke.keycode == KEY_Q or ke.keycode == KEY_SHIFT:
			# Block / parry — hold or tap
			if ke.pressed:
				begin_block_press()
			else:
				end_block_press()

func try_jump() -> void:
	if is_on_floor() and not _swinging and not _blocking:
		velocity.y = jump_velocity
		jumped.emit()

func do_light_swing() -> void:
	if _swinging or _blocking:
		return
	_start_swing(false, 0.28)

func do_heavy_swing() -> void:
	if _swinging or _blocking:
		return
	_start_swing(true, 0.55)

func can_start_swing() -> bool:
	return not _swinging and not _blocking

func _start_swing(heavy: bool, dur: float) -> void:
	if _blocking or _parry_window > 0.0:
		# Parry window is short; allow swing after it ends — block only during active hold
		if _blocking:
			return
	_swinging = true
	_swing_heavy = heavy
	_swing_t = 0.0
	_swing_dur = dur
	_swing_hit_done = false
	# Combat rules: grounded swing 1, jump+swing 2 (airborne)
	if not is_on_floor():
		_swing_damage = 2
	else:
		_swing_damage = 1 if not heavy else 2
	if _hit_area:
		_hit_area.monitoring = true
		_poll_stick_hits()

## --- Block / parry API (on-screen button + Q / Shift) ---

func begin_block_press() -> void:
	if hp <= 0:
		return
	if _block_held:
		return
	_block_held = true
	_block_press_t = 0.0
	# A press during cooldown can still become a hold-shield, but never a new parry.
	_parry_armed = _parry_cooldown_t <= 0.0
	# Do not start shield yet — wait for HOLD_THRESHOLD or release (tap = parry)

func end_block_press() -> void:
	if not _block_held:
		return
	_block_held = false
	if _parry_armed and _block_press_t < HOLD_THRESHOLD:
		# TAP → short parry window
		_parry_armed = false
		_start_parry()
	# If we already entered hold-shield, release it
	if _blocking:
		_stop_hold_block()

func set_block_held(held: bool) -> void:
	## For on-screen button press/release.
	if held:
		begin_block_press()
	else:
		end_block_press()

func _start_parry() -> void:
	if _swinging:
		return
	_parry_window = PARRY_DURATION
	_parry_cooldown_t = PARRY_COOLDOWN
	parry_cooldown_changed.emit(true)
	_show_block_fx(true)
	# Free to move/swing after window ends (not locked like hold)

func _start_hold_block() -> void:
	if _swinging:
		# Cancel swing attempt — cannot attack while blocking
		_swinging = false
		if _hit_area:
			_hit_area.monitoring = false
		if _stick:
			_stick.rotation = _stick_base_rot
	_blocking = true
	_parry_armed = false
	_show_block_fx(false)

func _stop_hold_block() -> void:
	_blocking = false
	_hide_block_fx()

func is_blocking() -> bool:
	return _blocking or _parry_window > 0.0

func is_airborne() -> bool:
	return not is_on_floor()

func take_damage(amount: int, from: Node = null) -> void:
	if hp <= 0 or amount <= 0:
		return
	if _i_frames > 0.0:
		return
	# Parry window: full negate + stagger foe
	if _parry_window > 0.0:
		_parry_window = 0.0
		_hide_block_fx()
		_i_frames = 0.25
		blocked.emit(true)
		if from != null and is_instance_valid(from) and from.has_method("stagger"):
			from.stagger(0.55)
		return
	# Hold shield: negate incoming (including mid-hit if held)
	if _blocking:
		_i_frames = 0.12
		blocked.emit(false)
		_pulse_block_fx()
		return
	hp = maxi(0, hp - amount)
	_i_frames = 0.45
	took_damage.emit(amount, hp)
	hp_changed.emit(hp, max_hp)
	# Whiff tax: damaged while jumping → next successful player hit wasted
	if not is_on_floor():
		_whiff_immune = true
		_whiff_t = WHIFF_TIMEOUT
	if hp <= 0:
		_clear_parry_cooldown()
		died.emit()

func _clear_parry_cooldown() -> void:
	if _parry_cooldown_t <= 0.0:
		return
	_parry_cooldown_t = 0.0
	parry_cooldown_changed.emit(false)

func _clear_whiff_immune() -> void:
	_whiff_immune = false
	_whiff_t = 0.0

func _show_block_fx(parry: bool) -> void:
	if _block_flash == null:
		return
	_block_flash.visible = true
	var mat := _block_flash.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.95, 0.9, 0.4, 0.55) if parry else Color(0.45, 0.7, 1.0, 0.4)

func _pulse_block_fx() -> void:
	_show_block_fx(false)
	var mat := _block_flash.material_override as StandardMaterial3D if _block_flash else null
	if mat:
		mat.albedo_color = Color(0.7, 0.9, 1.0, 0.7)

func _hide_block_fx() -> void:
	if _block_flash == null:
		return
	if _blocking or _parry_window > 0.0:
		return
	_block_flash.visible = false
	var mat := _block_flash.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.55, 0.75, 1.0, 0.0)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	if _i_frames > 0.0:
		_i_frames -= delta
	if _parry_cooldown_t > 0.0:
		_parry_cooldown_t -= delta
		if _parry_cooldown_t <= 0.0:
			_parry_cooldown_t = 0.0
			parry_cooldown_changed.emit(false)
	if _whiff_immune:
		_whiff_t -= delta
		if _whiff_t <= 0.0:
			_clear_whiff_immune()
	if _parry_window > 0.0:
		_parry_window -= delta
		if _parry_window <= 0.0:
			_parry_window = 0.0
			_hide_block_fx()

	# Tap vs hold detection
	if _block_held:
		_block_press_t += delta
		if _parry_armed and _block_press_t >= HOLD_THRESHOLD and not _blocking:
			_start_hold_block()

	if Input.is_action_just_pressed("ui_accept"):
		try_jump()

	var dir2 := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	## Direct key fallback (some editor builds swallow ui_* while focused on controls)
	if dir2.length() <= 0.01:
		dir2 = Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		)
	var joystick := get_tree().get_first_node_in_group("virtual_joystick")
	if joystick != null:
		var jdir: Variant = joystick.get("direction")
		if jdir is Vector2 and (jdir as Vector2).length() > 0.01:
			dir2 = jdir as Vector2

	if _pivot and not _interior:
		_pivot.rotation = Vector3(_pitch, _yaw, 0.0)

	var forward: Vector3
	var right: Vector3
	if _interior:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var basis := cam.global_transform.basis
			forward = -basis.z
			forward.y = 0.0
			if forward.length_squared() < 0.001:
				forward = Vector3(0, 0, -1)
			else:
				forward = forward.normalized()
			right = basis.x
			right.y = 0.0
			if right.length_squared() < 0.001:
				right = Vector3(1, 0, 0)
			else:
				right = right.normalized()
		else:
			forward = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
			right = Vector3(cos(_yaw), 0.0, -sin(_yaw))
	else:
		forward = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		right = Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var move := (right * dir2.x + forward * -dir2.y)
	if move.length_squared() > 1.0:
		move = move.normalized()

	# Slight slow while hold-blocking
	var spd := speed * (0.55 if _blocking else 1.0)
	velocity.x = move.x * spd
	velocity.z = move.z * spd
	move_and_slide()

	_update_figure_presence(move, delta)
	_update_swing(delta)

func _flick_combat_pose(hit: bool, heavy: bool = false) -> void:
	## Brief sprite swap synced to Hit (stick crop) / Miss (peasant front).
	if _sprite == null:
		return
	if _pose_flick_t <= 0.0:
		_pose_restore = _sprite.texture
		_pose_restore_side = _facing_side
	var tex: Texture2D = null
	if hit:
		tex = _tex_stick_heavy if heavy and _tex_stick_heavy else _tex_stick_hit
	else:
		tex = _tex_miss_peasant
	if tex == null:
		return
	_sprite.texture = tex
	_facing_side = "_flick"
	_pose_flick_t = 0.42 if hit else 0.38

func _restore_pose_if_needed() -> void:
	if _pose_flick_t > 0.0 or _sprite == null:
		return
	if _pose_restore != null:
		_sprite.texture = _pose_restore
	_facing_side = ""
	# Re-apply soft side from last restore hint
	if _pose_restore_side == "left" or _pose_restore_side == "right":
		_apply_primary_or_side(_pose_restore_side)
	else:
		_apply_primary_or_side("")
	_pose_restore = null

func _update_swing(delta: float) -> void:
	if _pose_flick_t > 0.0:
		_pose_flick_t -= delta
		if _pose_flick_t <= 0.0:
			_pose_flick_t = 0.0
			_restore_pose_if_needed()
	if not _swinging or _stick == null:
		return
	_swing_t += delta
	var t := clampf(_swing_t / _swing_dur, 0.0, 1.0)
	var arc: float
	# Big readable 3D arc — yaw + pitch sweep so the staff is obvious on camera
	if _swing_heavy:
		arc = sin(t * PI)
		_stick.rotation = _stick_base_rot + Vector3(
			-0.85 + arc * 1.55,
			-0.55 + arc * 2.4,
			-0.35 + arc * 1.1
		)
	else:
		arc = sin(t * PI)
		_stick.rotation = _stick_base_rot + Vector3(
			-0.45 + arc * 0.95,
			-0.35 + arc * 1.85,
			-0.2 + arc * 0.7
		)
	if _stick_trail and _trail_mat:
		_stick_trail.visible = true
		var a := sin(t * PI)
		_trail_mat.albedo_color = Color(1.0, 0.88, 0.35, 0.15 + a * 0.55)
		_trail_mat.emission_energy_multiplier = 1.4 + a * 3.2
		_stick_trail.scale = Vector3(0.7 + a * 0.9, 0.6 + a * 0.8, 1.0)
	if _stick_mesh:
		_stick_mesh.scale = Vector3(1.0, 1.0, 1.0) * (1.0 + sin(t * PI) * 0.08)
	if _hit_area:
		var want_mon := (t > 0.18 and t < 0.82) and not _swing_hit_done
		_hit_area.monitoring = want_mon
		if want_mon:
			_poll_stick_hits()
	if t >= 1.0:
		var missed := not _swing_hit_done
		_swinging = false
		_stick.rotation = _stick_base_rot
		if _stick_trail:
			_stick_trail.visible = false
		if _trail_mat:
			_trail_mat.albedo_color = Color(1.0, 0.85, 0.35, 0.0)
		if _stick_mesh:
			_stick_mesh.scale = Vector3.ONE
		if _hit_area:
			_hit_area.monitoring = false
		if missed:
			_flick_combat_pose(false, false)
			stick_miss.emit()
			swing_result.emit(false, _swing_heavy)
		else:
			swing_result.emit(true, _swing_heavy)

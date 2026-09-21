extends CharacterBody3D
## Greybox crossroads thug — walk toward player or idle; stick-hittable.
## Attack tells: wind-up telegraph → commit swing (QUICK jab vs HEAVY).
## Player Hold Block / tap parry during telegraph. Foes attack freely (no stagger cap).
## elite=true → stronger HP/damage/speed (2nd-floor bosslet).

@export var max_hp: int = 3
@export var move_speed: float = 2.4
@export var aggro_range: float = 14.0
@export var contact_damage: int = 1
@export var contact_cooldown: float = 0.85
@export var idle_wander: bool = true
@export var elite: bool = false

var hp: int = 3
var _hurt_cd: float = 0.0
var _contact_cd: float = 0.0
var _dead: bool = false
var _stagger_t: float = 0.0
var _wander_t: float = 0.0
var _wander_dir: Vector3 = Vector3.ZERO

## Attack telegraph state — foes may wind up freely (no global one-at-a-time lock).
## 0=idle, 1=windup (block window), 2=commit (damage frame), 3=recovery
var _atk_phase: int = 0
var _atk_t: float = 0.0
var _atk_windup: float = 0.0
var _atk_heavy: bool = false
var _atk_damage: int = 1
var _atk_target: Node = null
var _mesh_base_scale: Vector3 = Vector3.ONE
var _mesh_base_pos: Vector3 = Vector3.ZERO

const QUICK_WINDUP := 0.32
const HEAVY_WINDUP := 0.70
const QUICK_RECOVERY := 0.38
const HEAVY_RECOVERY := 0.62
const ATTACK_RANGE := 0.85
const COMMIT_RANGE := 1.15

var _mesh_root: Node3D
var _hurt: Area3D
var _touch: Area3D
var _hp_label: Label3D
var _mat_body: StandardMaterial3D
var _base_color: Color = Color(0.42, 0.28, 0.26)

signal died
signal hit_taken(remaining: int)

func _ready() -> void:
	add_to_group("foe")
	if elite:
		max_hp = maxi(max_hp, 6)
		move_speed = maxf(move_speed, 3.1)
		contact_damage = maxi(contact_damage, 2)
		aggro_range = maxf(aggro_range, 18.0)
		_base_color = Color(0.55, 0.18, 0.22)
		idle_wander = false
	hp = max_hp
	collision_layer = 0
	collision_mask = 1
	floor_snap_length = 0.2
	_build_visual()
	_mesh_base_scale = Vector3.ONE
	_mesh_base_pos = Vector3.ZERO
	_build_hurtbox()
	_build_touch()
	_refresh_hp_label()

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _hurt_cd > 0.0:
		_hurt_cd -= delta
	if _contact_cd > 0.0:
		_contact_cd -= delta
	if _stagger_t > 0.0:
		_stagger_t -= delta
		if _atk_phase != 0:
			_cancel_attack()
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 22.0 * delta
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	# Advance attack tell even while closing; block during windup.
	if _atk_phase != 0:
		_tick_attack(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 22.0 * delta
		move_and_slide()
		return

	var player := _find_player()
	var move := Vector3.ZERO
	if player != null:
		var to_p := player.global_position - global_position
		to_p.y = 0.0
		var dist := to_p.length()
		if dist < aggro_range and dist > ATTACK_RANGE:
			move = to_p.normalized()
			if _mesh_root:
				_mesh_root.rotation.y = atan2(move.x, move.z)
		elif dist <= ATTACK_RANGE:
			move = Vector3.ZERO
			if _mesh_root:
				_mesh_root.rotation.y = atan2(to_p.x, to_p.z)
			_start_attack(player)
		elif idle_wander:
			move = _idle_step(delta)
	elif idle_wander:
		move = _idle_step(delta)

	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed
	move_and_slide()

func take_hit(amount: int, _from: Node = null) -> void:
	if _dead or amount <= 0:
		return
	if _hurt_cd > 0.0:
		return
	_hurt_cd = 0.18
	hp = maxi(0, hp - amount)
	hit_taken.emit(hp)
	_flash_hurt()
	_refresh_hp_label()
	if hp <= 0:
		_die()

func stagger(duration: float = 0.5) -> void:
	if _dead:
		return
	_stagger_t = maxf(_stagger_t, duration)
	_cancel_attack()
	_flash_hurt()

func _die() -> void:
	_dead = true
	velocity = Vector3.ZERO
	if _hurt:
		_hurt.set_deferred("monitorable", false)
	if _touch:
		_touch.set_deferred("monitoring", false)
	died.emit()
	if _mesh_root:
		var tw := create_tween()
		tw.tween_property(_mesh_root, "scale", Vector3(1.1, 0.15, 1.1), 0.28)
		tw.tween_callback(queue_free)
	else:
		queue_free()

func _start_attack(player: Node) -> void:
	if _contact_cd > 0.0 or player == null or _atk_phase != 0:
		return
	_atk_target = player
	# QUICK jab (short tell, less dmg) vs HEAVY (long tell, more dmg). Elite prefers heavy.
	var heavy_chance := 0.55 if elite else 0.38
	_atk_heavy = randf() < heavy_chance
	if _atk_heavy:
		_atk_windup = HEAVY_WINDUP
		_atk_damage = contact_damage + (1 if elite else 1)
		_atk_damage = maxi(_atk_damage, contact_damage + 1)
	else:
		_atk_windup = QUICK_WINDUP
		_atk_damage = maxi(1, contact_damage)
	_atk_phase = 1
	_atk_t = 0.0
	_apply_windup_pose(0.0)


func _tick_attack(delta: float) -> void:
	_atk_t += delta
	if _atk_phase == 1:
		# Telegraph window — Hold Block / tap parry work via player.take_damage checks.
		var u := clampf(_atk_t / maxf(_atk_windup, 0.01), 0.0, 1.0)
		_apply_windup_pose(u)
		if _atk_t >= _atk_windup:
			_atk_phase = 2
			_atk_t = 0.0
			_apply_commit_pose()
			_deal_attack_damage()
	elif _atk_phase == 2:
		# Brief commit pose, then recovery.
		if _atk_t >= 0.10:
			_atk_phase = 3
			_atk_t = 0.0
	elif _atk_phase == 3:
		var rec := HEAVY_RECOVERY if _atk_heavy else QUICK_RECOVERY
		var u := clampf(_atk_t / maxf(rec, 0.01), 0.0, 1.0)
		_apply_recovery_pose(u)
		if _atk_t >= rec:
			_finish_attack()


func _deal_attack_damage() -> void:
	var player: Node = _atk_target
	if player == null or not is_instance_valid(player):
		player = _find_player()
	if player == null:
		return
	var to_p: Vector3 = (player as Node3D).global_position - global_position
	to_p.y = 0.0
	if to_p.length() > COMMIT_RANGE:
		return  # swung and missed — still readable commit flash
	if player.has_method("take_damage"):
		player.take_damage(_atk_damage, self)


func _finish_attack() -> void:
	_contact_cd = contact_cooldown * (0.55 if not _atk_heavy else 0.85)
	_cancel_attack()


func _cancel_attack() -> void:
	_atk_phase = 0
	_atk_t = 0.0
	_atk_target = null
	_atk_heavy = false
	_reset_pose()


func _apply_windup_pose(u: float) -> void:
	if _mesh_root == null:
		return
	# Lean back + slight grow; colour shifts warn (quick=amber, heavy=crimson).
	var lean := lerpf(0.0, -0.28 if _atk_heavy else -0.16, u)
	_mesh_root.rotation.x = lean
	var s := lerpf(1.0, 1.12 if _atk_heavy else 1.06, u)
	_mesh_root.scale = _mesh_base_scale * s
	if _mat_body:
		var warn := Color(0.95, 0.35, 0.22) if _atk_heavy else Color(0.95, 0.75, 0.25)
		_mat_body.albedo_color = _base_color.lerp(warn, 0.35 + 0.55 * u)


func _apply_commit_pose() -> void:
	if _mesh_root == null:
		return
	# Clear commit moment — snap lean forward + scale punch + colour flash (no toast).
	_mesh_root.rotation.x = 0.42 if _atk_heavy else 0.28
	_mesh_root.scale = _mesh_base_scale * (1.22 if _atk_heavy else 1.14)
	if _mat_body:
		_mat_body.albedo_color = Color(1.0, 0.95, 0.85) if not _atk_heavy else Color(1.0, 0.45, 0.35)


func _apply_recovery_pose(u: float) -> void:
	if _mesh_root == null:
		return
	_mesh_root.rotation.x = lerpf(0.42 if _atk_heavy else 0.28, 0.0, u)
	_mesh_root.scale = _mesh_base_scale.lerp(_mesh_base_scale * (1.22 if _atk_heavy else 1.14), 1.0 - u)
	if _mat_body:
		_mat_body.albedo_color = _base_color.lerp(
			Color(1.0, 0.95, 0.85) if not _atk_heavy else Color(1.0, 0.45, 0.35),
			1.0 - u
		)


func _reset_pose() -> void:
	if _mesh_root:
		_mesh_root.rotation.x = 0.0
		_mesh_root.scale = _mesh_base_scale
	if _mat_body:
		_mat_body.albedo_color = _base_color

func _idle_step(delta: float) -> Vector3:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(1.2, 2.8)
		if randf() < 0.35:
			_wander_dir = Vector3.ZERO
		else:
			var a := randf() * TAU
			_wander_dir = Vector3(sin(a), 0.0, cos(a))
	if _wander_dir.length_squared() > 0.01 and _mesh_root:
		_mesh_root.rotation.y = atan2(_wander_dir.x, _wander_dir.z)
	return _wander_dir

func _find_player() -> Node3D:
	var n := get_tree().get_first_node_in_group("player")
	return n as Node3D

func _build_visual() -> void:
	_mesh_root = Node3D.new()
	_mesh_root.name = "Mesh"
	add_child(_mesh_root)

	_mat_body = StandardMaterial3D.new()
	_mat_body.albedo_color = _base_color
	_mat_body.roughness = 0.92

	var body_r := 0.42 if elite else 0.38
	var body_h := 1.35 if elite else 1.15
	var body := CSGCylinder3D.new()
	body.name = "Body"
	body.radius = body_r
	body.height = body_h
	body.sides = 12
	body.position = Vector3(0, 0.55 + body_h * 0.5, 0)
	body.material = _mat_body
	body.use_collision = false
	_mesh_root.add_child(body)

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.72, 0.55, 0.45) if not elite else Color(0.85, 0.45, 0.35)
	var head := CSGSphere3D.new()
	head.name = "Head"
	head.radius = 0.32 if elite else 0.28
	head.position = Vector3(0, 0.55 + body_h + 0.22, 0)
	head.material = head_mat
	head.use_collision = false
	_mesh_root.add_child(head)

	if elite:
		var helm := CSGBox3D.new()
		helm.name = "Helm"
		helm.size = Vector3(0.55, 0.22, 0.55)
		helm.position = Vector3(0, head.position.y + 0.18, 0)
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.35, 0.35, 0.4)
		helm.material = hm
		helm.use_collision = false
		_mesh_root.add_child(helm)

	var club_mat := StandardMaterial3D.new()
	club_mat.albedo_color = Color(0.35, 0.25, 0.15) if not elite else Color(0.45, 0.42, 0.48)
	var club := CSGBox3D.new()
	club.name = "Club"
	club.size = Vector3(0.16 if elite else 0.14, 0.16 if elite else 0.14, 0.85 if elite else 0.7)
	club.position = Vector3(0.5, 1.05, 0.15)
	club.material = club_mat
	club.use_collision = false
	_mesh_root.add_child(club)

	_hp_label = Label3D.new()
	_hp_label.name = "HpLabel"
	_hp_label.font_size = 48 if not elite else 56
	_hp_label.pixel_size = 0.01
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.position = Vector3(0, head.position.y + 0.55, 0)
	_hp_label.modulate = Color(1.0, 0.55, 0.4) if elite else Color(1.0, 0.75, 0.55)
	_hp_label.outline_size = 6
	_mesh_root.add_child(_hp_label)

	if elite:
		var tag := Label3D.new()
		tag.text = "ELITE"
		tag.font_size = 36
		tag.pixel_size = 0.01
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, head.position.y + 0.9, 0)
		tag.modulate = Color(1.0, 0.35, 0.3)
		tag.outline_size = 5
		_mesh_root.add_child(tag)

	var feet := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = body_r
	cap.height = body_h + 0.3
	feet.shape = cap
	feet.position = Vector3(0, 0.55 + (body_h + 0.3) * 0.5, 0)
	add_child(feet)

func _build_hurtbox() -> void:
	_hurt = Area3D.new()
	_hurt.name = "Hurtbox"
	_hurt.collision_layer = 4
	_hurt.collision_mask = 0
	_hurt.monitoring = false
	_hurt.monitorable = true
	_hurt.add_to_group("hittable")
	_hurt.position = Vector3(0, 1.0, 0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0 if elite else 0.9, 1.9 if elite else 1.7, 0.8)
	cs.shape = box
	_hurt.add_child(cs)
	add_child(_hurt)
	_hurt.set_meta("foe_root", self)

func _build_touch() -> void:
	_touch = Area3D.new()
	_touch.name = "Touch"
	_touch.collision_layer = 0
	_touch.collision_mask = 2
	_touch.monitoring = true
	_touch.monitorable = false
	_touch.position = Vector3(0, 0.9, 0)
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.85 if elite else 0.75
	cs.shape = sph
	_touch.add_child(cs)
	add_child(_touch)
	_touch.body_entered.connect(_on_touch_body)

func _on_touch_body(body: Node) -> void:
	if _dead or _atk_phase != 0:
		return
	if body != null and body.is_in_group("player"):
		_start_attack(body)


func _refresh_hp_label() -> void:
	if _hp_label:
		_hp_label.text = "%d" % hp

func _flash_hurt() -> void:
	if _mat_body == null:
		return
	_mat_body.albedo_color = Color(0.95, 0.4, 0.3)
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func () -> void:
		if _mat_body:
			_mat_body.albedo_color = _base_color)

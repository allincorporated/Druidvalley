extends Node3D
## Empty road-beyond stub — ground + Coming later + Back to yard.

func _ready() -> void:
	_build()

func _build() -> void:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	var ground := CSGBox3D.new()
	ground.size = Vector3(40, 0.4, 40)
	ground.position = Vector3(0, -0.2, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.48, 0.24)
	gm.roughness = 0.92
	ground.material = gm
	ground.use_collision = true
	world.add_child(ground)

	# Simple stone path strip
	var path := CSGBox3D.new()
	path.size = Vector3(3.0, 0.08, 20.0)
	path.position = Vector3(0, 0.05, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.52, 0.42, 0.34)
	path.material = pm
	path.use_collision = true
	world.add_child(path)

	# Distant misty gate silhouette
	var pillar_l := CSGBox3D.new()
	pillar_l.size = Vector3(0.6, 4.0, 0.6)
	pillar_l.position = Vector3(-2.2, 2.0, -8.0)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.47, 0.50)
	pillar_l.material = stone
	pillar_l.use_collision = true
	world.add_child(pillar_l)
	var pillar_r := CSGBox3D.new()
	pillar_r.size = Vector3(0.6, 4.0, 0.6)
	pillar_r.position = Vector3(2.2, 2.0, -8.0)
	pillar_r.material = stone
	pillar_r.use_collision = true
	world.add_child(pillar_r)
	var lintel := CSGBox3D.new()
	lintel.size = Vector3(5.2, 0.5, 0.6)
	lintel.position = Vector3(0, 4.2, -8.0)
	lintel.material = stone
	lintel.use_collision = true
	world.add_child(lintel)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.0
	world.add_child(sun)

	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.50, 0.58)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.52, 0.60)
	e.ambient_light_energy = 0.55
	env_node.environment = e
	world.add_child(env_node)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.5, 10)
	cam.look_at(Vector3(0, 1.5, -4), Vector3.UP)
	cam.current = true
	world.add_child(cam)

	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	var title := Label.new()
	title.text = "Coming later"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchors_preset = Control.PRESET_CENTER_TOP
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.offset_left = -220.0
	title.offset_right = 220.0
	title.offset_top = 48.0
	title.offset_bottom = 100.0
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
	ui.add_child(title)

	var sub := Label.new()
	sub.text = "The road beyond is not open yet."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.anchor_left = 0.5
	sub.anchor_right = 0.5
	sub.offset_left = -280.0
	sub.offset_right = 280.0
	sub.offset_top = 110.0
	sub.offset_bottom = 150.0
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 0.9))
	ui.add_child(sub)

	var btn := Button.new()
	btn.text = "Back"
	btn.anchor_left = 0.5
	btn.anchor_right = 0.5
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -90.0
	btn.offset_right = 90.0
	btn.offset_top = -90.0
	btn.offset_bottom = -36.0
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(_on_back)
	ui.add_child(btn)

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/druid_yard.tscn")

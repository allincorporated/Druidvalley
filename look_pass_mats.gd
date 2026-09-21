extends RefCounted
## Optional artstyle look-pass under res://assets/textures/look_pass/
## Returns null when a file is missing so callers keep current fallbacks.
## Godot 4.1-safe (no 4.2+ APIs).
class_name LookPassMats

const DIR := "res://assets/textures/look_pass/"

static func has_file(filename: String) -> bool:
	return ResourceLoader.exists(DIR + filename)


static func load_tex(filename: String) -> Texture2D:
	var path := DIR + filename
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _base_albedo(tex: Texture2D, tint: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


## Ground / organic surfaces — triplanar + uv1_scale for CSG / uneven mesh.
static func ground(
	filename: String,
	tint: Color = Color(1, 1, 1),
	uv_scale: float = 2.0,
	rough: float = 0.92,
	triplanar: bool = true,
	sharp: float = 5.0
) -> StandardMaterial3D:
	var tex := load_tex(filename)
	if tex == null:
		return null
	var m := _base_albedo(tex, tint, rough)
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = sharp
	return m


static func _meadow_ground(uv_scale: float, tint: Color) -> StandardMaterial3D:
	## Locked meadow northstar (NOT Codia grass_tile_seamless swirl).
	var path := "res://assets/art/look/grass_painterly_northstar.jpg"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		return ground("grass_tile_seamless.jpg", tint, uv_scale, 0.92, true, 4.0)
	var m := _base_albedo(tex, tint, 0.92)
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	return m


static func grass() -> StandardMaterial3D:
	## Meadow northstar; ~9m / tile so strokes read on big floors.
	return _meadow_ground(9.0, Color(0.96, 0.98, 0.90))


static func grass_bank() -> StandardMaterial3D:
	## Slightly denser on short vertical banks / berms.
	return _meadow_ground(6.0, Color(0.94, 0.97, 0.88))


static func path_stone() -> StandardMaterial3D:
	## Flat path tiles (~4 across ~5m lane). No triplanar — UV on path quads.
	var tex := load_tex("path_stone_tile_seamless.jpg")
	if tex == null:
		return null
	var m := _base_albedo(tex, Color(0.94, 0.93, 0.90), 0.84)
	## ~4.5 tiles across ~5m lane — X carving stays readable
	m.uv1_scale = Vector3(4.5, 4.5, 1.0)
	return m


static func thatch() -> StandardMaterial3D:
	## UV ~1.15 so layered straw bands read on conical roofs (not one blurry wash).
	return ground("thatch_tile_seamless.jpg", Color(0.98, 0.84, 0.58), 1.15, 0.96, true, 7.0)


static func wall() -> StandardMaterial3D:
	## Dry-stone / timber-adjacent; slightly denser UV for block/grain read.
	return ground("wall_tile_seamless.jpg", Color(0.93, 0.91, 0.87), 1.85, 0.90, true, 6.0)


## Unshaded far plate (settlement / glade backdrop).
static func backdrop(filename: String) -> StandardMaterial3D:
	var tex := load_tex(filename)
	if tex == null:
		return null
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.render_priority = -20
	return mat


static func glade_backdrop() -> StandardMaterial3D:
	return backdrop("glade_backdrop.jpg")


static func settlement_backdrop() -> StandardMaterial3D:
	return backdrop("settlement_backdrop_sparse.jpg")


## Spawn a simple unshaded backdrop quad if the look_pass file exists.
static func attach_backdrop_plate(
	parent: Node3D,
	filename: String,
	pos: Vector3 = Vector3(0, 16.0, -50),
	quad_size: Vector2 = Vector2(96, 52),
	node_name: String = "LookPassBackdrop"
) -> MeshInstance3D:
	var mat := backdrop(filename)
	if mat == null or parent == null:
		return null
	var plate := MeshInstance3D.new()
	plate.name = node_name
	var qm := QuadMesh.new()
	qm.size = quad_size
	plate.mesh = qm
	plate.position = pos
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.material_override = mat
	parent.add_child(plate)
	return plate

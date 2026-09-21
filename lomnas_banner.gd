extends CanvasLayer
## Shared Lomnas narrator stub: head + lines on area enter.
class_name LomnasBanner

const HEAD_PATH := "res://assets/art/storyboard/lomnas_narrator_head.jpg"

var _panel: PanelContainer
var _body: Label
var _hide_t: float = 0.0

func _ready() -> void:
	layer = 25
	_build_ui()
	set_process(true)

func _process(delta: float) -> void:
	if _hide_t > 0.0:
		_hide_t -= delta
		if _hide_t <= 0.0 and _panel:
			_panel.visible = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "LomnasPanel"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 16.0
	_panel.offset_right = -16.0
	_panel.offset_top = 56.0
	_panel.offset_bottom = 148.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.88)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.42, 0.78, 0.7)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_panel.add_child(row)

	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(64, 64)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := load(HEAD_PATH) as Texture2D
	if tex:
		tex_rect.texture = tex
	row.add_child(tex_rect)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var title := Label.new()
	title.text = "Lomnas"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.85, 0.78, 1.0))
	col.add_child(title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 17)
	_body.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_body)

func show_lines(text: String, duration: float = 5.0) -> void:
	if _body:
		_body.text = text
	if _panel:
		_panel.visible = true
	_hide_t = duration

static func attach(parent: Node, lines: String, duration: float = 5.0) -> LomnasBanner:
	var b := LomnasBanner.new()
	b.name = "LomnasBanner"
	parent.add_child(b)
	b.call_deferred("show_lines", lines, duration)
	return b

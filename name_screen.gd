extends Control
## First screen: enter a name, then load the 3D yard. Android-safe Start.

@onready var _line: LineEdit = $Panel/VBox/NameEdit
var _starting: bool = false

func _ready() -> void:
	# Do not grab_focus — soft keyboard eats the Start tap on Android.
	if _line:
		_line.placeholder_text = "Your name"
		_line.focus_mode = Control.FOCUS_CLICK
		_line.text_submitted.connect(func(_t: String) -> void: _on_start())
	var btn := $Panel/VBox.get_node_or_null("StartButton") as BaseButton
	if btn == null:
		btn = $Panel/VBox.get_node_or_null("EnterBtn") as BaseButton
	if btn:
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		if not btn.pressed.is_connected(_on_start):
			btn.pressed.connect(_on_start)
		if not btn.button_down.is_connected(_on_start):
			btn.button_down.connect(_on_start)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_start()

func _on_start() -> void:
	if _starting:
		return
	_starting = true
	if _line:
		_line.release_focus()
		DisplayServer.virtual_keyboard_hide()
		GameState.player_name = _line.text.strip_edges()
	else:
		GameState.player_name = ""
	call_deferred("_go_yard")

func _go_yard() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/druid_yard.tscn")
	if err != OK:
		push_error("Failed to load druid_yard.tscn error=%s" % err)
		_starting = false
		var lbl := Label.new()
		lbl.text = "Yard failed to load — script error. Use the newest zip."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		lbl.offset_top = -120
		lbl.offset_bottom = -80
		lbl.add_theme_color_override("font_color", Color(1, 0.35, 0.35))
		add_child(lbl)

func _on_enter_pressed() -> void:
	_on_start()

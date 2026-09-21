extends Control
## Left-side on-screen stick for Android / touch.
## Base/Knob IGNORE mouse so this Control receives the touches.

@export var radius: float = 72.0
@export var deadzone: float = 0.12

var direction: Vector2 = Vector2.ZERO
var _touch_index: int = -1
var _center: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO

@onready var _base: ColorRect = $Base
@onready var _knob: ColorRect = $Knob

func _ready() -> void:
	add_to_group("virtual_joystick")
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 20
	focus_mode = Control.FOCUS_NONE
	_anchor_left_pad()
	if _base:
		_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_base.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	if _knob:
		_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_knob.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_update_layout()
	resized.connect(_update_layout)


func _anchor_left_pad() -> void:
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	var pad_w := radius * 2.0 + 64.0
	var pad_h := radius * 2.0 + 64.0
	offset_left = 8.0
	offset_right = 8.0 + pad_w
	offset_top = -pad_h - 8.0
	offset_bottom = -8.0


func _update_layout() -> void:
	_center = size * 0.5
	_knob_pos = _center
	_apply_visuals()


func _apply_visuals() -> void:
	if _base:
		_base.position = _center - Vector2(radius, radius)
		_base.size = Vector2(radius * 2.0, radius * 2.0)
	if _knob:
		var kr := radius * 0.38
		_knob.position = _knob_pos - Vector2(kr, kr)
		_knob.size = Vector2(kr * 2.0, kr * 2.0)


func _gui_input(event: InputEvent) -> void:
	_handle(event, true)


func _input(event: InputEvent) -> void:
	## Fallback: some Android editor builds skip Control._gui_input for touch.
	if _touch_index != -1:
		_handle(event, false)
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var st := event as InputEventScreenTouch
		var local := get_global_transform_with_canvas().affine_inverse() * st.position
		if Rect2(Vector2.ZERO, size).has_point(local):
			_handle(event, false)


func _handle(event: InputEvent, from_gui: bool) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var local := st.position if from_gui else (get_global_transform_with_canvas().affine_inverse() * st.position)
		if st.pressed and _touch_index == -1:
			if from_gui or Rect2(Vector2.ZERO, size).has_point(local):
				_touch_index = st.index
				_update_from_pos(local)
				accept_event()
		elif (not st.pressed) and st.index == _touch_index:
			_release()
			accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch_index:
			var local := sd.position if from_gui else (get_global_transform_with_canvas().affine_inverse() * sd.position)
			_update_from_pos(local)
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var local := mb.position if from_gui else (get_global_transform_with_canvas().affine_inverse() * mb.position)
		if mb.pressed and _touch_index == -1:
			if from_gui or Rect2(Vector2.ZERO, size).has_point(local):
				_touch_index = 0
				_update_from_pos(local)
				accept_event()
		elif (not mb.pressed) and _touch_index == 0:
			_release()
			accept_event()
	elif event is InputEventMouseMotion and _touch_index == 0:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var mm := event as InputEventMouseMotion
			var local := mm.position if from_gui else (get_global_transform_with_canvas().affine_inverse() * mm.position)
			_update_from_pos(local)
			accept_event()


func _release() -> void:
	_touch_index = -1
	direction = Vector2.ZERO
	_knob_pos = _center
	_apply_visuals()


func _update_from_pos(local_pos: Vector2) -> void:
	var offset := local_pos - _center
	if offset.length() > radius:
		offset = offset.normalized() * radius
	_knob_pos = _center + offset
	var n := offset / radius
	direction = Vector2.ZERO if n.length() < deadzone else n
	_apply_visuals()

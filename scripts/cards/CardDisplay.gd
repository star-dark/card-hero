class_name CardDisplay
extends Control

signal card_played(card: CardData)
signal drag_started
signal drag_ended

@export var card_data: CardData:
	set(value):
		card_data = value
		if is_inside_tree():
			_update_display()

@onready var _bg: TextureRect           = $Background
@onready var _frame: TextureRect        = $CardFrame
@onready var _illust_frame: TextureRect = $IllustrationFrame
@onready var _illust: TextureRect       = $Illustration
@onready var _desc_bg: TextureRect      = $DescriptionBG
@onready var _cost_icon: TextureRect    = $CostIcon
@onready var _name_label: Label         = $CardFrame/CardNameLabel
@onready var _desc_label: Label         = $DescriptionBG/DescriptionLabel
@onready var _cost_label: Label         = $CostIcon/CostLabel

const _UI_TEXTURES := {
	"bg":           "res://assets/sprites/ui/card/card_bg.png",
	"frame":        "res://assets/sprites/ui/card/card_frame.png",
	"illust_frame": "res://assets/sprites/ui/card/card_illust_frame.png",
	"desc_bg":      "res://assets/sprites/ui/card/card_desc.png",
	"cost_icon":    "res://assets/sprites/ui/card/card_cost.png",
}

const DRAG_MIN_DIST    := 8.0
const PLAY_Y_THRESHOLD := -55.0  # 마우스 기준 위로 55px 이상 드래그하면 발동

var _is_dragging       := false
var _press_active      := false  # 이 카드에서 마우스를 눌렀는지
var _press_global      := Vector2.ZERO   # 드래그 시작 마우스 위치
var _drag_start_global := Vector2.ZERO   # 카드 초기 위치 (snap-back용)
var _drag_mouse_offset := Vector2.ZERO   # 카드 origin → 마우스 간격
var _original_parent: Node = null
var _original_index: int   = 0

# ── 초기화 ────────────────────────────────────────────────────────
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(false)  # 마우스 프레스 때만 활성화
	_load_ui_textures()
	if card_data:
		_update_display()

func setup(data: CardData) -> void:
	card_data = data

func _load_ui_textures() -> void:
	for key in _UI_TEXTURES:
		var path: String = _UI_TEXTURES[key]
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			match key:
				"bg":           _bg.texture = tex
				"frame":        _frame.texture = tex
				"illust_frame": _illust_frame.texture = tex
				"desc_bg":      _desc_bg.texture = tex
				"cost_icon":    _cost_icon.texture = tex

func _update_display() -> void:
	if not card_data:
		return
	_name_label.text = card_data.card_name
	_desc_label.text = card_data.description
	_cost_label.text = str(card_data.cost)
	if card_data.illustration:
		_illust.texture = card_data.illustration
		_illust.visible = true
	else:
		_illust.visible = false

# ── 호버 ──────────────────────────────────────────────────────────
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			if not _is_dragging and not _press_active:
				_hover_enter()
		NOTIFICATION_MOUSE_EXIT:
			if not _is_dragging:
				_hover_exit()

func _hover_enter() -> void:
	pivot_offset = Vector2(size.x * 0.5, size.y)
	z_index = 10
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2(1.2, 1.2), 0.15)

func _hover_exit() -> void:
	var tw := create_tween().set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)
	tw.tween_callback(func(): z_index = 0)

func reset_hover() -> void:
	if _is_dragging:
		return
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.1)
	z_index = 0

# ── 드래그 ────────────────────────────────────────────────────────
# _gui_input: 이 카드 위에서 프레스 감지만 담당
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_active      = true
			_press_global      = get_global_mouse_position()
			_drag_mouse_offset = _press_global - global_position
			set_process_input(true)
		else:
			# 드래그 없이 그냥 뗀 경우
			if not _is_dragging:
				_press_active = false
				set_process_input(false)

# _input: 드래그 중 전역 이벤트 수신 (reparent 후에도 안정적)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		_press_active = false
		set_process_input(false)
		if _is_dragging:
			_end_drag()

	elif event is InputEventMouseMotion:
		if _press_active and not _is_dragging:
			if get_global_mouse_position().distance_to(_press_global) > DRAG_MIN_DIST:
				_start_drag()
		if _is_dragging:
			global_position = get_global_mouse_position() - _drag_mouse_offset

func _start_drag() -> void:
	_is_dragging     = true
	_original_parent = get_parent()
	_original_index  = get_index()
	# _press_global은 이미 마우스 누른 시점에 기록됨 → 발동 판정 기준으로 사용

	drag_started.emit()

	reparent(_get_canvas_layer(), true)
	_drag_start_global = global_position  # snap-back용 카드 위치

	rotation     = 0.0
	pivot_offset = size * 0.5
	scale        = Vector2(1.08, 1.08)
	z_index      = 100

func _end_drag() -> void:
	_is_dragging = false
	# 카드 position이 아닌 마우스 이동량으로 판정 (reparent 좌표계 영향 없음)
	var mouse_moved_y := get_global_mouse_position().y - _press_global.y

	if mouse_moved_y < PLAY_Y_THRESHOLD:
		if card_data and CardManager.current_cost < card_data.cost:
			# 코스트 부족 → 메시지 표시 후 복귀
			_show_cost_msg()
			_snap_back(true)
		else:
			scale   = Vector2.ONE
			z_index = 0
			hide()
			card_played.emit(card_data)
			queue_free()
		return

	_snap_back(false)

func _snap_back(flash_red: bool) -> void:
	if is_instance_valid(_original_parent):
		reparent(_original_parent, true)
		_original_parent.move_child(self, _original_index)

	z_index      = 0
	pivot_offset = Vector2(size.x * 0.5, size.y)

	if flash_red:
		modulate = Color(1.0, 0.35, 0.35)
		create_tween().tween_property(self, "modulate", Color.WHITE, 0.4)

	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tw.tween_property(self, "scale", Vector2.ONE, 0.45).from(Vector2(1.08, 1.08))

	drag_ended.emit()

func _show_cost_msg() -> void:
	var label := Label.new()
	label.text = "코스트 부족!"
	label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	label.add_theme_font_size_override("font_size", 16)
	# 카드 위쪽 중앙에 표시
	var canvas := _get_canvas_layer()
	canvas.add_child(label)
	label.position = global_position + Vector2(size.x * 0.5 - 40, -28)

	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y - 45, 0.65)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.65)
	tw.tween_callback(label.queue_free)

func _get_canvas_layer() -> Node:
	var node := get_parent()
	while node:
		if node is CanvasLayer:
			return node
		node = node.get_parent()
	return get_tree().root

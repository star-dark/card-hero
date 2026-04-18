extends Node2D

const WARRIOR_SCENE := preload("res://scenes/player/warrior.tscn")
const ENEMY_SCENE   := preload("res://scenes/enemies/base_enemy.tscn")
const CARD_SCENE    := preload("res://scenes/ui/card/card.tscn")

var player: Warrior
var hand_cards: Array[CardDisplay] = []
var deck_view_cards: Array[CardDisplay] = []

# HUD 루트
@onready var hud: CanvasLayer = $HUD

# HUD 자식 노드(코드에서 생성)
var hp_label: Label
var mana_label: Label
var deck_button: Button
var hand_count_label: Label
var instructions_label: Label
var game_over_label: Label

# 손패 펼침 영역 (R 토글)
var fan_root: Control
var fan_dim: ColorRect
var fan_hand: Control

# 덱 열람 오버레이 (Tab / 덱 버튼)
var deck_overlay: Control
var deck_grid: GridContainer

var hand_visible := false
var deck_overlay_visible := false

func _ready() -> void:
	_build_hud()

	# 플레이어 스폰
	player = WARRIOR_SCENE.instantiate()
	player.position = Vector2(400, 300)
	add_child(player)
	player.health.health_changed.connect(_on_player_health_changed)

	# 적 스폰 (속성별 3마리)
	_spawn_enemy(Vector2(700, 200), CardData.Element.FIRE,     50)
	_spawn_enemy(Vector2(750, 350), CardData.Element.GRASS,    50)
	_spawn_enemy(Vector2(650, 480), CardData.Element.ELECTRIC, 50)

	# 카드 매니저 시그널 연결
	CardManager.hand_changed.connect(_update_hand_ui, CONNECT_DEFERRED)
	CardManager.cost_changed.connect(_update_cost_ui, CONNECT_DEFERRED)

	GameManager.game_state_changed.connect(_on_game_state_changed)

	# 초기 UI
	_update_hand_ui()
	_update_cost_ui(CardManager.current_cost)
	_on_player_health_changed(player.health.current_health, player.health.max_health)
	_set_hand_visible(false)

func _spawn_enemy(pos: Vector2, element: CardData.Element, hp: int) -> void:
	var e: BaseEnemy = ENEMY_SCENE.instantiate()
	e.position  = pos
	e.element   = element
	e.max_health = hp
	add_child(e)

# ── HUD 빌드 ─────────────────────────────────────────────────────
func _build_hud() -> void:
	# 체력 (top-left)
	var hp_panel := _make_panel(Vector2(10, 10), Vector2(260, 40), Color(0, 0, 0, 0.55))
	hud.add_child(hp_panel)
	hp_label = Label.new()
	hp_label.text = "HP  100 / 100"
	hp_label.add_theme_font_size_override("font_size", 18)
	hp_label.position = Vector2(12, 8)
	hp_panel.add_child(hp_label)

	# 마나 (top-right, 육각 느낌 Panel)
	var mana_panel := _make_panel(Vector2(-110, 10), Vector2(100, 100), Color(0.1, 0.1, 0.3, 0.7))
	mana_panel.anchor_left = 1.0
	mana_panel.anchor_right = 1.0
	hud.add_child(mana_panel)
	mana_label = Label.new()
	mana_label.text = "0/5"
	mana_label.add_theme_font_size_override("font_size", 24)
	mana_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	mana_label.anchor_right = 1.0
	mana_label.anchor_bottom = 1.0
	mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mana_panel.add_child(mana_label)

	# 덱 버튼 (bottom-left)
	deck_button = Button.new()
	deck_button.text = "📚\n덱"
	deck_button.custom_minimum_size = Vector2(80, 80)
	deck_button.anchor_top = 1.0
	deck_button.anchor_bottom = 1.0
	deck_button.offset_left = 12.0
	deck_button.offset_top = -92.0
	deck_button.offset_right = 92.0
	deck_button.offset_bottom = -12.0
	deck_button.add_theme_font_size_override("font_size", 16)
	deck_button.pressed.connect(_toggle_deck_overlay)
	hud.add_child(deck_button)

	# 손패 수 (bottom-right) — 카드 아이콘 느낌 Panel
	var hand_count_panel := _make_panel(Vector2(0, 0), Vector2(80, 80), Color(0.15, 0.15, 0.2, 0.8))
	hand_count_panel.anchor_left = 1.0
	hand_count_panel.anchor_top = 1.0
	hand_count_panel.anchor_right = 1.0
	hand_count_panel.anchor_bottom = 1.0
	hand_count_panel.offset_left = -92.0
	hand_count_panel.offset_top = -92.0
	hand_count_panel.offset_right = -12.0
	hand_count_panel.offset_bottom = -12.0
	hud.add_child(hand_count_panel)
	hand_count_label = Label.new()
	hand_count_label.text = "0"
	hand_count_label.add_theme_font_size_override("font_size", 28)
	hand_count_label.anchor_right = 1.0
	hand_count_label.anchor_bottom = 1.0
	hand_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hand_count_panel.add_child(hand_count_label)

	# 조작 안내
	instructions_label = Label.new()
	instructions_label.text = "WASD: 이동  |  Z: 기본공격(3타콤보)  |  X홀드: 차지  |  Space: 대쉬  |  R: 손패 펼치기  |  Tab: 덱 보기"
	instructions_label.modulate = Color(0.8, 0.8, 0.8)
	instructions_label.add_theme_font_size_override("font_size", 12)
	instructions_label.position = Vector2(10, 60)
	hud.add_child(instructions_label)

	# 손패 펼침 오버레이
	fan_root = Control.new()
	fan_root.anchor_right = 1.0
	fan_root.anchor_bottom = 1.0
	fan_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fan_root)

	fan_dim = ColorRect.new()
	fan_dim.color = Color(0, 0, 0, 0.35)
	fan_dim.anchor_right = 1.0
	fan_dim.anchor_bottom = 1.0
	fan_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fan_root.add_child(fan_dim)

	fan_hand = Control.new()
	fan_hand.anchor_left = 0.0
	fan_hand.anchor_right = 1.0
	fan_hand.anchor_top = 1.0
	fan_hand.anchor_bottom = 1.0
	fan_hand.offset_top = -220.0
	fan_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fan_root.add_child(fan_hand)

	# 덱 열람 오버레이
	deck_overlay = Control.new()
	deck_overlay.anchor_right = 1.0
	deck_overlay.anchor_bottom = 1.0
	deck_overlay.visible = false
	deck_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(deck_overlay)

	var deck_dim := ColorRect.new()
	deck_dim.color = Color(0, 0, 0, 0.75)
	deck_dim.anchor_right = 1.0
	deck_dim.anchor_bottom = 1.0
	deck_dim.gui_input.connect(_on_deck_overlay_bg_input)
	deck_overlay.add_child(deck_dim)

	var deck_title := Label.new()
	deck_title.text = "덱에 남은 카드"
	deck_title.add_theme_font_size_override("font_size", 24)
	deck_title.position = Vector2(40, 20)
	deck_overlay.add_child(deck_title)

	var close_hint := Label.new()
	close_hint.text = "Tab / 클릭으로 닫기"
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.modulate = Color(0.7, 0.7, 0.7)
	close_hint.position = Vector2(40, 56)
	deck_overlay.add_child(close_hint)

	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 40.0
	scroll.offset_top = 90.0
	scroll.offset_right = -40.0
	scroll.offset_bottom = -40.0
	deck_overlay.add_child(scroll)

	var deck_center := CenterContainer.new()
	deck_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(deck_center)

	deck_grid = GridContainer.new()
	deck_grid.columns = 5
	deck_grid.add_theme_constant_override("h_separation", 48)
	deck_grid.add_theme_constant_override("v_separation", 56)
	deck_center.add_child(deck_grid)

	# 게임오버
	game_over_label = Label.new()
	game_over_label.text = "GAME OVER"
	game_over_label.add_theme_font_size_override("font_size", 52)
	game_over_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	game_over_label.anchor_left = 0.5
	game_over_label.anchor_top = 0.5
	game_over_label.anchor_right = 0.5
	game_over_label.anchor_bottom = 0.5
	game_over_label.offset_left = -200
	game_over_label.offset_top = -40
	game_over_label.offset_right = 200
	game_over_label.offset_bottom = 40
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.visible = false
	hud.add_child(game_over_label)

func _make_panel(pos: Vector2, s: Vector2, bg: Color) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = s
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_color = Color(1, 1, 1, 0.3)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	panel.add_theme_stylebox_override("panel", style)
	return panel

# ── UI 업데이트 ──────────────────────────────────────────────────
func _on_player_health_changed(current: int, max_hp: int) -> void:
	hp_label.text = "HP  %d / %d" % [current, max_hp]

func _update_cost_ui(current_cost: int) -> void:
	mana_label.text = "%d/%d" % [current_cost, CardManager.MAX_COST]

func _update_hand_ui() -> void:
	for c in hand_cards:
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			c.queue_free()
	hand_cards.clear()

	for card in CardManager.hand:
		var card_display: CardDisplay = CARD_SCENE.instantiate()
		fan_hand.add_child(card_display)
		card_display.size = Vector2(100, 140)
		card_display.setup(card)
		card_display.card_played.connect(_on_card_pressed)
		card_display.drag_started.connect(_on_card_drag_started.bind(card_display))
		card_display.drag_ended.connect(_arrange_fan)
		hand_cards.append(card_display)

	_arrange_fan()
	_apply_hand_interactivity()

	if is_instance_valid(hand_count_label):
		hand_count_label.text = "%d" % CardManager.hand.size()

func _arrange_fan() -> void:
	var n := hand_cards.size()
	if n == 0:
		return

	var fan_size := fan_hand.size
	if fan_size == Vector2.ZERO:
		# 초기 레이아웃이 아직 안 잡혔을 수 있음 → 기본값
		fan_size = Vector2(1152, 220)

	var center_x := fan_size.x * 0.5
	var baseline_y := fan_size.y - 20.0
	var card_pitch := 70.0     # 카드 간 고정 간격 (장수에 따라 넓어지지 않게)
	var max_angle_deg := 16.0  # 최대 회전 각도 (양 끝)
	var card_w := 100.0

	# 카드 수 기준으로 전체 폭 계산 → 중앙 정렬
	var total_width := float(n - 1) * card_pitch
	var start_x := center_x - total_width * 0.5

	for i in n:
		var card := hand_cards[i]
		if not is_instance_valid(card):
			continue
		var t := 0.5 if n == 1 else float(i) / float(n - 1)
		var offset_t := t - 0.5    # -0.5 ~ 0.5
		var angle_deg := offset_t * max_angle_deg
		var rad := deg_to_rad(angle_deg)

		var px := start_x + float(i) * card_pitch - card_w * 0.5
		var py := baseline_y - card.size.y + absf(offset_t) * 20.0  # 가운데가 가장 위

		card.rotation = rad
		card.position = Vector2(px, py)
		card.pivot_offset = Vector2(card.size.x * 0.5, card.size.y)

func _apply_hand_interactivity() -> void:
	var filter := Control.MOUSE_FILTER_STOP if hand_visible else Control.MOUSE_FILTER_IGNORE
	for c in hand_cards:
		if is_instance_valid(c):
			c.mouse_filter = filter
			c.visible = hand_visible

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	if event.is_action_pressed("toggle_hand"):
		_set_hand_visible(not hand_visible)
	elif event.is_action_pressed("show_deck"):
		_toggle_deck_overlay()

func _set_hand_visible(v: bool) -> void:
	hand_visible = v
	if is_instance_valid(fan_root):
		fan_root.visible = v
	_apply_hand_interactivity()
	if v:
		_arrange_fan()

func _on_card_drag_started(dragged: CardDisplay) -> void:
	for c in hand_cards:
		if is_instance_valid(c) and c != dragged:
			c.reset_hover()

func _on_card_pressed(card: CardData) -> void:
	if player and GameManager.current_state == GameManager.GameState.PLAYING:
		player.use_card_from_hand(card)
	# 카드 사용 후 자동으로 펼침 닫기
	_set_hand_visible(false)
	# 거부(스턴 등)로 hand_changed가 안 떠도 UI 동기화 보장
	call_deferred("_update_hand_ui")

func _on_game_state_changed(new_state: int) -> void:
	if new_state == GameManager.GameState.GAME_OVER:
		game_over_label.visible = true
		for c in hand_cards:
			if is_instance_valid(c):
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ── 덱 오버레이 ─────────────────────────────────────────────────
func _toggle_deck_overlay() -> void:
	deck_overlay_visible = not deck_overlay_visible
	deck_overlay.visible = deck_overlay_visible
	if deck_overlay_visible:
		_populate_deck_view()

func _populate_deck_view() -> void:
	for c in deck_view_cards:
		if is_instance_valid(c):
			c.free()
	deck_view_cards.clear()

	for card in CardManager.deck:
		var cd: CardDisplay = CARD_SCENE.instantiate()
		cd.custom_minimum_size = Vector2(80, 112)
		cd.size = Vector2(80, 112)
		deck_grid.add_child(cd)
		# _ready()가 mouse_filter를 STOP으로 덮어쓰므로 add_child 뒤에 다시 IGNORE로
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.setup(card)
		deck_view_cards.append(cd)

func _on_deck_overlay_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_toggle_deck_overlay()

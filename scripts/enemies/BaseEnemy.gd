class_name BaseEnemy
extends CharacterBody2D

enum State { IDLE, CHASE, WINDUP, DASH, RECOVER, DEAD }

# ── 스탯 ─────────────────────────────────────────────────────────
const MOVE_SPEED     := 75.0
const DETECT_RANGE   := 260.0
const DASH_RANGE     := 200.0   # 이 거리 안에서 윈드업 시작
const DASH_HIT_RANGE := 58.0    # 대쉬 중 이 거리 내면 피격(플레이어 콜리전 70x70 대응)
const WINDUP_TIME    := 0.55    # 대쉬 전 대기
const DASH_SPEED     := 360.0
const DASH_DURATION  := 0.35
const RECOVER_TIME   := 0.7
const DASH_DAMAGE    := 12
const PLAYER_KNOCKBACK_FORCE := 420.0
const KNOCKBACK_DECAY := 9.0

@export var max_health: int = 50
@export var element: CardData.Element = CardData.Element.NONE

# ── 노드 참조 ────────────────────────────────────────────────────
@onready var sprite: Sprite2D         = $Sprite2D
@onready var health: HealthComponent  = $HealthComponent

var state: State   = State.IDLE
var player: Node2D = null

var state_timer      := 0.0
var dash_direction   := Vector2.ZERO
var _dash_hit_player := false

var knockback_velocity := Vector2.ZERO

# ── 속성별 색상 ──────────────────────────────────────────────────
static func element_color(el: CardData.Element) -> Color:
	match el:
		CardData.Element.FIRE:     return Color(1.0, 0.25, 0.15)
		CardData.Element.GRASS:    return Color(0.2,  0.9, 0.25)
		CardData.Element.WATER:    return Color(0.15, 0.4, 1.0)
		CardData.Element.EARTH:    return Color(0.6,  0.5, 0.3)
		CardData.Element.ELECTRIC: return Color(1.0,  1.0, 0.15)
		_:                         return Color(0.75, 0.2, 0.9)

func _ready() -> void:
	add_to_group("enemy")
	health.max_health     = max_health
	health.current_health = max_health
	health.died.connect(_on_died)
	_make_placeholder_sprite()
	call_deferred("_find_player")

func _make_placeholder_sprite() -> void:
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(element_color(element))
	# 삼각형 마킹 (적 구분용)
	for x in 8:
		img.set_pixel(14, 4 + x, Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(img)

func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

# ── 메인 루프 ────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	# 넉백은 DEAD 포함 모든 상태보다 우선 → 죽으면서 튕겨나가는 연출 가능
	if knockback_velocity.length() > 5.0:
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, delta * KNOCKBACK_DECAY)
		move_and_slide()
		return

	if state == State.DEAD:
		return

	if player == null:
		_find_player()
		return

	var dist := global_position.distance_to(player.global_position)
	state_timer -= delta

	match state:
		State.IDLE:      _state_idle(dist)
		State.CHASE:     _state_chase(dist)
		State.WINDUP:    _state_windup(dist)
		State.DASH:      _state_dash(delta)
		State.RECOVER:   _state_recover(dist)

# ── 상태 핸들러 ──────────────────────────────────────────────────
func _state_idle(dist: float) -> void:
	velocity = Vector2.ZERO
	if dist <= DETECT_RANGE:
		_enter_chase()

func _state_chase(dist: float) -> void:
	if dist > DETECT_RANGE * 1.3:
		_enter_idle()
		return

	if dist <= DASH_RANGE:
		_enter_windup()
		return

	var dir := (player.global_position - global_position).normalized()
	velocity = dir * MOVE_SPEED
	if dir.x != 0.0:
		sprite.flip_h = dir.x < 0.0
	move_and_slide()

func _state_windup(_dist: float) -> void:
	velocity = Vector2.ZERO
	# 텔레그래프: 색 번쩍임은 진입 시 한 번만 튜닝
	if state_timer <= 0.0:
		_enter_dash()

func _state_dash(_delta: float) -> void:
	velocity = dash_direction * DASH_SPEED
	move_and_slide()

	# 대쉬 중 플레이어와 접촉 시 데미지 + 넉백 (한 번만)
	if not _dash_hit_player and player != null:
		var hit_player := false
		# 우선 slide 충돌로 판정 — 플레이어 콜리전 경계에 닿는 순간
		for i in get_slide_collision_count():
			var col := get_slide_collision(i)
			if col.get_collider() != null and col.get_collider().is_in_group("player"):
				hit_player = true
				break
		# 보조: 거리로도 판정 (빠르게 지나가는 케이스)
		if not hit_player:
			hit_player = global_position.distance_to(player.global_position) <= DASH_HIT_RANGE

		if hit_player:
			var warrior := player as Warrior
			if warrior and not warrior.is_invincible:
				var hp: HealthComponent = player.get_node_or_null("HealthComponent")
				if hp:
					hp.take_damage(DASH_DAMAGE)
				if warrior.has_method("apply_knockback"):
					warrior.apply_knockback(dash_direction * PLAYER_KNOCKBACK_FORCE)
				_dash_hit_player = true

	if state_timer <= 0.0:
		_enter_recover()

func _state_recover(dist: float) -> void:
	velocity = Vector2.ZERO
	if state_timer <= 0.0:
		if dist > DETECT_RANGE * 1.3:
			_enter_idle()
		else:
			_enter_chase()

# ── 상태 전이 ───────────────────────────────────────────────────
func _enter_idle() -> void:
	state = State.IDLE
	velocity = Vector2.ZERO

func _enter_chase() -> void:
	state = State.CHASE

func _enter_windup() -> void:
	state = State.WINDUP
	state_timer = WINDUP_TIME
	velocity = Vector2.ZERO
	_dash_hit_player = false

	# 방향 고정 (윈드업 순간의 플레이어 방향)
	dash_direction = (player.global_position - global_position).normalized()
	if dash_direction == Vector2.ZERO:
		dash_direction = Vector2.RIGHT
	sprite.flip_h = dash_direction.x < 0.0

	# 텔레그래프: 노란색 번쩍
	var base_col := element_color(element)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color(1.6, 1.6, 0.4), WINDUP_TIME * 0.6)
	tw.tween_property(sprite, "modulate", base_col, WINDUP_TIME * 0.4)

func _enter_dash() -> void:
	state = State.DASH
	state_timer = DASH_DURATION

	# 대쉬 중 시각 효과
	sprite.modulate = Color(1.2, 0.3, 0.3)

func _enter_recover() -> void:
	state = State.RECOVER
	state_timer = RECOVER_TIME
	velocity = Vector2.ZERO
	sprite.modulate = element_color(element)

# ── 외부 호출 ──────────────────────────────────────────────────
func apply_knockback(impulse: Vector2) -> void:
	knockback_velocity = impulse
	# 공격/대쉬 상태에서도 넉백으로 끊김 → 회복 상태로 (살아있을 때만)
	if state == State.DASH or state == State.WINDUP:
		_enter_recover()

func _on_died() -> void:
	state = State.DEAD
	# physics_process는 유지 → 죽는 도중에도 넉백 적용됨

	var tween := create_tween()
	tween.tween_interval(0.35)   # 넉백이 진행될 시간을 잠깐 준 뒤
	tween.tween_property(sprite, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)

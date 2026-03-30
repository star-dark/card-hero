class_name Warrior
extends CharacterBody2D

# ── 스탯 ─────────────────────────────────────────────────────────
const MOVE_SPEED       := 200.0
const DASH_SPEED       := 520.0
const DASH_DURATION    := 0.15
const DASH_COOLDOWN    := 0.8
const CHARGE_HOLD_TIME := 0.5   # X키를 이 시간 이상 누르면 차지 발동
const ATTACK_DAMAGE    := 15
const CHARGE_DAMAGE    := 40
const ATTACK_STUN_TIME := 0.25

# ── 상태 ─────────────────────────────────────────────────────────
var is_dashing       := false
var is_invincible    := false
var dash_direction   := Vector2.RIGHT
var dash_timer       := 0.0
var dash_cd_timer    := 0.0
var is_attacking     := false
var attack_stun_timer := 0.0
var is_charging      := false
var charge_timer     := 0.0
var face_dir         := Vector2.RIGHT

# ── 노드 참조 ────────────────────────────────────────────────────
@onready var sprite: Sprite2D       = $Sprite2D
@onready var attack_area: Area2D    = $AttackArea
@onready var health: HealthComponent = $HealthComponent

func _ready() -> void:
	add_to_group("player")
	health.died.connect(_on_died)
	_make_placeholder_sprite(Color(0.95, 0.45, 0.1))  # 불 → 주황

func _make_placeholder_sprite(color: Color) -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(color)
	sprite.texture = ImageTexture.create_from_image(img)

# ── 메인 루프 ────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	if is_dashing:
		velocity = dash_direction * DASH_SPEED
		move_and_slide()
		return

	if not is_attacking:
		_handle_movement()
	else:
		velocity = velocity.lerp(Vector2.ZERO, 0.25)

	_handle_combat(delta)
	move_and_slide()

func _tick_timers(delta: float) -> void:
	# 대쉬
	if dash_timer > 0.0:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing  = false
			is_invincible = false
	if dash_cd_timer > 0.0:
		dash_cd_timer -= delta

	# 공격 경직
	if attack_stun_timer > 0.0:
		attack_stun_timer -= delta
		if attack_stun_timer <= 0.0:
			is_attacking = false

func _handle_movement() -> void:
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up",   "ui_down")
	)
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		face_dir = dir
		if dir.x != 0.0:
			sprite.flip_h = dir.x < 0.0
	velocity = dir * MOVE_SPEED

func _handle_combat(delta: float) -> void:
	# 기본공격 (Z)
	if Input.is_action_just_pressed("attack"):
		_basic_attack()
		return

	# 차지공격 (X, 홀드)
	if Input.is_action_pressed("special_attack"):
		is_charging   = true
		charge_timer += delta
		var t := minf(charge_timer / CHARGE_HOLD_TIME, 1.0)
		sprite.modulate = Color(1.0 + t, 1.0 - t * 0.5, 0.3)
	elif Input.is_action_just_released("special_attack"):
		if is_charging and charge_timer >= CHARGE_HOLD_TIME:
			_charge_attack()
		is_charging  = false
		charge_timer = 0.0
		sprite.modulate = Color.WHITE

	# 대쉬 (Space)
	if Input.is_action_just_pressed("dash") and dash_cd_timer <= 0.0:
		_start_dash()

# ── 전투 액션 ────────────────────────────────────────────────────
func _basic_attack() -> void:
	is_attacking      = true
	attack_stun_timer = ATTACK_STUN_TIME

	sprite.modulate = Color(1.8, 1.2, 0.5)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)

	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("enemy"):
			var hp: HealthComponent = body.get_node_or_null("HealthComponent")
			if hp:
				hp.take_damage(ATTACK_DAMAGE)

	CardManager.add_cost(1)

func _charge_attack() -> void:
	is_attacking      = true
	attack_stun_timer = 0.5

	sprite.modulate = Color(2.5, 1.0, 0.2)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.35)

	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("enemy"):
			var hp: HealthComponent = body.get_node_or_null("HealthComponent")
			if hp:
				hp.take_damage(CHARGE_DAMAGE)

	CardManager.draw_card()

func _start_dash() -> void:
	var dir := velocity.normalized()
	if dir == Vector2.ZERO:
		dir = face_dir
	dash_direction = dir
	is_dashing     = true
	is_invincible  = true
	dash_timer     = DASH_DURATION
	dash_cd_timer  = DASH_COOLDOWN

	sprite.modulate = Color(0.4, 0.7, 2.0, 0.6)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, DASH_DURATION + 0.1)

# ── 카드 사용 (test_room에서 호출) ─────────────────────────────
func use_card_from_hand(card: CardData) -> void:
	if not CardManager.use_card(card):
		return

	match card.effect_type:
		CardData.EffectType.ATTACK:
			for body in attack_area.get_overlapping_bodies():
				if body.is_in_group("enemy"):
					var hp: HealthComponent = body.get_node_or_null("HealthComponent")
					if hp:
						hp.take_damage(int(card.damage))
			sprite.modulate = Color(2.0, 0.8, 0.3)
			create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.3)

		CardData.EffectType.HEAL:
			health.heal(int(card.damage))
			sprite.modulate = Color(0.4, 2.0, 0.4)
			create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.3)

func _on_died() -> void:
	set_physics_process(false)
	sprite.modulate = Color(0.3, 0.3, 0.3, 0.6)
	GameManager.game_over()

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

const SPRITE_BASE := "res://assets/Tiny RPG Character Asset Pack v1.02 -Free Soldier&Orc/Soldier/Soldier with shadows/"

# ── 상태 ─────────────────────────────────────────────────────────
var is_dashing        := false
var is_invincible     := false
var dash_direction    := Vector2.RIGHT
var dash_timer        := 0.0
var dash_cd_timer     := 0.0
var is_attacking      := false
var attack_stun_timer := 0.0
var is_charging       := false
var charge_timer      := 0.0
var face_dir          := Vector2.RIGHT

# GUI가 입력을 소비했을 때 게임 입력이 무시되도록 _unhandled_input 사용
var _attack_requested := false

# ── 노드 참조 ────────────────────────────────────────────────────
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D           = $AttackArea
@onready var health: HealthComponent       = $HealthComponent

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_attack_requested = true

func _ready() -> void:
	add_to_group("player")
	health.died.connect(_on_died)
	_setup_animations()
	anim_sprite.play("idle")

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	# 애니메이션명: {파일명, 프레임 수, FPS, 루프 여부}
	var anim_data := {
		"idle":    {"file": "Soldier-Idle.png",     "count": 6, "fps": 8.0,  "loop": true},
		"walk":    {"file": "Soldier-Walk.png",     "count": 8, "fps": 10.0, "loop": true},
		"attack":  {"file": "Soldier-Attack01.png", "count": 6, "fps": 14.0, "loop": false},
		"attack2": {"file": "Soldier-Attack02.png", "count": 6, "fps": 14.0, "loop": false},
		"charge":  {"file": "Soldier-Attack03.png", "count": 9, "fps": 10.0, "loop": false},
		"death":   {"file": "Soldier-Death.png",    "count": 4, "fps": 8.0,  "loop": false},
		"hurt":    {"file": "Soldier-Hurt.png",     "count": 4, "fps": 12.0, "loop": false},
	}

	for anim_name in anim_data:
		var data: Dictionary = anim_data[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, data["fps"])
		frames.set_animation_loop(anim_name, data["loop"])

		var texture: Texture2D = load(SPRITE_BASE + data["file"])
		for i in data["count"]:
			var atlas := AtlasTexture.new()
			atlas.atlas  = texture
			atlas.region = Rect2(i * 100, 0, 100, 100)
			frames.add_frame(anim_name, atlas)

	anim_sprite.sprite_frames = frames

# ── 메인 루프 ────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	if is_dashing:
		velocity = dash_direction * DASH_SPEED
		move_and_slide()
		_update_animation()
		return

	_update_facing()

	if not is_attacking:
		_handle_movement()
	else:
		velocity = velocity.lerp(Vector2.ZERO, 0.25)

	_handle_combat(delta)
	move_and_slide()
	_update_animation()

func _update_animation() -> void:
	if is_dashing:
		anim_sprite.speed_scale = 2.0
		if anim_sprite.animation != "walk":
			anim_sprite.play("walk")
		return

	anim_sprite.speed_scale = 1.0

	# 공격/차지 중에는 해당 애니메이션이 스스로 끝날 때까지 유지
	if is_attacking:
		return

	if velocity.length() > 10.0:
		if anim_sprite.animation != "walk":
			anim_sprite.play("walk")
	else:
		if anim_sprite.animation != "idle":
			anim_sprite.play("idle")

func _tick_timers(delta: float) -> void:
	# 대쉬
	if dash_timer > 0.0:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing    = false
			is_invincible = false
	if dash_cd_timer > 0.0:
		dash_cd_timer -= delta

	# 공격 경직
	if attack_stun_timer > 0.0:
		attack_stun_timer -= delta
		if attack_stun_timer <= 0.0:
			is_attacking = false

func _get_mouse_dir() -> Vector2:
	var mouse_world := get_global_mouse_position()
	var dir := (mouse_world - global_position).normalized()
	return dir if dir != Vector2.ZERO else Vector2.RIGHT

func _update_facing() -> void:
	var dir := _get_mouse_dir()
	face_dir = dir
	anim_sprite.flip_h = dir.x < 0.0
	attack_area.rotation = dir.angle()

func _handle_movement() -> void:
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up",   "ui_down")
	)
	if dir != Vector2.ZERO:
		dir = dir.normalized()
	velocity = dir * MOVE_SPEED

func _handle_combat(delta: float) -> void:
	# 기본공격 (Z) — _unhandled_input 플래그 사용 (카드 클릭 시 발동 방지)
	if _attack_requested:
		_attack_requested = false
		_basic_attack()
		return

	# 차지공격 (X, 홀드)
	if Input.is_action_pressed("special_attack"):
		is_charging   = true
		charge_timer += delta
		var t := minf(charge_timer / CHARGE_HOLD_TIME, 1.0)
		anim_sprite.modulate = Color(1.0 + t, 1.0 - t * 0.5, 0.3)
	elif Input.is_action_just_released("special_attack"):
		if is_charging and charge_timer >= CHARGE_HOLD_TIME:
			_charge_attack()
		is_charging   = false
		charge_timer  = 0.0
		anim_sprite.modulate = Color.WHITE

	# 대쉬 (Space)
	if Input.is_action_just_pressed("dash") and dash_cd_timer <= 0.0:
		_start_dash()

# ── 전투 액션 ────────────────────────────────────────────────────
func _basic_attack() -> void:
	is_attacking      = true
	attack_stun_timer = ATTACK_STUN_TIME

	anim_sprite.play("attack")
	if not anim_sprite.animation_finished.is_connected(_on_attack_anim_finished):
		anim_sprite.animation_finished.connect(_on_attack_anim_finished, CONNECT_ONE_SHOT)

	var hit := false
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("enemy"):
			var hp: HealthComponent = body.get_node_or_null("HealthComponent")
			if hp:
				hp.take_damage(ATTACK_DAMAGE)
				hit = true

	if hit:
		CardManager.add_cost(1)

func _on_attack_anim_finished() -> void:
	if not is_attacking:
		anim_sprite.play("idle")

func _charge_attack() -> void:
	is_attacking      = true
	attack_stun_timer = 0.5

	anim_sprite.play("charge")
	if not anim_sprite.animation_finished.is_connected(_on_charge_anim_finished):
		anim_sprite.animation_finished.connect(_on_charge_anim_finished, CONNECT_ONE_SHOT)

	var hit := false
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("enemy"):
			var hp: HealthComponent = body.get_node_or_null("HealthComponent")
			if hp:
				hp.take_damage(CHARGE_DAMAGE)
				hit = true

	if hit:
		CardManager.draw_card()

func _on_charge_anim_finished() -> void:
	if not is_attacking:
		anim_sprite.play("idle")

func _start_dash() -> void:
	var dir := velocity.normalized()
	if dir == Vector2.ZERO:
		dir = face_dir
	dash_direction = dir
	is_dashing     = true
	is_invincible  = true
	dash_timer     = DASH_DURATION
	dash_cd_timer  = DASH_COOLDOWN

	anim_sprite.modulate = Color(0.4, 0.7, 2.0, 0.6)
	create_tween().tween_property(anim_sprite, "modulate", Color.WHITE, DASH_DURATION + 0.1)

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
			anim_sprite.play("attack2")
			anim_sprite.animation_finished.connect(
				func(): anim_sprite.play("idle"), CONNECT_ONE_SHOT
			)

		CardData.EffectType.HEAL:
			health.heal(int(card.damage))
			anim_sprite.modulate = Color(0.4, 2.0, 0.4)
			create_tween().tween_property(anim_sprite, "modulate", Color.WHITE, 0.3)

func _on_died() -> void:
	set_physics_process(false)
	anim_sprite.play("death")
	GameManager.game_over()

class_name Warrior
extends CharacterBody2D

# ── 스탯 ─────────────────────────────────────────────────────────
const MOVE_SPEED       := 200.0
const DASH_SPEED       := 520.0
const DASH_DURATION    := 0.15
const DASH_COOLDOWN    := 0.8
const CHARGE_HOLD_TIME := 0.5   # X키를 이 시간 이상 누르면 차지 발동
const ATTACK_DAMAGE    := 1
const FINISHER_DAMAGE  := 28
const CHARGE_DAMAGE    := 40
const ATTACK_STUN_TIME := 0.45  # 애니메이션 재생 시간(6프레임/14fps)에 맞춤
const ATTACK_SPEED     := 0.5   # 공격 속도 배율 (1.0 = 기본, 2.0 = 2배 빠름)

# 히트박스가 활성화될 프레임 (0-indexed)
const ATTACK_HIT_FRAMES  := [2, 3]       # 기본공격 (6프레임 애니메이션)
const CHARGE_HIT_FRAMES  := [5, 6, 7]    # 차지공격 (9프레임 애니메이션)

# 3타 콤보: 마지막 타는 넉백
const COMBO_MAX       := 3
const COMBO_WINDOW    := 0.55   # 다음 입력 유효시간 (공격 종료 후)
const KNOCKBACK_FORCE := 480.0

# 피격 경직 + 넉백
const HIT_STUN_TIME   := 0.35
const HIT_KNOCKBACK_DECAY := 8.0

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

# 콤보
var combo_index       := 0         # 0,1,2 → 다음에 나갈 콤보 단계
var combo_window_timer := 0.0      # 이 시간 안에 또 누르면 이어서 나감

# 피격 경직
var is_stunned        := false
var stun_timer        := 0.0
var hit_knockback     := Vector2.ZERO

# 카드 펼침 상태 (R 토글)
var hand_visible      := false

# 현재 공격의 데미지 및 이번 스윙에서 이미 피격된 적 목록
var _current_attack_damage := 0
var _is_finisher           := false
var _hit_this_swing        := []

# ── 노드 참조 ────────────────────────────────────────────────────
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D           = $AttackArea
@onready var health: HealthComponent       = $HealthComponent


func _ready() -> void:
	add_to_group("player")
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	_setup_animations()
	anim_sprite.play("idle")

	# 히트 판정은 frame_changed에서 get_overlapping_bodies()로 처리
	anim_sprite.frame_changed.connect(_on_frame_changed)

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

	# 피격 경직: 이동/공격 모두 불가 (넉백 중이면 넉백 속도로 밀려남)
	if is_stunned:
		if hit_knockback.length() > 5.0:
			velocity = hit_knockback
			hit_knockback = hit_knockback.lerp(Vector2.ZERO, delta * HIT_KNOCKBACK_DECAY)
		else:
			velocity = velocity.lerp(Vector2.ZERO, 0.3)
		move_and_slide()
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

	# 공격/피격 애니메이션이 세팅된 동안은 절대 덮어쓰지 않음
	if anim_sprite.animation in ["attack", "attack2", "charge", "hurt"]:
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

	# 콤보 윈도우
	if combo_window_timer > 0.0:
		combo_window_timer -= delta
		if combo_window_timer <= 0.0:
			combo_index = 0

	# 피격 경직
	if stun_timer > 0.0:
		stun_timer -= delta
		if stun_timer <= 0.0:
			is_stunned = false
			if anim_sprite.animation == "hurt":
				anim_sprite.play("idle")

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
	# 기본공격 — 마우스가 UI 위에 없을 때만 발동 (카드 클릭 시 발동 방지)
	if Input.is_action_just_pressed("attack"):
		if get_viewport().gui_get_hovered_control() == null:
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
	# 공격 중엔 새 입력 무시 (애니메이션 끝날 때 콤보 대기창에서만 다음 타 수용)
	if is_attacking:
		return

	_is_finisher = (combo_index == COMBO_MAX - 1)
	_current_attack_damage = FINISHER_DAMAGE if _is_finisher else ATTACK_DAMAGE

	is_attacking           = true
	attack_stun_timer      = ATTACK_STUN_TIME / ATTACK_SPEED
	_hit_this_swing.clear()

	# 1/3타 → attack, 2타 → attack2
	var anim_name := "attack2" if combo_index == 1 else "attack"
	anim_sprite.play(anim_name)
	anim_sprite.speed_scale = ATTACK_SPEED

	if not anim_sprite.animation_finished.is_connected(_on_attack_anim_finished):
		anim_sprite.animation_finished.connect(_on_attack_anim_finished, CONNECT_ONE_SHOT)

func _on_frame_changed() -> void:
	var frame := anim_sprite.frame
	var is_hit_frame := false
	match anim_sprite.animation:
		"attack", "attack2": is_hit_frame = frame in ATTACK_HIT_FRAMES
		"charge":            is_hit_frame = frame in CHARGE_HIT_FRAMES

	if not is_hit_frame:
		return

	# 히트 프레임에서만 범위 안 적에게 데미지 적용
	var hit := false
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("enemy") and body not in _hit_this_swing:
			_hit_this_swing.append(body)
			var hp: HealthComponent = body.get_node_or_null("HealthComponent")
			if hp:
				hp.take_damage(_current_attack_damage)
				hit = true
			# 3타 마무리: 넉백
			if _is_finisher and body.has_method("apply_knockback"):
				var kb_dir := (body.global_position - global_position).normalized()
				if kb_dir == Vector2.ZERO:
					kb_dir = face_dir
				body.apply_knockback(kb_dir * KNOCKBACK_FORCE)

	if hit:
		match anim_sprite.animation:
			"attack", "attack2": CardManager.add_cost(1)
			"charge": CardManager.draw_card()

func _on_attack_anim_finished() -> void:
	anim_sprite.speed_scale = 1.0
	anim_sprite.play("idle")

	# 다음 콤보 단계 준비 (3타 끝나면 리셋)
	if _is_finisher:
		combo_index = 0
		combo_window_timer = 0.0
	else:
		combo_index = mini(combo_index + 1, COMBO_MAX - 1)
		combo_window_timer = COMBO_WINDOW

func _charge_attack() -> void:
	is_attacking           = true
	attack_stun_timer      = 0.5
	_current_attack_damage = CHARGE_DAMAGE
	_is_finisher = false
	_hit_this_swing.clear()
	# 차지공격은 콤보를 리셋
	combo_index = 0
	combo_window_timer = 0.0

	anim_sprite.play("charge")
	if not anim_sprite.animation_finished.is_connected(_on_charge_anim_finished):
		anim_sprite.animation_finished.connect(_on_charge_anim_finished, CONNECT_ONE_SHOT)

func _on_charge_anim_finished() -> void:
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

# ── 피격 경직 / 넉백 ─────────────────────────────────────────
func apply_knockback(impulse: Vector2) -> void:
	if is_invincible or health.current_health <= 0:
		return
	hit_knockback = impulse
	# 경직도 같이 걸어서 공격/이동 잠금
	is_stunned = true
	stun_timer = HIT_STUN_TIME

func _on_damaged(_amount: int) -> void:
	if is_invincible or health.current_health <= 0:
		return

	is_stunned = true
	stun_timer = HIT_STUN_TIME

	# 공격/차지 상태 해제
	is_attacking = false
	attack_stun_timer = 0.0
	is_charging = false
	charge_timer = 0.0
	combo_index = 0
	combo_window_timer = 0.0

	anim_sprite.modulate = Color.WHITE
	anim_sprite.speed_scale = 1.0
	anim_sprite.play("hurt")

# ── 카드 사용 (test_room에서 호출) ─────────────────────────────
func use_card_from_hand(card: CardData) -> void:
	if is_stunned:
		return
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

class_name BaseEnemy
extends CharacterBody2D

enum State { IDLE, CHASE, ATTACK, DEAD }

# ── 스탯 ─────────────────────────────────────────────────────────
const MOVE_SPEED    := 75.0
const DETECT_RANGE  := 220.0
const ATTACK_RANGE  := 42.0
const ATTACK_DAMAGE := 10
const ATTACK_CD     := 1.2

@export var max_health: int = 50
@export var element: CardData.Element = CardData.Element.NONE

# ── 노드 참조 ────────────────────────────────────────────────────
@onready var sprite: Sprite2D         = $Sprite2D
@onready var health: HealthComponent  = $HealthComponent

var state: State   = State.IDLE
var player: Node2D = null
var attack_timer   := 0.0

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
	sprite.texture = ImageTexture.create_from_image(img)
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
	if state == State.DEAD:
		return

	if attack_timer > 0.0:
		attack_timer -= delta

	if player == null:
		_find_player()
		return

	var dist := global_position.distance_to(player.global_position)

	match state:
		State.IDLE:   _state_idle(dist)
		State.CHASE:  _state_chase(dist)
		State.ATTACK: _state_attack(dist)

func _state_idle(dist: float) -> void:
	velocity = Vector2.ZERO
	if dist <= DETECT_RANGE:
		state = State.CHASE

func _state_chase(dist: float) -> void:
	if dist > DETECT_RANGE * 1.3:
		state = State.IDLE
		velocity = Vector2.ZERO
		return

	if dist <= ATTACK_RANGE:
		state = State.ATTACK
		velocity = Vector2.ZERO
		return

	var dir := (player.global_position - global_position).normalized()
	velocity = dir * MOVE_SPEED
	if dir.x != 0.0:
		sprite.flip_h = dir.x < 0.0
	move_and_slide()

func _state_attack(dist: float) -> void:
	velocity = Vector2.ZERO
	if dist > ATTACK_RANGE * 1.6:
		state = State.CHASE
		return
	if attack_timer <= 0.0:
		_do_attack()

func _do_attack() -> void:
	attack_timer = ATTACK_CD

	var base_col := element_color(element)
	sprite.modulate = Color(2.0, 0.5, 0.5)
	create_tween().tween_property(sprite, "modulate", base_col, 0.25)

	var warrior := player as Warrior
	if warrior and not warrior.is_invincible:
		var hp: HealthComponent = player.get_node_or_null("HealthComponent")
		if hp:
			hp.take_damage(ATTACK_DAMAGE)

func _on_died() -> void:
	state = State.DEAD
	set_physics_process(false)
	velocity = Vector2.ZERO

	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)

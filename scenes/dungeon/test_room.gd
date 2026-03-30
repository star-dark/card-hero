extends Node2D

const WARRIOR_SCENE := preload("res://scenes/player/warrior.tscn")
const ENEMY_SCENE   := preload("res://scenes/enemies/base_enemy.tscn")

var player: Warrior
var hand_buttons: Array[Button] = []

@onready var hp_label:    Label        = $HUD/TopBar/HPLabel
@onready var cost_label:  Label        = $HUD/TopBar/CostLabel
@onready var deck_label:  Label        = $HUD/TopBar/DeckLabel
@onready var card_hand:   HBoxContainer = $HUD/CardHand
@onready var game_over_label: Label    = $HUD/GameOverLabel

func _ready() -> void:
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
	CardManager.hand_changed.connect(_update_hand_ui)
	CardManager.cost_changed.connect(_update_cost_ui)

	# GameManager 게임오버 연결
	GameManager.game_state_changed.connect(_on_game_state_changed)

	# 초기 UI
	_update_hand_ui()
	_update_cost_ui(CardManager.current_cost)
	_on_player_health_changed(player.health.current_health, player.health.max_health)

func _spawn_enemy(pos: Vector2, element: CardData.Element, hp: int) -> void:
	var e: BaseEnemy = ENEMY_SCENE.instantiate()
	e.position  = pos
	e.element   = element
	e.max_health = hp
	add_child(e)

# ── UI 업데이트 ──────────────────────────────────────────────────
func _on_player_health_changed(current: int, max_hp: int) -> void:
	hp_label.text = "HP  %d / %d" % [current, max_hp]

func _update_cost_ui(current_cost: int) -> void:
	var s := ""
	for i in CardManager.MAX_COST:
		s += ("◆ " if i < current_cost else "◇ ")
	cost_label.text = "코스트  " + s.strip_edges()

func _update_hand_ui() -> void:
	for btn in hand_buttons:
		if is_instance_valid(btn):
			btn.free()
	hand_buttons.clear()

	for card in CardManager.hand:
		var btn := Button.new()
		btn.text         = "[%d코] %s" % [card.cost, card.card_name]
		btn.tooltip_text = card.description
		btn.custom_minimum_size = Vector2(130, 70)
		btn.pressed.connect(_on_card_pressed.bind(card))
		card_hand.add_child(btn)
		hand_buttons.append(btn)

func _process(_delta: float) -> void:
	if is_instance_valid(deck_label):
		deck_label.text = "덱 %d  |  버림 %d" % [
			CardManager.deck.size(),
			CardManager.discard_pile.size()
		]

func _on_card_pressed(card: CardData) -> void:
	if player and GameManager.current_state == GameManager.GameState.PLAYING:
		player.use_card_from_hand(card)

func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.GAME_OVER:
		game_over_label.visible = true
		for btn in hand_buttons:
			if is_instance_valid(btn):
				btn.disabled = true

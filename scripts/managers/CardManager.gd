class_name CardManager
extends Node

signal hand_changed
signal cost_changed(current_cost: int)

const MAX_COST: int = 5
const MAX_HAND: int = 5
const COST_REGEN_INTERVAL: float = 2.0  # 초당 자동 충전

var deck: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var current_cost: int = 0

var _regen_timer: float = 0.0

func _ready() -> void:
	_setup_starter_deck()

func _process(delta: float) -> void:
	if current_cost < MAX_COST:
		_regen_timer += delta
		if _regen_timer >= COST_REGEN_INTERVAL:
			_regen_timer = 0.0
			add_cost(1)

# ── 스타터 덱 (전사용) ────────────────────────────────────────────
func _setup_starter_deck() -> void:
	var cards_to_add: Array[CardData] = []

	var slash := CardData.new()
	slash.card_name = "베기"
	slash.card_type = CardData.CardType.ACTIVE
	slash.cost = 1
	slash.effect_type = CardData.EffectType.ATTACK
	slash.damage = 20.0
	slash.description = "적을 베어 20 데미지"
	slash.element = CardData.Element.FIRE

	var charge_slash := CardData.new()
	charge_slash.card_name = "차지 베기"
	charge_slash.card_type = CardData.CardType.ACTIVE
	charge_slash.cost = 2
	charge_slash.effect_type = CardData.EffectType.ATTACK
	charge_slash.damage = 45.0
	charge_slash.description = "기를 모아 45 데미지"
	charge_slash.element = CardData.Element.FIRE

	var fire_burst := CardData.new()
	fire_burst.card_name = "화염 폭발"
	fire_burst.card_type = CardData.CardType.ACTIVE
	fire_burst.cost = 3
	fire_burst.effect_type = CardData.EffectType.ATTACK
	fire_burst.damage = 70.0
	fire_burst.description = "화염 폭발 70 데미지 (범위)"
	fire_burst.element = CardData.Element.FIRE

	var draw_effect := CardData.new()
	draw_effect.card_name = "드로우"
	draw_effect.card_type = CardData.CardType.ACTIVE
	draw_effect.cost = 1
	draw_effect.effect_type = CardData.EffectType.DRAW
	draw_effect.description = "카드 2장을 추가로 뽑는다"

	var heal_card := CardData.new()
	heal_card.card_name = "응급 처치"
	heal_card.card_type = CardData.CardType.ACTIVE
	heal_card.cost = 2
	heal_card.effect_type = CardData.EffectType.HEAL
	heal_card.damage = 30.0
	heal_card.description = "HP 30 회복"

	# 15장 덱 구성
	for i in 4: cards_to_add.append(slash.duplicate())
	for i in 3: cards_to_add.append(charge_slash.duplicate())
	for i in 2: cards_to_add.append(fire_burst.duplicate())
	for i in 4: cards_to_add.append(draw_effect.duplicate())
	for i in 2: cards_to_add.append(heal_card.duplicate())

	deck = cards_to_add
	shuffle_deck()

	# 초기 손패 3장
	for i in 3:
		draw_card()

# ── 코어 함수 ────────────────────────────────────────────────────
func shuffle_deck() -> void:
	deck.shuffle()

func draw_card() -> void:
	if hand.size() >= MAX_HAND:
		# 손패 꽉 참 → 뽑은 카드 버리기
		if deck.size() > 0:
			discard_pile.append(deck.pop_front())
		return

	if deck.size() == 0:
		if discard_pile.is_empty():
			return
		# 버린 카드 다시 섞기
		deck = discard_pile.duplicate()
		discard_pile.clear()
		shuffle_deck()

	hand.append(deck.pop_front())
	hand_changed.emit()

func add_cost(amount: int) -> void:
	current_cost = mini(current_cost + amount, MAX_COST)
	cost_changed.emit(current_cost)

func use_card(card: CardData) -> bool:
	if card.cost > current_cost:
		return false
	if not hand.has(card):
		return false

	hand.erase(card)
	discard_pile.append(card)
	current_cost -= card.cost
	cost_changed.emit(current_cost)
	hand_changed.emit()

	if card.effect_type == CardData.EffectType.DRAW:
		draw_card()
		draw_card()

	return true

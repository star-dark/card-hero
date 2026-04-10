class_name CardData
extends Resource

enum CardType { WEAPON, PASSIVE, ACTIVE }
enum Rarity { COMMON, RARE, UNIQUE, LEGENDARY }
enum Element { NONE, FIRE, GRASS, EARTH, ELECTRIC, WATER }
enum EffectType { ATTACK, BUFF, DEBUFF, TERRAIN, AUGMENT, DRAW, SPECIAL, HEAL }

@export var card_name: String = ""
@export var card_type: CardType = CardType.ACTIVE
@export var rarity: Rarity = Rarity.COMMON
@export var cost: int = 1
@export var element: Element = Element.NONE
@export var effect_type: EffectType = EffectType.ATTACK
@export var description: String = ""
@export var damage: float = 0.0
@export var duration: float = 0.0
@export var illustration: Texture2D = null

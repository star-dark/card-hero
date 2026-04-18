class_name HealthComponent
extends Node

signal health_changed(current_hp: int, max_hp: int)
signal damaged(amount: int)
signal died

@export var max_health: int = 100
var current_health: int = 100

func _ready() -> void:
	current_health = max_health

func take_damage(amount: int) -> void:
	if current_health <= 0:
		return
	current_health = maxi(0, current_health - amount)
	damaged.emit(amount)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()

func heal(amount: int) -> void:
	current_health = mini(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func get_health_percent() -> float:
	return float(current_health) / float(max_health)

extends Node2D

@export var can_owner_deploy: bool = false
@export var can_enemy_deploy: bool = false

var card_in_slot = false

func _ready() -> void:
	$EnemyIndicator.visible = can_enemy_deploy
	$OwnerIndicator.visible = can_owner_deploy

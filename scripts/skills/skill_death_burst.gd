extends SkillEffect
class_name SkillDeathBurst

# On removal: fires a projectile dealing `damage` HP to a random enemy.
# Trigger: "remove"

@export var damage: int = 3

func execute(card, resolver) -> void:
	var enemies: Array = []
	for fc in resolver.field_cards:
		if is_instance_valid(fc) and fc.is_owner_card != card.is_owner_card:
			enemies.append(fc)
	if enemies.is_empty():
		return
	var target = enemies[randi() % enemies.size()]
	var from_pos: Vector2 = card.global_position
	print("[Skill] death_burst → %s (-%d HP)" % [target.card_data.get("name", "?"), damage])
	resolver.add_pause(1.2)
	_launch_projectile(from_pos, target, damage, resolver)

func _launch_projectile(from_pos: Vector2, target, damage: int, resolver) -> void:
	var proj := Node2D.new()
	var rect := ColorRect.new()
	rect.size = Vector2(20.0, 12.0)
	rect.position = Vector2(-10.0, -6.0)
	rect.color = Color(1.0, 0.3, 0.1, 0.9)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	proj.add_child(rect)
	proj.z_index = 20
	resolver.spawn_child(proj)
	proj.global_position = from_pos
	var tween = resolver.make_tween()
	tween.tween_property(proj, "global_position", target.global_position, 1.0)
	tween.tween_callback(func() -> void:
		if is_instance_valid(target):
			resolver.apply_damage(target, damage)
		proj.queue_free()
	)

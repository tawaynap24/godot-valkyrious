extends SkillEffect
class_name SkillStunEnemy

# Stuns a random enemy card on the field for 3 seconds.
# Trigger: "attack"

func execute(card, resolver) -> void:
	var enemies: Array = []
	for fc in resolver.field_cards:
		if is_instance_valid(fc) and fc.is_owner_card != card.is_owner_card:
			enemies.append(fc)
	if enemies.is_empty():
		return
	var target = enemies[randi() % enemies.size()]
	print("[Skill] stun_enemy → %s (3s stun)" % target.card_data.get("name", "?"))
	target.set_stun(3.0)

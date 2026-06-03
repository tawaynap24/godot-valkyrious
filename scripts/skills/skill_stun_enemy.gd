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
	var skill_lvl = card.card_data.get("skill_level", 1)
	var skill_values = card.card_data.get("skill_level_values", [])
	var duration = 3.0
	if not skill_values.is_empty():
		var idx = clamp(skill_lvl - 1, 0, skill_values.size() - 1)
		duration = float(skill_values[idx])
	var target = enemies[randi() % enemies.size()]
	print("[Skill] stun_enemy → %s (%.1fs stun)" % [target.card_data.get("name", "?"), duration])
	target.set_stun(duration)

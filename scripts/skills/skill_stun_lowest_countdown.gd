extends SkillEffect
class_name SkillStunLowestCountdown

# Stuns the enemy card with the lowest field_countdown for 4 seconds.
# Trigger: "place"

func execute(card, resolver) -> void:
	var best_target = null
	var lowest: float = INF
	for fc in resolver.field_cards:
		if is_instance_valid(fc) and fc.is_owner_card != card.is_owner_card:
			if fc.field_countdown < lowest:
				lowest = fc.field_countdown
				best_target = fc
	if best_target != null:
		var skill_lvl = card.card_data.get("skill_level", 1)
		var skill_values = card.card_data.get("skill_level_values", [])
		var duration = 4.0
		if not skill_values.is_empty():
			var idx = clamp(skill_lvl - 1, 0, skill_values.size() - 1)
			duration = float(skill_values[idx])
		print("[Skill] stun_lowest_countdown → %s (%.1fs stun)" % [best_target.card_data.get("name", "?"), duration])
		best_target.set_stun(duration)

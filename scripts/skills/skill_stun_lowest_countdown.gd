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
		print("[Skill] stun_lowest_countdown → %s (4s stun)" % best_target.card_data.get("name", "?"))
		best_target.set_stun(4.0)

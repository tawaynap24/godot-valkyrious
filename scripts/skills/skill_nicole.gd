extends SkillEffect
class_name SkillNicole

# Grants a barrier to the ally directly in front of Nicole on place.
# Trigger: "place"

func execute(card, resolver) -> void:
	var front_row = card.row_index - 1 if card.is_owner_card else card.row_index + 1
	var target_col = card.col_index
	
	# Find ally card on the field at (front_row, target_col)
	var ally = null
	for fc in resolver.field_cards:
		if is_instance_valid(fc) and fc.is_owner_card == card.is_owner_card:
			if fc.row_index == front_row and fc.col_index == target_col:
				ally = fc
				break
				
	if ally != null:
		print("[Skill] Nicole → Granting barrier to front ally: %s" % ally.card_data.get("name", "?"))
		ally.set_barrier(true)

extends Node2D

signal left_mouse_button_clicked
signal left_mouse_button_released
signal card_pressed(card)

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_DESK = 4

var deck_reference

# Last known pointer position (mouse or first-touch) used by CardManager drag
var pointer_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	deck_reference = $"../Deck"

func _input(event):
	# ── Mouse (PC) ────────────────────────────────────────────────────────────
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer_position = event.position
		if event.pressed:
			emit_signal("left_mouse_button_clicked")
			_raycast_at(pointer_position)
		else:
			emit_signal("left_mouse_button_released")
	elif event is InputEventMouseMotion:
		pointer_position = event.position

	# ── Touch (Mobile) ────────────────────────────────────────────────────────
	elif event is InputEventScreenTouch and event.index == 0:
		pointer_position = event.position
		if event.pressed:
			emit_signal("left_mouse_button_clicked")
			_raycast_at(pointer_position)
		else:
			emit_signal("left_mouse_button_released")
	elif event is InputEventScreenDrag and event.index == 0:
		pointer_position = event.position

func _raycast_at(pos: Vector2) -> void:
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = pos
	parameters.collide_with_areas = true
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		var result_collision_mask = result[0].collider.collision_mask
		if result_collision_mask == COLLISION_MASK_CARD:
			var card_found = result[0].collider.get_parent()
			if card_found:
				emit_signal("card_pressed", card_found)
		elif result_collision_mask == COLLISION_MASK_DESK:
			deck_reference.draw_card()

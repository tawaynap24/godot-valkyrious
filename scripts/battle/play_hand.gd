extends Node2D

const HAND_SIZE = 4
const CARD_WIDTH = 95
const HAND_Y_POSITION = 810
const DEFAULT_CARD_MOVE_SPEED = 0.1

var hand_slots = [null, null, null, null]
var center_screen_x

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2

func get_slot_position(index: int) -> Vector2:
	var total_width = (HAND_SIZE - 1) * CARD_WIDTH
	var x = center_screen_x + index * CARD_WIDTH - total_width / 2.0
	return Vector2(x, HAND_Y_POSITION)

func add_card_to_hand(card, speed):
	card.scale = Vector2(1.2, 1.2)
	# Card already in a slot — animate back to its position
	for i in range(HAND_SIZE):
		if hand_slots[i] == card:
			animate_card_to_position(card, get_slot_position(i), speed)
			return
	# Find first empty slot
	for i in range(HAND_SIZE):
		if hand_slots[i] == null:
			hand_slots[i] = card
			card.starting_position = get_slot_position(i)
			animate_card_to_position(card, card.starting_position, speed)
			return

func remove_card_from_hand(card):
	for i in range(HAND_SIZE):
		if hand_slots[i] == card:
			hand_slots[i] = null
			return

func animate_card_to_position(card, new_position, speed):
	card.position = new_position

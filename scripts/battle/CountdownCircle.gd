extends Node2D

const RADIUS: float = 21.0
const TRACK_WIDTH: float = 4.5
const SEGMENTS: int = 64
const TRACK_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.40)
const ARC_COLOR: Color = Color(1.0, 0.85, 0.25, 0.95)
const FILL_COLOR: Color = Color(0.0, 0.0, 0.0, 0.50)

var _max_value: float = 8.0
var _current_value: float = 8.0

func set_max(max_val: float) -> void:
	_max_value = max_val
	_current_value = max_val
	queue_redraw()

func update_display(value: float) -> void:
	_current_value = value
	queue_redraw()

func _draw() -> void:
	# Dark semi-transparent background circle
	draw_circle(Vector2.ZERO, RADIUS + TRACK_WIDTH * 0.5, FILL_COLOR)

	# Grey ring track (full circle underneath)
	draw_arc(Vector2.ZERO, RADIUS, -PI / 2.0, -PI / 2.0 + TAU, SEGMENTS, TRACK_BG_COLOR, TRACK_WIDTH)

	# Remaining time arc — gold, clockwise from 12 o'clock, shrinks as time runs out
	var ratio: float = clamp(_current_value / _max_value, 0.0, 1.0)
	if ratio > 0.005:
		var end_angle: float = -PI / 2.0 + ratio * TAU
		draw_arc(Vector2.ZERO, RADIUS, -PI / 2.0, end_angle, SEGMENTS, ARC_COLOR, TRACK_WIDTH, true)

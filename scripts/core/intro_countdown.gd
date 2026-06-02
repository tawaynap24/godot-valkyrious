extends Node2D

const STEP_DURATION: float = 1.0
const STEPS: Array = ["3", "2", "1", "READY!"]

var _step: int = 0
var _timer: float = 0.0

func _ready() -> void:
	$CountdownLabel.text = STEPS[0]

func _process(delta: float) -> void:
	_timer += delta
	if _timer < STEP_DURATION:
		return
	_timer -= STEP_DURATION
	_step += 1
	if _step >= STEPS.size():
		visible = false
		get_parent().start_game()
		set_process(false)
	else:
		$CountdownLabel.text = STEPS[_step]

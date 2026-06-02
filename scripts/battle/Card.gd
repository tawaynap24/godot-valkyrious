extends Node2D

signal hovered
signal hovered_off

var starting_position
var card_data = {}

# Field state
var is_on_field = false
var field_countdown = 0.0
var move_countdown: float = 8.0       # time between consecutive actions
var capture_duration: float = 4.0     # time to capture a slot
var delay_place: float = 0.0          # global pause on place
var delay_attack: float = 0.5         # global pause on attack
var delay_move: float = 0.5           # global pause on move
var row_index = -1
var col_index = -1
var is_owner_card = true
var current_hp = 0
var current_atk = 0
var barrier: bool = false
var capture_timer: float = 0.0
var locked_target = null   # holds the Node2D this card has committed to attack
var stun_remaining: float = 0.0  # seconds of stun left; 0 = not stunned

func set_stun(duration: float) -> void:
	stun_remaining = duration
	$StunOverlay.visible = duration > 0.0

func setup(data: Dictionary) -> void:
	card_data = data
	$CostLabel.text = str(data.cost)
	$ATKLabel.text = str(data.atk)
	$HPLabel.text = str(data.hp)
	$NameLabel.text = data.name
	$LevelLabel.text = "Lv" + str(data.level)
	if data.get("has_image", false):
		var img_path: String = data.get("image_path", "")
		var tex = GameCache.get_texture(img_path)
		if tex != null:
			$CardImage.texture = tex
			# Scale image to fill full card frame (71×117) — Sprite2D is centered
			var tex_size: Vector2 = tex.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				var scale_x: float = 98.0 / tex_size.x
				var scale_y: float = 158.0 / tex_size.y
				$CardImage.scale = Vector2(scale_x, scale_y)
			$CardImage.position = Vector2(0.0, 0.0)
			$CardImage.visible = true
			$CardBg.visible = false
		else:
			$CardImage.visible = false
			$CardBg.color = data.get("bg_color", Color(0.15, 0.15, 0.35, 1.0))
	else:
		$CardImage.visible = false
		$CardBg.color = data.get("bg_color", Color(0.15, 0.15, 0.35, 1.0))
	# Apply time_delay values from card data
	var td: Dictionary = data.get("time_delay", {})
	delay_place       = td.get("place",            0.0)
	delay_attack      = td.get("attack",           0.5)
	delay_move        = td.get("move",             0.5)
	move_countdown    = td.get("move_countdown",   8.0)
	capture_duration  = td.get("capture_duration", 4.0)
	# Barrier — visual initialised here; actual value reset by CardManager on deploy
	barrier = data.get("has_barrier", false)
	_update_barrier_visual()

func set_barrier(value: bool) -> void:
	barrier = value
	_update_barrier_visual()

func _update_barrier_visual() -> void:
	$BarrierOverlay.visible = barrier

func update_stun_timer(delta: float) -> void:
	if stun_remaining > 0.0:
		stun_remaining -= delta
		if stun_remaining <= 0.0:
			stun_remaining = 0.0
			$StunOverlay.visible = false

func update_countdown_display(value: float) -> void:
	$CountdownCircle.visible = true
	$CountdownCircle.update_display(value)

func set_field_border(is_owner: bool) -> void:
	if is_owner:
		$CardBorder.color = Color(0.2, 0.55, 1.0, 0.85)
	else:
		$CardBorder.color = Color(1.0, 0.2, 0.25, 0.85)

# dir: "U" "D" "L" "R" or "" to hide
# Arrow is placed at the corresponding edge of the card
func set_attack_arrow(dir: String) -> void:
	var arrow_map = {"U": "↑", "D": "↓", "L": "←", "R": "→"}
	var label = $ArrowLabel
	if dir == "" or not arrow_map.has(dir):
		label.visible = false
		return
	label.text = arrow_map[dir]
	label.visible = true
	# Reposition to the matching edge (card body: ±35.5 x, ±58.5 y)
	match dir:
		"U":
			label.offset_left   = -20.0
			label.offset_top    = -74.0
			label.offset_right  =  20.0
			label.offset_bottom = -44.0
		"D":
			label.offset_left   = -20.0
			label.offset_top    =  44.0
			label.offset_right  =  20.0
			label.offset_bottom =  74.0
		"L":
			label.offset_left   = -66.0
			label.offset_top    = -15.0
			label.offset_right  = -36.0
			label.offset_bottom =  15.0
		"R":
			label.offset_left   =  36.0
			label.offset_top    = -15.0
			label.offset_right  =  66.0
			label.offset_bottom =  15.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered",self)


func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off",self)

extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
# GachaScreen — Gacha pull UI (x1 / x10).
# Layout is defined in scenes/Gacha.tscn; result cards are built procedurally.
#
# Rarity tiers: 0=Bronze  1=Silver  2=Gold
# Display constants live in CardDatabase (RARITY_NAMES, RARITY_COLORS, RARITY_BG)
# ─────────────────────────────────────────────────────────────────────────────

# ── Gacha economy ──────────────────────────────────────────────────────────────
const GACHA_COST_X1: int  = 1
const GACHA_COST_X10: int = 10

# ── Gacha odds (Bronze 70% | Silver 25% | Gold 5%) ────────────────────────────
const ODDS_GOLD:   float = 5.0
const ODDS_SILVER: float = 25.0  # cumulative threshold: 30%

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	$TopBar/BackButton.pressed.connect(_on_back)
	$PullX1Btn.pressed.connect(_on_pull.bind(1))
	$PullX10Btn.pressed.connect(_on_pull.bind(10))
	$ResultOverlay/ResultPanel/CloseBtn.pressed.connect(_on_close_result)
	$ResultOverlay.visible = false
	$InsufficientLabel.visible = false
	_refresh_ui()
	UIShell.refresh_coins()
	UIShell.set_active_tab("gacha")

func _on_back() -> void:
	SceneManager.go_to_lobby()

# ── Pull logic

func _refresh_ui() -> void:
	var coins: int = SaveManager.get_coins()
	$PullX1Btn.disabled  = coins < GACHA_COST_X1
	$PullX10Btn.disabled = coins < GACHA_COST_X10
	var coins_lbl = $TopBar.get_node_or_null("CoinsLabel")
	if coins_lbl:
		coins_lbl.text = "💰 " + str(coins)

# ── Pull logic ───────────────────────────────────────────────────────────────────

func _on_pull(count: int) -> void:
	var results: Array = _do_pull(count)
	if results.is_empty():
		$InsufficientLabel.visible = true
		await get_tree().create_timer(1.5).timeout
		$InsufficientLabel.visible = false
		return
	_refresh_ui()
	UIShell.refresh_coins()
	_show_results(results)

## Deducts coins, rolls `count` cards, returns result dicts.
## Returns empty Array if coins are insufficient.
func _do_pull(count: int) -> Array:
	var cost := GACHA_COST_X1 if count == 1 else GACHA_COST_X10
	if SaveManager.get_coins() < cost:
		return []
	SaveManager.add_coins(-cost)
	var results: Array = []
	for i in range(count):
		results.append(_pull_one())
	return results

## Rolls a single card, marks it owned, returns a result dict.
func _pull_one() -> Dictionary:
	# Determine rarity tier from weighted odds
	var roll := randf() * 100.0
	var tier: int
	if roll < ODDS_GOLD:
		tier = 2  # Gold
	elif roll < ODDS_GOLD + ODDS_SILVER:
		tier = 1  # Silver
	else:
		tier = 0  # Bronze
	# Build pool for this tier
	var pool: Array = []
	for cid in CardDatabase.CARDS:
		if CardDatabase.CARDS[cid].get("rarity", 0) == tier:
			pool.append(cid)
	if pool.is_empty():
		pool = CardDatabase.CARDS.keys()
	var picked: String = pool[randi() % pool.size()]
	var is_new: bool = not SaveManager.has_owned_card(picked)
	SaveManager.own_card(picked)
	var cdata: Dictionary = CardDatabase.CARDS.get(picked, {})
	return {
		"card_id":    picked,
		"name":       cdata.get("name", picked),
		"rarity":     tier,
		"is_new":     is_new,
		"bg_color":   cdata.get("bg_color", Color(0.15, 0.15, 0.35, 1.0)),
		"has_image":  cdata.get("has_image", false),
		"image_path": cdata.get("image_path", ""),
	}

# ── Result overlay ────────────────────────────────────────────────────────────

func _show_results(results: Array) -> void:
	var container: Control = $ResultOverlay/ResultPanel/CardsContainer
	for child in container.get_children():
		child.queue_free()

	if results.size() == 1:
		_add_card(container, results[0], Vector2(122.0, 10.0), Vector2(200.0, 280.0))
	else:
		# x10 — 2 rows × 5 cols
		const CARD_W := 94.0
		const CARD_H := 128.0
		const GAP_X  := 7.0
		const GAP_Y  := 10.0
		var total_w: float = 5.0 * CARD_W + 4.0 * GAP_X
		var start_x: float = (544.0 - total_w) * 0.5
		for i in range(results.size()):
			var col: int = i % 5
			var row: int = i / 5
			var pos := Vector2(start_x + col * (CARD_W + GAP_X), 6.0 + row * (CARD_H + GAP_Y))
			_add_card(container, results[i], pos, Vector2(CARD_W, CARD_H))

	$ResultOverlay.visible = true

func _add_card(parent: Control, result: Dictionary, pos: Vector2, sz: Vector2) -> void:
	var rarity: int = result.get("rarity", 0)
	var is_new: bool = result.get("is_new", false)

	var card := Control.new()
	card.position = pos
	card.custom_minimum_size = sz
	parent.add_child(card)

	# Rarity-coloured border panel
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = CardDatabase.RARITY_BG[rarity]
	sbf.set_corner_radius_all(8)
	sbf.border_width_top    = 3
	sbf.border_width_bottom = 3
	sbf.border_width_left   = 3
	sbf.border_width_right  = 3
	sbf.border_color = CardDatabase.RARITY_COLORS[rarity]
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", sbf)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	# Character artwork
	if result.get("has_image", false):
		var tex := GameCache.get_texture(result.get("image_path", ""))
		if tex:
			var art := TextureRect.new()
			art.texture = tex
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(art)

	# Name bar
	var bar_h: float = 40.0 if sz.y > 100.0 else 30.0
	var name_bar := ColorRect.new()
	name_bar.color = Color(0, 0, 0, 0.68)
	name_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_bar.offset_top = -bar_h
	name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_bar)

	var font_sz: int = 12 if sz.y > 100.0 else 10
	var name_lbl := Label.new()
	name_lbl.text = result.get("name", "?")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_lbl.offset_top = -bar_h
	name_lbl.add_theme_font_size_override("font_size", font_sz)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	# NEW badge
	if is_new:
		var new_lbl := Label.new()
		new_lbl.text = "NEW!"
		new_lbl.position = Vector2(3.0, 2.0)
		new_lbl.add_theme_font_size_override("font_size", 10)
		new_lbl.add_theme_color_override("font_color", Color(0.18, 1.0, 0.32, 1.0))
		new_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		new_lbl.add_theme_constant_override("shadow_offset_x", 1)
		new_lbl.add_theme_constant_override("shadow_offset_y", 1)
		new_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(new_lbl)

	# Rarity tag (top-right)
	var tag_lbl := Label.new()
	tag_lbl.text = CardDatabase.RARITY_NAMES[rarity]
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tag_lbl.offset_left  = -54.0
	tag_lbl.offset_bottom = 16.0
	tag_lbl.add_theme_font_size_override("font_size", 9)
	tag_lbl.add_theme_color_override("font_color", CardDatabase.RARITY_COLORS[rarity])
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tag_lbl)

func _on_close_result() -> void:
	$ResultOverlay.visible = false
	_refresh_ui()

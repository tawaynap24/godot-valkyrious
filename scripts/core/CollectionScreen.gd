extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
# CollectionScreen — read-only character encyclopaedia.
# Shows ALL characters from CardDatabase, regardless of ownership.
# No upgrade functionality — this is purely an info viewer.
# Rarity display: CardDatabase.RARITY_NAMES / RARITY_COLORS / RARITY_BG
# ─────────────────────────────────────────────────────────────────────────────

var _filter_rarity: int = -1
var _grid_built: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	$TopBar/BackButton.pressed.connect(_on_back)
	$DetailOverlay/CloseBtn.pressed.connect(_on_close_detail)
	$DetailOverlay/Dim.gui_input.connect(_on_dim_input)
	var upbtn = $DetailOverlay/CardPanel.get_node_or_null("UpgradeBtn")
	if upbtn:
		upbtn.visible = false
	_build_filter_bar()
	_build_collection_grid()
	UIShell.set_active_tab("collection")

func _on_back() -> void:
	SceneManager.go_to_lobby()

# ── Filter Bar ────────────────────────────────────────────────────────────────

func _build_filter_bar() -> void:
	var bar: HBoxContainer = $FilterBar
	_add_filter_btn(bar, "ทั้งหมด", -1)
	for i in range(CardDatabase.RARITY_NAMES.size()):
		_add_filter_btn(bar, CardDatabase.RARITY_NAMES[i], i)

func _add_filter_btn(bar: HBoxContainer, label: String, rarity: int) -> void:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = Color(0.60, 0.82, 0.98, 1.0)
	sbf.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sbf)
	var sbf_h := sbf.duplicate() as StyleBoxFlat
	sbf_h.bg_color = Color(0.18, 0.55, 0.95, 1.0)
	btn.add_theme_stylebox_override("hover", sbf_h)
	btn.add_theme_stylebox_override("pressed", sbf_h)
	btn.add_theme_color_override("font_color", Color(0.06, 0.18, 0.45, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.pressed.connect(func():
		_filter_rarity = rarity
		_apply_filter()
	)
	bar.add_child(btn)

# ── Collection Grid — shows ALL characters ────────────────────────────────────

func _build_collection_grid() -> void:
	var grid: GridContainer = $CollectionScroll/CollectionGrid
	if not _grid_built:
		_grid_built = true
		var card_ids: Array = CardDatabase.CARDS.keys()
		card_ids.sort()
		for card_id in card_ids:
			var data: Dictionary = CardDatabase.CARDS.get(card_id, {})
			if data.is_empty():
				continue
			var btn: Button = _add_card_button(grid, card_id, data)
			btn.set_meta("card_rarity", data.get("rarity", 0))
	_apply_filter()

func _apply_filter() -> void:
	var grid: GridContainer = $CollectionScroll/CollectionGrid
	var visible_count := 0
	for child in grid.get_children():
		if child is Button:
			var rarity: int = child.get_meta("card_rarity", -1)
			var show: bool = _filter_rarity == -1 or rarity == _filter_rarity
			child.visible = show
			if show:
				visible_count += 1
	var empty_lbl: Label = grid.get_node_or_null("EmptyLabel")
	if visible_count == 0:
		if empty_lbl == null:
			empty_lbl = Label.new()
			empty_lbl.name = "EmptyLabel"
			empty_lbl.text = "ไม่มีตัวละครที่ตรงกับตัวกรองนี้"
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.65, 1.0))
			empty_lbl.add_theme_font_size_override("font_size", 14)
			grid.add_child(empty_lbl)
		empty_lbl.visible = true
	else:
		if empty_lbl:
			empty_lbl.visible = false

func _add_card_button(grid: GridContainer, card_id: String, data: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(136, 190)
	btn.clip_contents = true
	var rarity: int = clampi(data.get("rarity", 0), 0, CardDatabase.RARITY_COLORS.size() - 1)
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = data.get("bg_color", Color(0.12, 0.10, 0.22, 1.0))
	sbf.set_corner_radius_all(6)
	sbf.border_width_bottom = 3
	sbf.border_width_top = 1
	sbf.border_color = CardDatabase.RARITY_COLORS[rarity]
	btn.add_theme_stylebox_override("normal", sbf)
	var sbf_h := sbf.duplicate() as StyleBoxFlat
	sbf_h.border_color = Color(0.9, 0.9, 1.0, 1.0)
	sbf_h.border_width_bottom = 3
	btn.add_theme_stylebox_override("hover", sbf_h)
	btn.add_theme_stylebox_override("pressed", sbf_h)
	if data.get("has_image", false):
		var tex := _try_load_texture(data.get("image_path", ""))
		if tex:
			var art := TextureRect.new()
			art.texture = tex
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(art)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.58)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -52.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(bar)
	var lbl := Label.new()
	var display_name: String = data.get("name", card_id)
	lbl.text = (display_name + "\n"
		+ "⚔" + str(data.get("atk", "?"))
		+ " ❤" + str(data.get("hp", "?"))
		+ " 💰" + str(data.get("cost", "?")))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	lbl.offset_top = -52.0
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)
	btn.pressed.connect(_on_card_pressed.bind(card_id))
	grid.add_child(btn)
	return btn

func _try_load_texture(path: String) -> Texture2D:
	return GameCache.get_texture(path)

# ── Card Detail Overlay ───────────────────────────────────────────────────────

func _on_card_pressed(card_id: String) -> void:
	var data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	if data.is_empty():
		return
	_show_detail(data)

func _show_detail(data: Dictionary) -> void:
	UIShell.hide_shell()
	var rarity: int = clampi(data.get("rarity", 0), 0, CardDatabase.RARITY_COLORS.size() - 1)
	var img: TextureRect = $DetailOverlay/CardPanel/ArtworkRect
	if data.get("has_image", false):
		var tex := _try_load_texture(data.get("image_path", ""))
		if tex:
			img.texture = tex
			img.visible = true
		else:
			img.visible = false
	else:
		img.visible = false
	$DetailOverlay/CardPanel/NameLabel.text = data.get("name", "")
	var r_lbl: Label = $DetailOverlay/CardPanel/RarityLabel
	r_lbl.text = "◆  " + CardDatabase.RARITY_NAMES[rarity]
	r_lbl.add_theme_color_override("font_color", CardDatabase.RARITY_COLORS[rarity])
	$DetailOverlay/CardPanel/StatsLabel.text = (
		"⚔ ATK  " + str(data.get("atk", "?"))
		+ "    ❤ HP  " + str(data.get("hp", "?"))
		+ "    💰 Cost  " + str(data.get("cost", "?"))
	)
	var desc: String = data.get("description", "")
	$DetailOverlay/CardPanel/DescLabel.text = desc if desc != "" else "ยังไม่มีคำอธิบาย"
	var skills: Array = data.get("skills", [])
	var skills_text: String = "—"
	if not skills.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		for s in skills:
			parts.append(str(s))
		skills_text = "  •  ".join(parts)
	$DetailOverlay/CardPanel/SkillsLabel.text = "Skills:  " + skills_text
	$DetailOverlay.visible = true

func _on_close_detail() -> void:
	$DetailOverlay.visible = false
	UIShell.show_shell()

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_close_detail()
	elif event is InputEventScreenTouch and event.pressed:
		_on_close_detail()

extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
# DeckBuilderScreen — Deck Builder UI
#
# Features:
#   • 3 deck presets with save/load via SaveManager
#   • Deck slots show artwork + name + cost
#   • Collection shows all owned cards; "In Deck" badge + disabled tap for dupes
#   • Press-and-hold (0.5 s) on any collection card opens a detail popup
#   • Duplicate prevention with feedback message
#   • White / sky-blue theme
#
# Node layout (DeckBuilder.tscn):
#   TopBar / BackButton, TitleLabel
#   DeckSelectorBar / Deck1Btn, Deck2Btn, Deck3Btn
#   ActionBar / SetActiveBtn, SaveBtn, CancelBtn
#   DeckGrid (GridContainer) — 8 DeckSlotX children, each has:
#       ArtworkRect (TextureRect), CardLabel (Label)
#   Divider (ColorRect), CollectionLabel (Label)
#   CollectionScroll / CollectionGrid (GridContainer)
#   HoldTimer (Timer, one_shot = true, wait_time = 0.5)
#   DetailOverlay (Control, visible=false) / Dim, CardPanel / ArtworkRect,
#       NameLabel, RarityLabel, StatsLabel, DescLabel, SkillsLabel, CloseBtn
# ─────────────────────────────────────────────────────────────────────────────

const DECK_SIZE: int = 8

# Rarity display: use CardDatabase.RARITY_NAMES and CardDatabase.RARITY_COLORS

# Theme palette — edit here to repaint everything
const C_BTN_ACTIVE    := Color(0.12, 0.48, 0.92, 1.0)   # selected deck tab
const C_BTN_INACTIVE  := Color(0.72, 0.85, 0.98, 1.0)   # unselected deck tab
const C_SLOT_EMPTY    := Color(0.95, 0.97, 1.00, 1.0)   # empty slot bg
const C_SLOT_FILLED   := Color(0.82, 0.92, 1.00, 1.0)   # filled slot bg
const C_BORDER_EMPTY  := Color(0.72, 0.84, 0.96, 1.0)
const C_BORDER_FILLED := Color(0.15, 0.52, 0.95, 1.0)
const C_BORDER_HOVER  := Color(0.05, 0.72, 0.92, 1.0)   # cyan hover in collection
const C_BORDER_INDECK := Color(0.05, 0.78, 0.55, 1.0)   # teal "in deck" ring
const C_TEXT_DARK     := Color(0.08, 0.14, 0.35, 1.0)   # dark navy text
const C_TEXT_MUTED    := Color(0.45, 0.55, 0.70, 1.0)   # muted slot empty text

var _current_index: int = 1
var _working_deck: Array[String] = []

# Hold-to-detail state
var _held_card_id: String = ""
var _held_button_index: int = -1
var _hold_press_pos: Vector2 = Vector2.ZERO
var _hold_triggered: bool = false
const HOLD_DRAG_THRESHOLD: float = 10.0



# Maps index (int) → Button node in the collection grid so we can refresh
# highlights without destroying and recreating all nodes
var _collection_btn_map: Dictionary = {}
var _sorted_owned_cards: Array[String] = []
var _detail_card_id: String = ""


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_connect_signals()
	_current_index = SaveManager.get_active_index()
	
	# Populate _sorted_owned_cards first, since _load_working_deck requires it
	var owned: Array[String] = SaveManager.get_owned_cards()
	_sorted_owned_cards = owned.duplicate()
	_sorted_owned_cards.sort()
	
	_load_working_deck()
	_build_collection_grid()
	_refresh_deck_ui()
	_refresh_selector_buttons()
	_refresh_action_bar()
	UIShell.set_active_tab("deck")

# ── Signal Wiring ─────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	$TopBar/BackButton.pressed.connect(_on_back)
	$DeckSelectorBar/Deck1Btn.pressed.connect(func(): _switch_preset(1))
	$DeckSelectorBar/Deck2Btn.pressed.connect(func(): _switch_preset(2))
	$DeckSelectorBar/Deck3Btn.pressed.connect(func(): _switch_preset(3))
	$ActionBar/SetActiveBtn.pressed.connect(_on_set_active)
	$ActionBar/SaveBtn.pressed.connect(_on_save)
	$ActionBar/CancelBtn.pressed.connect(_on_cancel_edit)
	$HoldTimer.timeout.connect(_on_hold_complete)
	$DetailOverlay/CloseBtn.pressed.connect(_on_close_detail)
	$DetailOverlay/CardPanel/UpgradeBtn.pressed.connect(_on_upgrade_pressed)
	# Tap outside detail overlay (on Dim) to close
	$DetailOverlay/Dim.gui_input.connect(_on_dim_input)
	# Deck slot tap-to-remove
	var _dg: GridContainer = $DeckGrid
	for _i in range(DECK_SIZE):
		_dg.get_child(_i).gui_input.connect(_on_deck_slot_input.bind(_i))

# ── Preset Switching ──────────────────────────────────────────────────────────

func _switch_preset(index: int) -> void:
	_current_index = index
	_load_working_deck()
	_refresh_deck_ui()
	_refresh_selector_buttons()
	_refresh_action_bar()
	_refresh_collection_highlights()   # resync in-deck highlights without rebuild

func _load_working_deck() -> void:
	var saved_deck = SaveManager.get_deck(_current_index)
	_working_deck.clear()
	
	var used_indices := {}
	for card_id in saved_deck:
		var found_idx := -1
		for idx in range(_sorted_owned_cards.size()):
			if _sorted_owned_cards[idx] == card_id and not used_indices.has(idx):
				found_idx = idx
				break
		if found_idx != -1:
			_working_deck.append(str(found_idx))
			used_indices[found_idx] = true

# ── Deck Grid (8 slots) ───────────────────────────────────────────────────────

func _refresh_deck_ui() -> void:
	var grid: GridContainer = $DeckGrid

	# Build slot StyleBoxes once
	var sbf_empty := StyleBoxFlat.new()
	sbf_empty.bg_color = C_SLOT_EMPTY
	sbf_empty.set_corner_radius_all(6)
	sbf_empty.border_width_bottom = 2
	sbf_empty.border_color = C_BORDER_EMPTY

	var sbf_filled := StyleBoxFlat.new()
	sbf_filled.bg_color = Color(1.0, 1.0, 1.0, 1.0)   # white
	sbf_filled.set_corner_radius_all(6)
	sbf_filled.border_width_top    = 2
	sbf_filled.border_width_left   = 2
	sbf_filled.border_width_right  = 2
	sbf_filled.border_width_bottom = 2
	sbf_filled.border_color = Color(0.0, 0.0, 0.0, 1.0)  # black

	for i in range(DECK_SIZE):
		var slot: Panel = grid.get_child(i)
		var lbl: Label       = slot.get_node("CardLabel")
		var art: TextureRect = slot.get_node("ArtworkRect")
		if i < _working_deck.size():
			var idx_str: String = _working_deck[i]
			var idx: int = int(idx_str)
			var card_id: String = _sorted_owned_cards[idx]
			var card_data: Dictionary = CardDatabase.CARDS.get(card_id, {})

			# Artwork — top 148px of 180px slot, leaving 32px name strip below
			var _has_art: bool = false
			if card_data.get("has_image", false):
				var tex := _try_load_texture(card_data.get("image_path", ""))
				if tex:
					art.texture = tex
					art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
					art.anchor_left = 0.0; art.anchor_top = 0.0
					art.anchor_right = 1.0; art.anchor_bottom = 0.0
					art.offset_left = 0.0; art.offset_top = 0.0
					art.offset_right = 0.0; art.offset_bottom = 148.0
					art.visible = true
					_has_art = true
			if not _has_art:
				art.texture = null
				art.visible = false

			# Name — bottom strip on white background
			lbl.text = _short_name(card_id)
			lbl.add_theme_color_override("font_color", Color(0.08, 0.14, 0.35, 1))
			lbl.anchor_top = 1.0; lbl.anchor_bottom = 1.0
			lbl.offset_top = -32.0; lbl.offset_bottom = -2.0
			lbl.offset_left = 2.0; lbl.offset_right = -26.0
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

			slot.clip_contents = true
			slot.add_theme_stylebox_override("panel", sbf_filled)
		else:
			art.texture = null
			art.visible = false
			# Restore artwork anchors to full rect for next fill
			art.anchor_bottom = 1.0; art.offset_bottom = 0.0

			lbl.text = "— empty —"
			lbl.add_theme_color_override("font_color", C_TEXT_MUTED)
			# Restore original bottom-anchored label position
			lbl.anchor_top = 1.0; lbl.anchor_bottom = 1.0
			lbl.offset_top = -38.0; lbl.offset_bottom = -2.0
			lbl.offset_left = 2.0; lbl.offset_right = -28.0
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

			slot.clip_contents = false
			slot.add_theme_stylebox_override("panel", sbf_empty)

# ── Collection Grid ───────────────────────────────────────────────────────────

# Rebuild the full collection grid — only call this on first build or full refresh.
# For add/remove/switch operations use _refresh_collection_highlights() instead.
func _build_collection_grid() -> void:
	var grid: GridContainer = $CollectionScroll/CollectionGrid
	for child in grid.get_children():
		child.queue_free()
	_collection_btn_map.clear()

	var owned: Array[String] = SaveManager.get_owned_cards()
	_sorted_owned_cards = owned.duplicate()
	_sorted_owned_cards.sort()

	for i in range(_sorted_owned_cards.size()):
		var card_id: String = _sorted_owned_cards[i]
		var card_data: Dictionary = CardDatabase.CARDS.get(card_id, {})
		var in_deck: bool = _is_button_in_deck(i, card_id)

		# Container: clips artwork to card bounds
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(130, 162)
		btn.clip_contents = true
		# Remove default button padding so artwork fills the whole button
		var sbf_btn := StyleBoxFlat.new()
		sbf_btn.bg_color = card_data.get("bg_color", Color(0.55, 0.72, 0.90, 1.0))
		sbf_btn.set_corner_radius_all(6)
		sbf_btn.border_width_bottom = 3
		sbf_btn.border_width_top = 1
		sbf_btn.border_color = C_BORDER_INDECK if in_deck else Color(0.55, 0.75, 0.95, 1.0)
		btn.add_theme_stylebox_override("normal", sbf_btn)
		var sbf_h := sbf_btn.duplicate() as StyleBoxFlat
		sbf_h.border_color = C_BORDER_HOVER
		sbf_h.border_width_bottom = 3
		btn.add_theme_stylebox_override("hover", sbf_h)
		btn.add_theme_stylebox_override("pressed", sbf_h)
		# Remove icon (we use a child TextureRect instead)
		btn.flat = false

		# Artwork as child TextureRect — fills full card, keeps aspect, clips at edge
		if card_data.get("has_image", false):
			var tex := _try_load_texture(card_data.get("image_path", ""))
			if tex:
				var art := TextureRect.new()
				art.texture = tex
				art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				# Anchor to fill the entire button
				art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				art.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(art)

		# Bottom info bar: name + cost overlaid on artwork
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.52)
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = -42.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(bar)

		var lbl := Label.new()
		lbl.text = _short_name(card_id) + "\n💰" + str(card_data.get("cost", "?"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		lbl.offset_top = -42.0
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(lbl)

		# "In Deck" badge
		if in_deck:
			var badge := Label.new()
			badge.text = "✓ In Deck"
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			badge.offset_bottom = 22.0
			badge.add_theme_font_size_override("font_size", 10)
			badge.name = "InDeckBadge"
			badge.add_theme_color_override("font_color", Color(0.05, 0.88, 0.62, 1.0))
			badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
			badge.add_theme_constant_override("shadow_offset_x", 1)
			badge.add_theme_constant_override("shadow_offset_y", 1)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(badge)
			btn.modulate = Color(0.72, 0.72, 0.72, 1.0)

		# All interaction handled in gui_input (tap + hold-to-detail)
		btn.gui_input.connect(_on_card_gui_input.bind(i, card_id))

		_collection_btn_map[i] = btn
		grid.add_child(btn)

func _try_load_texture(path: String) -> Texture2D:
	return GameCache.get_texture(path)

# ── Add Card ──────────────────────────────────────────────────────────────────

func _toggle_collection_card(button_index: int, card_id: String) -> void:
	# Toggle: remove if already in deck
	var in_deck: bool = _is_button_in_deck(button_index, card_id)
	if in_deck:
		var idx: int = _working_deck.find(str(button_index))
		if idx != -1:
			_working_deck.remove_at(idx)
			_refresh_deck_ui()
			_refresh_collection_highlights()
			_refresh_action_bar()
			return
	else:
		# Add: check capacity
		if _working_deck.size() >= DECK_SIZE:
			return
		# Add: enforce unique name per deck
		if _deck_has_name(card_id):
			return
		_working_deck.append(str(button_index))
		_refresh_deck_ui()
		_refresh_collection_highlights()
		_refresh_action_bar()

# ── Hold-to-Detail ────────────────────────────────────────────────────────────

func _on_card_gui_input(event: InputEvent, button_index: int, card_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_hold_triggered = false
			_held_card_id = card_id
			_held_button_index = button_index
			_hold_press_pos = event.position
			$HoldTimer.start()
		else:
			$HoldTimer.stop()
			if _held_card_id == card_id and _held_button_index == button_index and not _hold_triggered:
				_toggle_collection_card(button_index, card_id)
			_held_card_id = ""
			_held_button_index = -1
	elif event is InputEventMouseMotion:
		if _held_card_id != "":
			var pos: Vector2 = event.position
			if pos.distance_to(_hold_press_pos) > HOLD_DRAG_THRESHOLD:
				$HoldTimer.stop()
				_held_card_id = ""
				_held_button_index = -1

func _on_hold_complete() -> void:
	if _held_card_id != "":
		_hold_triggered = true
		_show_detail(_held_card_id)

func _on_deck_slot_input(event: InputEvent, slot_index: int) -> void:
	if slot_index >= _working_deck.size():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_working_deck.remove_at(slot_index)
		_refresh_deck_ui()
		_refresh_collection_highlights()
		_refresh_action_bar()

# ── Card Detail Overlay ───────────────────────────────────────────────────────

func _show_detail(card_id: String) -> void:
	UIShell.hide_shell()
	_detail_card_id = card_id
	var data: Dictionary = CardDatabase.get_effective_dict(card_id)
	if data.is_empty():
		return

	var rarity: int = clampi(data.get("rarity", 0), 0, CardDatabase.RARITY_COLORS.size() - 1)

	# Artwork
	var art: TextureRect = $DetailOverlay/CardPanel/ArtworkRect
	if data.get("has_image", false):
		var tex := _try_load_texture(data.get("image_path", ""))
		if tex:
			art.texture = tex
			art.visible = true
		else:
			art.visible = false
	else:
		art.visible = false

	$DetailOverlay/CardPanel/NameLabel.text   = data.get("name", card_id)

	var r_lbl: Label = $DetailOverlay/CardPanel/RarityLabel
	r_lbl.text = "◆  " + CardDatabase.RARITY_NAMES[rarity]
	r_lbl.add_theme_color_override("font_color", CardDatabase.RARITY_COLORS[rarity])

	$DetailOverlay/CardPanel/StatsLabel.text = (
		"⚔ ATK  " + str(data.get("atk", "?"))
		+ "    ❤ HP  " + str(data.get("hp", "?"))
		+ "    💰 Cost  " + str(data.get("cost", "?"))
	)

	var desc: String = data.get("description", "")
	$DetailOverlay/CardPanel/DescLabel.text = desc if desc != "" else "No description yet."

	var skills: Array = data.get("skills", [])
	var skills_text: String = "—"
	if not skills.is_empty():
		var parts := PackedStringArray()
		for s in skills:
			parts.append(str(s))
		skills_text = "  •  ".join(parts)
	$DetailOverlay/CardPanel/SkillsLabel.text = "Skills:  " + skills_text

	# Refresh upgrade table (Level 5 down to 2, bottom to top)
	var table: VBoxContainer = $DetailOverlay/CardPanel/UpgradeTable
	for child in table.get_children():
		child.queue_free()
		
	var current_level: int = SaveManager.get_character_level(card_id)
	
	# Render 4 rows: from lvl 5 (top) down to 2 (bottom)
	for lvl in range(5, 1, -1):
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(400, 42)
		
		var sbf_row := StyleBoxFlat.new()
		sbf_row.set_corner_radius_all(4)
		if lvl <= current_level:
			sbf_row.bg_color = Color(0.1, 0.45, 0.25, 0.18) # Unlocked (green)
			sbf_row.border_color = Color(0.1, 0.45, 0.25, 0.6)
			sbf_row.border_width_bottom = 1
		elif lvl == current_level + 1:
			sbf_row.bg_color = Color(0.72, 0.5, 0.05, 0.18) # Next (yellow/orange)
			sbf_row.border_color = Color(0.72, 0.5, 0.05, 0.6)
			sbf_row.border_width_bottom = 1
		else:
			sbf_row.bg_color = Color(0.25, 0.25, 0.25, 0.1) # Locked (grey)
			sbf_row.border_color = Color(0.25, 0.25, 0.25, 0.25)
			sbf_row.border_width_bottom = 1
		row.add_theme_stylebox_override("panel", sbf_row)
		
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		row.add_child(margin)
		
		var hbox := HBoxContainer.new()
		margin.add_child(hbox)
		
		var lvl_lbl := Label.new()
		lvl_lbl.text = "Level " + str(lvl)
		lvl_lbl.add_theme_font_size_override("font_size", 12)
		lvl_lbl.add_theme_color_override("font_color", Color(0.08, 0.14, 0.35, 1))
		hbox.add_child(lvl_lbl)
		
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spacer)
		
		var status_lbl := Label.new()
		if lvl <= current_level:
			status_lbl.text = "✓ Unlocked"
			status_lbl.add_theme_color_override("font_color", Color(0.1, 0.62, 0.25, 1))
		elif lvl == current_level + 1:
			status_lbl.text = "Next (Cost: " + str(10 * lvl) + " coins)"
			status_lbl.add_theme_color_override("font_color", Color(0.72, 0.5, 0.05, 1))
		else:
			status_lbl.text = "🔒 Locked"
			status_lbl.add_theme_color_override("font_color", Color(0.45, 0.55, 0.70, 1))
		status_lbl.add_theme_font_size_override("font_size", 12)
		hbox.add_child(status_lbl)
		
		table.add_child(row)

	# Upgrade Button state
	var up_btn: Button = $DetailOverlay/CardPanel/UpgradeBtn
	if current_level >= SaveManager.UPGRADE_MAX_LEVEL:
		up_btn.disabled = true
		up_btn.text = "Max Level"
	else:
		var cost = 10 * (current_level + 1)
		up_btn.disabled = SaveManager.get_coins() < cost
		up_btn.text = "Upgrade (Cost: " + str(cost) + ")"
		
	var sbf_up := StyleBoxFlat.new()
	sbf_up.set_corner_radius_all(6)
	if up_btn.disabled:
		sbf_up.bg_color = Color(0.45, 0.55, 0.70, 1.0)
	else:
		sbf_up.bg_color = Color(0.10, 0.62, 0.25, 1.0)
	up_btn.add_theme_stylebox_override("normal", sbf_up)
	up_btn.add_theme_stylebox_override("hover", sbf_up)
	up_btn.add_theme_stylebox_override("pressed", sbf_up)
	up_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	$DetailOverlay.visible = true

func _on_upgrade_pressed() -> void:
	if _detail_card_id == "":
		return
	if SaveManager.upgrade_character(_detail_card_id):
		_show_detail(_detail_card_id)
		UIShell.refresh_coins()
		_build_collection_grid()
		_refresh_deck_ui()

func _on_close_detail() -> void:
	$DetailOverlay.visible = false
	UIShell.show_shell()

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_close_detail()
	elif event is InputEventScreenTouch and event.pressed:
		_on_close_detail()

# ── Collection Highlight Refresh ─────────────────────────────────────────────
# Updates border colour, badge and dimming on existing collection buttons.
# Much cheaper than _build_collection_grid() — does NOT touch the texture or
# recreate any nodes.
func _refresh_collection_highlights() -> void:
	for i in _collection_btn_map:
		var btn: Button = _collection_btn_map[i]
		if not is_instance_valid(btn):
			continue
		var card_id: String = _sorted_owned_cards[i]
		var in_deck: bool = _is_button_in_deck(i, card_id)

		# Update border colour on the StyleBoxFlat we stored earlier
		var sbf := btn.get_theme_stylebox("normal") as StyleBoxFlat
		if sbf:
			sbf.border_color = C_BORDER_INDECK if in_deck else Color(0.55, 0.75, 0.95, 1.0)

		# Dim / un-dim
		btn.modulate = Color(0.72, 0.72, 0.72, 1.0) if in_deck else Color(1, 1, 1, 1)

		# Add or remove the "In Deck" badge
		var badge: Node = btn.get_node_or_null("InDeckBadge")
		if in_deck and badge == null:
			var b := Label.new()
			b.name = "InDeckBadge"
			b.text = "✓ In Deck"
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			b.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			b.offset_bottom = 22.0
			b.add_theme_font_size_override("font_size", 10)
			b.add_theme_color_override("font_color", Color(0.05, 0.88, 0.62, 1.0))
			b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
			b.add_theme_constant_override("shadow_offset_x", 1)
			b.add_theme_constant_override("shadow_offset_y", 1)
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(b)
		elif not in_deck and badge != null:
			badge.queue_free()
# ── Deck Active / Edit / Save / Cancel ───────────────────────────────────────────

func _on_set_active() -> void:
	if _working_deck.size() < DECK_SIZE:
		return
	var cards_to_save: Array[String] = []
	for idx_str in _working_deck:
		var idx := int(idx_str)
		if idx >= 0 and idx < _sorted_owned_cards.size():
			cards_to_save.append(_sorted_owned_cards[idx])
	SaveManager.set_deck(_current_index, cards_to_save)
	SaveManager.set_active_deck(_current_index)
	_refresh_selector_buttons()
	_refresh_action_bar()

func _on_save() -> void:
	if _working_deck.size() < DECK_SIZE:
		return
	var cards_to_save: Array[String] = []
	for idx_str in _working_deck:
		var idx := int(idx_str)
		if idx >= 0 and idx < _sorted_owned_cards.size():
			cards_to_save.append(_sorted_owned_cards[idx])
	SaveManager.set_deck(_current_index, cards_to_save)
	_refresh_selector_buttons()
	_refresh_action_bar()

func _on_cancel_edit() -> void:
	_do_cancel_edit()

func _do_cancel_edit() -> void:
	_load_working_deck()
	_refresh_deck_ui()
	_refresh_collection_highlights()
	_refresh_action_bar()

func _refresh_action_bar() -> void:
	var is_active: bool = (SaveManager.get_active_index() == _current_index)
	var is_full: bool = (_working_deck.size() == DECK_SIZE)
	var set_btn: Button = $ActionBar/SetActiveBtn
	var save_btn: Button = $ActionBar/SaveBtn
	var cancel_btn: Button = $ActionBar/CancelBtn
	set_btn.disabled = is_active or not is_full
	set_btn.text = "[ACTIVE]" if is_active else "Set Active"
	_style_btn(set_btn, Color(0.10, 0.62, 0.25, 1.0) if (not is_active and is_full) else Color(0.45, 0.55, 0.70, 1.0))
	save_btn.disabled = not is_full
	_style_btn(save_btn, Color(0.10, 0.62, 0.25, 1.0) if is_full else Color(0.45, 0.55, 0.70, 1.0))
	_style_btn(cancel_btn, Color(0.72, 0.25, 0.18, 1.0))

func _style_btn(btn: Button, color: Color) -> void:
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = color
	sbf.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sbf)
	btn.add_theme_stylebox_override("hover", sbf)
	btn.add_theme_stylebox_override("pressed", sbf)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
# ── Selector Buttons Highlight ────────────────────────────────────────────────

func _refresh_selector_buttons() -> void:
	var active_idx: int = SaveManager.get_active_index()
	for i in range(1, 4):
		var btn: Button = $DeckSelectorBar.get_node("Deck" + str(i) + "Btn")
		var sbf := StyleBoxFlat.new()
		sbf.set_corner_radius_all(8)
		if i == _current_index:
			sbf.bg_color = C_BTN_ACTIVE
			btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		else:
			sbf.bg_color = C_BTN_INACTIVE
			btn.add_theme_color_override("font_color", C_TEXT_DARK)
		btn.add_theme_stylebox_override("normal", sbf)
		btn.add_theme_stylebox_override("hover", sbf)
		btn.add_theme_stylebox_override("pressed", sbf)
		btn.text = "Deck " + str(i) + (" [ACTIVE]" if i == active_idx else "")

# ── Helpers ───────────────────────────────────────────────────────────────────

func _short_name(card_id: String) -> String:
	var data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	var display: String = data.get("name", card_id)
	if display.length() > 10:
		return display.substr(0, 9) + "."
	return display

func _deck_has_name(card_id: String) -> bool:
	var new_name: String = CardDatabase.CARDS.get(card_id, {}).get("name", card_id)
	for idx_str in _working_deck:
		var idx := int(idx_str)
		if idx >= 0 and idx < _sorted_owned_cards.size():
			var existing_id: String = _sorted_owned_cards[idx]
			if CardDatabase.CARDS.get(existing_id, {}).get("name", existing_id) == new_name:
				return true
	return false

func _is_button_in_deck(button_index: int, _card_id: String) -> bool:
	return _working_deck.has(str(button_index))

func _on_back() -> void:
	SceneManager.go_to_lobby()

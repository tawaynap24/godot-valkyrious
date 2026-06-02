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
var _detail_card_index: int = -1


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
	$DetailOverlay/MainDetailView/LeftBtn.pressed.connect(_on_prev_character)
	$DetailOverlay/MainDetailView/RightBtn.pressed.connect(_on_next_character)
	$DetailOverlay/MainDetailView/BottomBar/BackBtn.pressed.connect(_on_close_detail)
	$DetailOverlay/MainDetailView/BottomBar/UpgradeBtn.pressed.connect(_on_open_upgrade_dialog)
	$DetailOverlay/MainDetailView/BottomBar/JoinTeamBtn.pressed.connect(_on_join_team_pressed)
	$DetailOverlay/UpgradeDialog/DialogPanel/LevelUpBtn.pressed.connect(_on_level_up_pressed)
	$DetailOverlay/UpgradeDialog/CloseDialogBtn.pressed.connect(_on_close_upgrade_dialog)
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
	if _held_button_index != -1:
		_hold_triggered = true
		_show_detail(_held_button_index)

func _on_deck_slot_input(event: InputEvent, slot_index: int) -> void:
	if slot_index >= _working_deck.size():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_working_deck.remove_at(slot_index)
		_refresh_deck_ui()
		_refresh_collection_highlights()
		_refresh_action_bar()

# ── Card Detail Overlay ───────────────────────────────────────────────────────

# Character-specific skill translations to make it look premium
const SKILL_INFO := {
	"death_burst_ange": {
		"name": "✨ ระเบิดพลีชีพ",
		"desc": "เมื่อถูกกำจัด จะสร้างความเสียหาย 4 หน่วยแก่ศัตรูทั้งหมด"
	},
	"stun_lowest_countdown": {
		"name": "✨ คลื่นช็อกเวฟ",
		"desc": "ทำให้ศัตรูที่มีคูลดาวน์เคลื่อนไหวต่ำสุด ติดสถานะมึนงง"
	},
	"stun_enemy": {
		"name": "✨ หมัดอัมพาต",
		"desc": "ทำให้ศัตรูที่ถูกโจมตีติดสถานะมึนงง"
	},
	"benita": {
		"name": "✨ ระเบิดโทสะ",
		"desc": "เมื่อได้รับความเสียหาย จะมอบพลังโจมตี +2 แก่ตนเอง"
	}
}

func _show_detail(card_index: int) -> void:
	UIShell.hide_shell()
	_detail_card_index = card_index
	var card_id: String = _sorted_owned_cards[card_index]
	var data: Dictionary = CardDatabase.get_effective_dict(card_id)
	if data.is_empty():
		return

	# Artwork
	var art: TextureRect = $DetailOverlay/MainDetailView/ArtworkRect
	if data.get("has_image", false):
		var tex := _try_load_texture(data.get("image_path", ""))
		if tex:
			art.texture = tex
			art.visible = true
		else:
			art.visible = false
	else:
		art.visible = false

	# Name & Level
	var current_level: int = SaveManager.get_character_level(card_id)
	var char_name: String = data.get("name", card_id)
	
	# Try translating card name to Thai for UI aesthetics
	var thai_names := {
		"benita": "เบนิต้า",
		"ange": "แอนจ์",
		"ariana": "อารีอานา",
		"nicole": "นิโคล",
		"ran": "รัน",
		"sia": "เซีย",
		"victoria": "วิคตอเรีย",
		"jenny": "เจนนี่"
	}
	var display_name: String = thai_names.get(card_id.to_lower(), char_name)
	$DetailOverlay/MainDetailView/InfoPanel/LevelNameLabel.text = "Lv." + str(current_level) + " " + display_name

	# Stats
	$DetailOverlay/MainDetailView/InfoPanel/StatsHBox/CostBox/Val.text = str(data.get("cost", "?"))
	$DetailOverlay/MainDetailView/InfoPanel/StatsHBox/AtkBox/Val.text = str(data.get("atk", "?"))
	$DetailOverlay/MainDetailView/InfoPanel/StatsHBox/HpBox/Val.text = str(data.get("hp", "?"))

	# Skill Name & Desc
	var skill_id: String = ""
	var skills: Array = data.get("skills", [])
	if not skills.is_empty():
		skill_id = str(skills[0])
	
	# Look up translation or use fallback
	var sk_name: String = "✨ ไม่มีสกิล"
	var sk_desc: String = "ฮีโร่ตัวนี้ไม่มีสกิลติดตัว"
	
	if SKILL_INFO.has(skill_id):
		sk_name = SKILL_INFO[skill_id]["name"]
		sk_desc = SKILL_INFO[skill_id]["desc"]
	elif SKILL_INFO.has(card_id):
		sk_name = SKILL_INFO[card_id]["name"]
		sk_desc = SKILL_INFO[card_id]["desc"]
	elif skill_id != "":
		sk_name = "✨ " + skill_id
		sk_desc = "คำอธิบายสำหรับสกิล " + skill_id
		
	$DetailOverlay/MainDetailView/InfoPanel/SkillPanel/SkillName.text = sk_name
	$DetailOverlay/MainDetailView/InfoPanel/SkillPanel/SkillDesc.text = sk_desc

	# Enable/Disable character navigation arrows
	$DetailOverlay/MainDetailView/LeftBtn.disabled = (_detail_card_index <= 0)
	$DetailOverlay/MainDetailView/RightBtn.disabled = (_detail_card_index >= _sorted_owned_cards.size() - 1)

	# Join/Leave Team Button Text & Style
	_refresh_join_team_btn(card_id)

	# Make detail overlay visible (ensure UpgradeDialog is closed by default)
	$DetailOverlay/UpgradeDialog.visible = false
	$DetailOverlay.visible = true

func _refresh_join_team_btn(card_id: String) -> void:
	var join_btn := $DetailOverlay/MainDetailView/BottomBar/JoinTeamBtn
	var is_in_deck: bool = _working_deck.has(str(_detail_card_index))
	
	if is_in_deck:
		join_btn.text = "ออกจากทีม"
	else:
		join_btn.text = "เข้าร่วมทีม"
		
	# Disable if name is already taken or deck is full
	var name_taken = _deck_has_name(card_id) and not is_in_deck
	var deck_full = _working_deck.size() >= DECK_SIZE and not is_in_deck
	join_btn.disabled = name_taken or deck_full

func _on_prev_character() -> void:
	if _detail_card_index > 0:
		_show_detail(_detail_card_index - 1)

func _on_next_character() -> void:
	if _detail_card_index < _sorted_owned_cards.size() - 1:
		_show_detail(_detail_card_index + 1)

func _on_join_team_pressed() -> void:
	if _detail_card_index == -1:
		return
	var card_id: String = _sorted_owned_cards[_detail_card_index]
	_toggle_collection_card(_detail_card_index, card_id)
	_refresh_join_team_btn(card_id)

func _on_open_upgrade_dialog() -> void:
	$DetailOverlay/UpgradeDialog.visible = true
	_refresh_upgrade_dialog()

func _on_close_upgrade_dialog() -> void:
	$DetailOverlay/UpgradeDialog.visible = false

func _refresh_upgrade_dialog() -> void:
	if _detail_card_index == -1:
		return
	var card_id: String = _sorted_owned_cards[_detail_card_index]
	var data: Dictionary = CardDatabase.get_effective_dict(card_id)
	if data.is_empty():
		return
		
	# Banner artwork
	var banner := $DetailOverlay/UpgradeDialog/DialogPanel/BannerRect
	if data.get("has_image", false):
		banner.texture = _try_load_texture(data.get("image_path", ""))
		banner.visible = true
	else:
		banner.visible = false

	# Title Box Status
	var current_level: int = SaveManager.get_character_level(card_id)
	var title_lbl := $DetailOverlay/UpgradeDialog/DialogPanel/TitleBox/TitleLbl
	if current_level >= 5:
		title_lbl.text = "TITLE\n🔓 Unlocked"
	else:
		title_lbl.text = "TITLE\n🔒 Locked"

	# Build upgrade table rows (Levels 5 down to 2)
	var table := $DetailOverlay/UpgradeDialog/DialogPanel/UpgradeTable
	for child in table.get_children():
		child.queue_free()

	for lvl in range(5, 1, -1):
		var row := Panel.new()
		row.custom_minimum_size = Vector2(432, 40)
		
		var sbf := StyleBoxFlat.new()
		sbf.set_corner_radius_all(6)
		
		var text_color: Color
		if lvl <= current_level:
			# Unlocked: Dark Slate Blue
			sbf.bg_color = Color(0.18, 0.28, 0.48, 1.0)
			text_color = Color(1.0, 1.0, 1.0)
		elif lvl == current_level + 1:
			# Active / Next Level: Vibrant Cyan-Blue
			sbf.bg_color = Color(0.12, 0.48, 0.92, 1.0)
			text_color = Color(1.0, 1.0, 1.0)
		else:
			# Locked / Higher Levels: Muted Gray-Blue
			sbf.bg_color = Color(0.85, 0.88, 0.92, 0.6)
			text_color = Color(0.5, 0.55, 0.65)
			
		row.add_theme_stylebox_override("panel", sbf)
		
		var lbl := Label.new()
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", text_color)
		
		var boost_desc = "❤️ Life +1" if lvl == 5 else "⚡ Ability +1"
		lbl.text = "Lv. " + str(lvl) + "   |   " + boost_desc
		
		row.add_child(lbl)
		table.add_child(row)

	# Level Up Button and Cost display
	var level_up_btn := $DetailOverlay/UpgradeDialog/DialogPanel/LevelUpBtn
	var cost_lbl := $DetailOverlay/UpgradeDialog/DialogPanel/CostHBox/CostLbl
	
	if current_level >= SaveManager.UPGRADE_MAX_LEVEL:
		cost_lbl.text = "Max Level"
		level_up_btn.disabled = true
		level_up_btn.text = "MAX LEVEL"
	else:
		var cost = 10 * (current_level + 1)
		cost_lbl.text = "💰 " + str(cost)
		level_up_btn.disabled = SaveManager.get_coins() < cost
		level_up_btn.text = "LEVEL UP"

func _on_level_up_pressed() -> void:
	if _detail_card_index == -1:
		return
	var card_id: String = _sorted_owned_cards[_detail_card_index]
	if SaveManager.upgrade_character(card_id):
		# Re-render Detail UI and Dialog with new level
		UIShell.refresh_coins()
		_show_detail(_detail_card_index)
		_refresh_upgrade_dialog()
		_build_collection_grid()
		_refresh_deck_ui()

func _on_close_detail() -> void:
	$DetailOverlay.visible = false
	UIShell.show_shell()

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

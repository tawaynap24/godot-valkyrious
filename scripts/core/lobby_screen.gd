extends Node2D

var _showing_coming_soon: bool = false
var _forced_edit: bool = false       # true = first-time setup, no cancel
var _pending_icon: String = ""       # icon selected in picker not yet saved

func _ready() -> void:
	$BattleAIButton.pressed.connect(_on_battle_ai_pressed)
	$BattleOnlineButton.pressed.connect(_on_battle_online_pressed)
	$CollectionBtn.pressed.connect(func(): SceneManager.go_to_collection())
	# Navigation buttons hidden — accessible via footer UIShell
	$DeckBuilderButton.visible = false
	$CollectionButton.visible  = false
	$GachaButton.visible       = false
	$HistoryButton.visible     = false
	SaveManager.active_deck_changed.connect(func(_i): _refresh_battle_btns())
	SaveManager.deck_changed.connect(func(_i): _refresh_battle_btns())
	SaveManager.profile_changed.connect(_refresh_profile_display)
	SaveManager.record_changed.connect(_refresh_record)
	$ProfileBtn.pressed.connect(_on_profile_btn_pressed)
	$ProfileEditorPanel/EditorCard/ChangeIconBtn.pressed.connect(_on_change_icon_pressed)
	$ProfileEditorPanel/EditorCard/SaveProfileBtn.pressed.connect(_on_save_profile)
	$ProfileEditorPanel/EditorCard/CancelProfileBtn.pressed.connect(_on_cancel_profile)
	$IconPickerPanel/PickerHeader/PickerBackBtn.pressed.connect(_on_picker_back)
	$HistoryPanel/HistoryHeader/HistoryCloseBtn.pressed.connect(func(): $HistoryPanel.visible = false)
	_refresh_battle_btns()
	_refresh_profile_display()
	_refresh_record()
	_refresh_coins()
	UIShell.set_active_tab("")
	# Auto-open profile editor on first launch (name is empty)
	if SaveManager.get_player_name() == "":
		_open_profile_editor(true)

func _refresh_coins() -> void:
	$GoldLabel.text = "💰 " + str(SaveManager.get_coins())

# ── Battle button gating ──────────────────────────────────────────────────────

func _refresh_battle_btns() -> void:
	var can_play: bool = SaveManager.has_playable_deck()
	$BattleAIButton.disabled = not can_play
	$BattleOnlineButton.disabled = not can_play
	$NoDeckLabel.visible = not can_play

# ── Scene navigation ──────────────────────────────────────────────────────────

func _on_battle_ai_pressed() -> void:
	SceneManager.go_to_battle_ai()

func _on_battle_online_pressed() -> void:
	SceneManager.go_to_matchmaking()

func _on_deck_builder_pressed() -> void:
	SceneManager.go_to_deck_builder()

func _on_collection_pressed() -> void:
	SceneManager.go_to_collection()

func _on_gacha_pressed() -> void:
	SceneManager.go_to_gacha()

func _on_coming_soon() -> void:
	if _showing_coming_soon:
		return
	_showing_coming_soon = true
	$ComingSoonLabel.visible = true
	await get_tree().create_timer(1.5).timeout
	$ComingSoonLabel.visible = false
	_showing_coming_soon = false

# ── Record display ────────────────────────────────────────────────────────────

func _refresh_record() -> void:
	var w := SaveManager.get_wins()
	var d := SaveManager.get_draws()
	var l := SaveManager.get_losses()
	$RecordLabel.text = "W:%d  D:%d  L:%d" % [w, d, l]

# ── History panel ─────────────────────────────────────────────────────────────

func _on_history_pressed() -> void:
	_build_history_list()
	$HistoryPanel.visible = true

func _build_history_list() -> void:
	var list: VBoxContainer = $HistoryPanel/HistoryScroll/HistoryList
	for c in list.get_children():
		c.queue_free()
	var history := SaveManager.get_battle_history()
	if history.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = tr("UI_NO_BATTLE_HISTORY")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 1.0))
		empty_lbl.custom_minimum_size = Vector2(576.0, 80.0)
		list.add_child(empty_lbl)
		return
	for entry in history:
		var row := _make_history_row(
			entry.get("result", ""),
			entry.get("opponent", "?"),
			entry.get("mode", "ai"),
			entry.get("time", 0)
		)
		list.add_child(row)

func _make_history_row(result: String, opponent: String, mode: String, unix_time: int) -> Control:
	# Use Control as outer container so VBoxContainer can size it properly
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, 64.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Background ColorRect fills the whole row
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match result:
		"win":  bg.color = Color(0.06, 0.22, 0.10, 1.0)
		"loss": bg.color = Color(0.22, 0.06, 0.06, 1.0)
		"draw": bg.color = Color(0.14, 0.14, 0.24, 1.0)
		_:      bg.color = Color(0.10, 0.12, 0.20, 1.0)
	row.add_child(bg)

	# Badge WIN/LOSS/DRAW — fixed left column 80px
	var badge := Label.new()
	badge.anchor_bottom = 1.0
	badge.offset_right = 80.0
	match result:
		"win":  badge.text = tr("UI_WIN");  badge.add_theme_color_override("font_color", Color(0.28, 1.0, 0.50, 1.0))
		"loss": badge.text = tr("UI_LOSS"); badge.add_theme_color_override("font_color", Color(1.0, 0.35, 0.30, 1.0))
		"draw": badge.text = tr("UI_DRAW_SHORT"); badge.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78, 1.0))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 14)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)

	# Opponent name — upper half, from x=86 to x=400
	var opp_lbl := Label.new()
	opp_lbl.text = "vs  " + opponent
	opp_lbl.offset_left = 86.0
	opp_lbl.offset_top = 6.0
	opp_lbl.offset_right = 400.0
	opp_lbl.offset_bottom = 36.0
	opp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	opp_lbl.add_theme_font_size_override("font_size", 16)
	opp_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	opp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(opp_lbl)

	# Mode tag — lower half, from x=86
	var mode_lbl := Label.new()
	mode_lbl.text = tr("UI_ONLINE") if mode == "online" else tr("UI_AI")
	mode_lbl.offset_left = 86.0
	mode_lbl.offset_top = 36.0
	mode_lbl.offset_right = 240.0
	mode_lbl.offset_bottom = 58.0
	mode_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var mc := Color(0.4, 0.8, 1.0, 1.0) if mode == "online" else Color(0.55, 0.78, 0.55, 1.0)
	mode_lbl.add_theme_color_override("font_color", mc)
	mode_lbl.add_theme_font_size_override("font_size", 12)
	mode_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mode_lbl)

	# Date/time — right side, anchored to right edge of parent
	var dt_lbl := Label.new()
	if unix_time > 0:
		var dt := Time.get_datetime_dict_from_unix_time(unix_time)
		dt_lbl.text = "%02d/%02d  %02d:%02d" % [dt["month"], dt["day"], dt["hour"], dt["minute"]]
	else:
		dt_lbl.text = ""
	dt_lbl.anchor_left = 1.0
	dt_lbl.anchor_right = 1.0
	dt_lbl.anchor_top = 0.0
	dt_lbl.anchor_bottom = 1.0
	dt_lbl.offset_left = -160.0
	dt_lbl.offset_right = -8.0
	dt_lbl.offset_top = 0.0
	dt_lbl.offset_bottom = 0.0
	dt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dt_lbl.add_theme_font_size_override("font_size", 12)
	dt_lbl.add_theme_color_override("font_color", Color(0.52, 0.62, 0.76, 1.0))
	dt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dt_lbl)

	return row

# ── Profile display ───────────────────────────────────────────────────────────

func _refresh_profile_display() -> void:
	var pname := SaveManager.get_player_name()
	$PlayerNameLabel.text = pname if pname != "" else tr("UI_PLAYER")
	var icon_id := SaveManager.get_profile_icon()
	var has_icon := _load_icon_into($ProfileBtn/ProfileIconRect, icon_id)
	$ProfileBtn/ProfileIconRect.visible = has_icon
	$ProfileBtn/ProfileIconPlaceholder.visible = not has_icon
	var initial := pname.substr(0, 1).to_upper() if pname != "" else "?"
	$ProfileBtn/ProfileInitialLabel.text = initial
	$ProfileBtn/ProfileInitialLabel.visible = not has_icon

# ── Profile editor ────────────────────────────────────────────────────────────

func _on_profile_btn_pressed() -> void:
	_open_profile_editor(false)

func _open_profile_editor(force: bool) -> void:
	_forced_edit = force
	_pending_icon = SaveManager.get_profile_icon()
	var ed := $ProfileEditorPanel/EditorCard
	(ed.get_node("NameEdit") as LineEdit).text = SaveManager.get_player_name()
	ed.get_node("NameFeedbackLabel").visible = false
	(ed.get_node("EditorTitle") as Label).text = tr("UI_SET_PLAYER_NAME") if force else tr("UI_EDIT_PROFILE")
	ed.get_node("CancelProfileBtn").visible = not force
	_update_editor_icon_preview(_pending_icon)
	$ProfileEditorPanel.visible = true

func _update_editor_icon_preview(card_id: String) -> void:
	var ed := $ProfileEditorPanel/EditorCard
	var has_icon := _load_icon_into(ed.get_node("EditorIconRect"), card_id)
	ed.get_node("EditorIconRect").visible = has_icon
	ed.get_node("EditorIconPlaceholder").visible = not has_icon
	ed.get_node("EditorIconInitial").visible = not has_icon

func _on_save_profile() -> void:
	var ed := $ProfileEditorPanel/EditorCard
	var name_edit := ed.get_node("NameEdit") as LineEdit
	var new_name: String = name_edit.text.strip_edges()
	if new_name.length() < 2:
		ed.get_node("NameFeedbackLabel").visible = true
		return
	SaveManager.set_player_name(new_name)
	if _pending_icon != "":
		SaveManager.set_profile_icon(_pending_icon)
	$ProfileEditorPanel.visible = false

func _on_cancel_profile() -> void:
	if _forced_edit:
		return
	$ProfileEditorPanel.visible = false

# ── Icon picker ───────────────────────────────────────────────────────────────

func _on_change_icon_pressed() -> void:
	_build_picker_grid()
	$IconPickerPanel.visible = true

func _on_picker_back() -> void:
	$IconPickerPanel.visible = false

func _build_picker_grid() -> void:
	var grid: GridContainer = $IconPickerPanel/PickerScroll/PickerGrid
	for child in grid.get_children():
		child.queue_free()
	var owned := SaveManager.get_owned_cards()
	owned.sort()
	var current_icon := _pending_icon
	for card_id in owned:
		var cdata: Dictionary = CardDatabase.CARDS.get(card_id, {})
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(180, 225)
		btn.clip_contents = true
		var sbf := StyleBoxFlat.new()
		sbf.bg_color = cdata.get("bg_color", Color(0.12, 0.20, 0.48, 1.0))
		sbf.set_corner_radius_all(6)
		sbf.border_width_bottom = 3
		sbf.border_color = Color(0.05, 0.78, 0.55, 1.0) if card_id == current_icon else Color(0.25, 0.45, 0.75, 1.0)
		sbf.border_width_top = 1
		btn.add_theme_stylebox_override("normal", sbf)
		var sbf_h := sbf.duplicate() as StyleBoxFlat
		sbf_h.border_color = Color(0.3, 0.85, 1.0, 1.0)
		sbf_h.border_width_bottom = 4
		btn.add_theme_stylebox_override("hover", sbf_h)
		btn.add_theme_stylebox_override("pressed", sbf_h)
		if cdata.get("has_image", false):
			var tex := GameCache.get_texture(cdata.get("image_path", ""))
			if tex:
				var art := TextureRect.new()
				art.texture = tex
				art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				art.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(art)
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.55)
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = -36.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(bar)
		var lbl := Label.new()
		lbl.text = tr(cdata.get("name", card_id))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		lbl.offset_top = -36.0
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(lbl)
		btn.pressed.connect(_on_icon_selected.bind(card_id))
		grid.add_child(btn)

func _on_icon_selected(card_id: String) -> void:
	_pending_icon = card_id
	_update_editor_icon_preview(card_id)
	$IconPickerPanel.visible = false

# ── Shared helper ─────────────────────────────────────────────────────────────

func _load_icon_into(rect: TextureRect, card_id: String) -> bool:
	if card_id == "":
		return false
	var cdata: Dictionary = CardDatabase.CARDS.get(card_id, {})
	if cdata.get("has_image", false):
		var tex := GameCache.get_texture(cdata.get("image_path", ""))
		if tex:
			rect.texture = tex
			return true
	return false

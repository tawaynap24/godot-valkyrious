extends Node

const HEADER_H = 56.0
const FOOTER_H = 68.0
const VP_W = 576.0

var _layer = null
var _coins_lbl = null
var _tab_btns = {}
var _active_tab = ""

func _ready():
	_build_shell()

func _build_shell():
	_layer = CanvasLayer.new()
	_layer.layer = 10
	_layer.visible = false  # hidden until a screen calls show_shell()
	add_child(_layer)
	_build_header()
	_build_footer()

func _build_header():
	_coins_lbl = Label.new()
	_coins_lbl.anchor_left = 0.0; _coins_lbl.anchor_right = 1.0
	_coins_lbl.anchor_top = 0.0; _coins_lbl.anchor_bottom = 0.0
	_coins_lbl.offset_top = 6.0; _coins_lbl.offset_bottom = HEADER_H - 6.0
	_coins_lbl.offset_left = 0.0; _coins_lbl.offset_right = -16.0
	_coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coins_lbl.add_theme_font_size_override("font_size", 18)
	_coins_lbl.add_theme_color_override("font_color", Color(1.00, 0.82, 0.20, 1.0))
	_coins_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_coins_lbl)
	var tl = Label.new()
	tl.text = "✦ Valkyrious"
	tl.anchor_left = 0.0; tl.anchor_right = 1.0; tl.anchor_top = 0.0; tl.anchor_bottom = 0.0
	tl.offset_top = 6.0; tl.offset_bottom = HEADER_H - 6.0
	tl.offset_left = 16.0; tl.offset_right = 0.0
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 17)
	tl.add_theme_color_override("font_color", Color(0.82, 0.70, 1.0, 1.0))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(tl)
	refresh_coins()

func _build_footer():
	var bg = ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.18, 0.97)
	bg.anchor_left = 0.0; bg.anchor_right = 1.0; bg.anchor_top = 1.0; bg.anchor_bottom = 1.0
	bg.offset_top = -FOOTER_H; bg.offset_bottom = 0.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(bg)
	var sep = ColorRect.new()
	sep.color = Color(0.55, 0.35, 0.95, 0.45)
	sep.anchor_left = 0.0; sep.anchor_right = 1.0; sep.anchor_top = 1.0; sep.anchor_bottom = 1.0
	sep.offset_top = -FOOTER_H; sep.offset_bottom = -FOOTER_H + 2.0
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(sep)
	var TABS = [
		["shop", "🛒", "ร้านค้า"],
		["deck", "🃏", "ทีม"],
		["battle", "⚔", "ต่อสู้"],
		["records", "🏆", "บันทึก"],
		["gacha", "✨", "Gacha"],
	]
	var tab_w = VP_W / float(TABS.size())
	for i in range(TABS.size()):
		var tab_id = TABS[i][0]
		var btn = Button.new()
		btn.text = TABS[i][1] + "\n" + TABS[i][2]
		btn.anchor_left = 0.0; btn.anchor_right = 0.0; btn.anchor_top = 1.0; btn.anchor_bottom = 1.0
		btn.offset_left = float(i) * tab_w
		btn.offset_right = float(i + 1) * tab_w
		btn.offset_top = -FOOTER_H; btn.offset_bottom = 0.0
		btn.add_theme_font_size_override("font_size", 11)
		_style_tab_btn(btn, false)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		_layer.add_child(btn)
		_tab_btns[tab_id] = btn

func _style_tab_btn(btn, active):
	var sbf = StyleBoxFlat.new()
	sbf.bg_color = Color(0.22, 0.15, 0.40, 1.0) if active else Color(0.0, 0.0, 0.0, 0.0)
	sbf.set_corner_radius_all(0)
	btn.add_theme_stylebox_override("normal", sbf)
	var sbf_h = sbf.duplicate()
	sbf_h.bg_color = Color(0.30, 0.20, 0.52, 1.0)
	btn.add_theme_stylebox_override("hover", sbf_h)
	btn.add_theme_stylebox_override("pressed", sbf_h)
	var col = Color(0.82, 0.60, 1.0, 1.0) if active else Color(0.62, 0.55, 0.80, 1.0)
	btn.add_theme_color_override("font_color", col)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 1.0, 1.0))

func _on_tab_pressed(tab_id):
	match tab_id:
		"shop":    SceneManager.go_to_shop()
		"deck":    SceneManager.go_to_deck_builder()
		"battle":  SceneManager.go_to_lobby()
		"records": SceneManager.go_to_records()
		"gacha":   SceneManager.go_to_gacha()

func set_active_tab(tab_id):
	show_shell()
	_active_tab = tab_id
	for tid in _tab_btns:
		_style_tab_btn(_tab_btns[tid], tid == tab_id)
	refresh_coins()

func refresh_coins():
	if _coins_lbl:
		_coins_lbl.text = "💰 " + str(SaveManager.get_coins())

func hide_shell():
	if _layer:
		_layer.visible = false
	_set_canvas_offset(Vector2.ZERO)

func show_shell():
	if _layer:
		_layer.visible = true
		refresh_coins()
	_set_canvas_offset(Vector2(0.0, HEADER_H))

func _set_canvas_offset(offset: Vector2) -> void:
	var vp = get_viewport()
	if vp:
		vp.canvas_transform = Transform2D(0.0, offset)

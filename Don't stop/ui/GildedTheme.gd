extends RefCounted
## One material vocabulary, in the game's 410 x 230 design units.
## No gameplay state or random numbers belong in this resource.
const INK := Color("10191f")
const SURFACE := Color("18262e")
const EDGE := Color("41525a")
const GOLD := Color("dfbf82")
const TEXT := Color("eee8d9")
const MUTED := Color("a7bbc2")
static var themes: Dictionary = {}

static func plate(fill: Color = SURFACE, edge: Color = EDGE, margin := 3.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.corner_detail = 2
	s.set_content_margin_all(margin)
	return s

static func build(font_size := 7) -> Theme:
	if themes.has(font_size): return themes[font_size]
	var t := Theme.new()
	t.default_font = preload("res://fonts/fusion-pixel.otf")
	t.default_font_size = font_size
	var panel := plate(INK, EDGE, 4)
	panel.shadow_color = Color(0.01,0.02,0.03,0.55)
	panel.shadow_size = 5
	panel.shadow_offset = Vector2(0,3)
	t.set_stylebox("panel","PanelContainer",panel)
	t.set_stylebox("panel","Panel",panel)
	t.set_stylebox("panel","PopupMenu",plate(INK,GOLD,4))
	t.set_stylebox("panel","TooltipPanel",plate(INK,GOLD,4))
	for kind in ["Button","OptionButton","MenuButton"]:
		for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
			var fill: Color = {"normal":SURFACE,"hover":Color("30434c"),"pressed":Color("68573c"),"hover_pressed":Color("7b6542"),"disabled":Color("141d23"),"focus":Color.TRANSPARENT}[state]
			var edge: Color = GOLD if state in ["hover","pressed","hover_pressed","focus"] else EDGE
			var s := plate(fill,edge,3)
			if state == "normal": s.border_width_bottom = 2
			t.set_stylebox(state,kind,s)
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]: t.set_color(state,kind,TEXT)
		t.set_color("font_disabled_color",kind,Color("7f949e"))
	t.set_color("font_color","Label",TEXT)
	t.set_color("font_color","RichTextLabel",TEXT)
	t.set_color("font_color","TooltipLabel",TEXT)
	t.set_color("font_color","PopupMenu",TEXT)
	t.set_stylebox("hover","PopupMenu",plate(SURFACE,GOLD))
	t.set_stylebox("normal","LineEdit",plate(Color("0b1319"),EDGE,3))
	t.set_stylebox("focus","LineEdit",plate(Color.TRANSPARENT,GOLD,3))
	t.set_color("font_color","LineEdit",TEXT)
	t.set_color("font_placeholder_color","LineEdit",MUTED)
	t.set_color("caret_color","LineEdit",GOLD)
	t.set_color("selection_color","LineEdit",Color("566579"))
	for kind in ["VScrollBar","HScrollBar"]:
		for state in ["scroll","grabber","grabber_highlight","grabber_pressed"]:
			var s := plate(Color("1e3039") if state == "scroll" else (GOLD if state != "grabber" else Color("69868e")),Color.TRANSPARENT,1)
			s.set_border_width_all(0)
			t.set_stylebox(state,kind,s)
	for state in ["slider","grabber_area","grabber_area_highlight"]:
		var s := plate(EDGE if state == "slider" else GOLD,Color.TRANSPARENT,1)
		s.set_border_width_all(0)
		t.set_stylebox(state,"HSlider",s)
	t.set_stylebox("background","ProgressBar",plate(Color("081117"),EDGE,0))
	t.set_stylebox("fill","ProgressBar",plate(Color("68c8ac"),Color("a8e4c6"),0))
	themes[font_size] = t
	return t

static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal",plate(Color("aa8750"),Color("f3d79e")))
	button.add_theme_stylebox_override("hover",plate(Color("d4b177"),Color("ffe8b9")))
	button.add_theme_stylebox_override("pressed",plate(Color("79603c"),GOLD))
	button.add_theme_color_override("font_color",Color("111b21"))
	button.add_theme_color_override("font_hover_color",Color("111b21"))
	button.add_theme_color_override("font_focus_color",Color("111b21"))
	button.add_theme_stylebox_override("disabled",plate(Color("17232a"),EDGE))
	button.add_theme_color_override("font_disabled_color",MUTED)

static func entrance(node: Control) -> void:
	node.modulate.a = 0.35
	node.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(node,"modulate:a",1.0,0.22)

static func modal_backdrop(root: Control) -> void:
	var scrim := ColorRect.new()
	scrim.name = "ModalBackdrop"
	scrim.color = Color("050b10b8")
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scrim)
	root.move_child(scrim,0)
	entrance(scrim)

static func legacy_tree(node: Node) -> void:
	if node is Control:
		node.theme = build()
		if node is Button:
			for key in ["normal","hover","pressed","focus","disabled"]: node.remove_theme_stylebox_override(key)
		elif node is Panel or node is PanelContainer: node.remove_theme_stylebox_override("panel")
	for child in node.get_children(): legacy_tree(child)

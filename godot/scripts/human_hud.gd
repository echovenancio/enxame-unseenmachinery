extends Control
const HudMeter = preload("res://scripts/hud_meter.gd")
const CARD_SIZE = Vector2(140,58)

var arena
var picture: TextureRect
var cards: Array = []
var links: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_priority = 1 # Project positions after the arena updates its camera and poses.

func reset() -> void:
	for card in cards:
		remove_child(card.panel); card.panel.queue_free()
	cards.clear(); links.clear()
	for i in range(arena.rigs.size()):
		var panel = Panel.new(); panel.size = CARD_SIZE
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var skin = StyleBoxTexture.new(); skin.texture = preload("res://assets/ui_panel.png")
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: skin.set_texture_margin(side,7)
		panel.add_theme_stylebox_override("panel",skin); add_child(panel)
		var title = _label(panel,"HUMANO %02d"%(i+1),Vector2(8,3),12,Color("e5dcc6"))
		var card = {"panel":panel,"title":title}
		for row in [["pain","DOR",21,Color("b84b2d")],["energy","FÔLEGO",38,Color("a39a60")]]:
			_label(panel,row[1],Vector2(8,row[2]),10,Color("b0a38c"))
			var bar = HudMeter.new(); bar.position = Vector2(50,row[2]+4); bar.size = Vector2(56,6)
			bar.tint = row[3]; panel.add_child(bar); card[row[0]] = bar
			var number = _label(panel,"",Vector2(111,row[2]),10,row[3])
			number.size = Vector2(24,14); number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			card[row[0]+"_number"] = number
		cards.append(card)
	update_positions()

func _label(parent: Control, text: String, at: Vector2, font_size: int, tint: Color) -> Label:
	var label = Label.new(); label.text = text; label.position = at
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(label)
	return label

func _process(_delta: float) -> void:
	if visible: update_positions()

func update_positions() -> void:
	if arena==null or arena.sim==null or picture==null: return
	var canvas_scale = picture.size/Vector2(arena.get_viewport().size)
	var occupied: Array[Rect2] = []
	links.clear()
	for i in range(cards.size()):
		var card: Dictionary = cards[i]; var rig: Dictionary = arena.rigs[i]
		var h: Dictionary = arena.sim.humans[i]
		card.pain.value = minf(h.pain,100.0); card.energy.value = h.stamina
		card.pain_number.text = "%.0f"%minf(h.pain,100.0)
		card.energy_number.text = "%.0f%%"%h.stamina
		var anchor: Vector3 = rig.badge.global_position
		var point: Vector2 = arena.camera.unproject_position(anchor)*canvas_scale
		card.panel.visible = rig.root.visible and not arena.camera.is_position_behind(anchor) and Rect2(Vector2.ZERO,size).has_point(point)
		if not card.panel.visible: continue
		var chosen = Rect2(point-Vector2(CARD_SIZE.x*0.5,CARD_SIZE.y+12),CARD_SIZE)
		var found = false
		# Spread nearby cards without covering one another; a leader keeps each owner clear.
		for row in range(8):
			for column in [0,-1,1,-2,2,-3,3,-4,4]:
				var at = point-Vector2(CARD_SIZE.x*0.5,CARD_SIZE.y+12)
				at += Vector2(column*(CARD_SIZE.x+6),-row*(CARD_SIZE.y+6))
				at.x = clampf(at.x,6,maxf(6,size.x-CARD_SIZE.x-6))
				at.y = clampf(at.y,138,maxf(138,size.y-CARD_SIZE.y-110))
				var candidate = Rect2(at.round(),CARD_SIZE)
				if candidate.grow(10).has_point(point): continue
				var overlaps = false
				for other in occupied:
					if candidate.grow(3).intersects(other): overlaps = true; break
				if not overlaps:
					chosen = candidate; found = true; break
			if found: break
		card.panel.visible = found
		if not found: continue
		card.panel.position = chosen.position; occupied.append(chosen)
		var selected: bool = i==arena.selected_human
		card.title.add_theme_color_override("font_color",Color("c3a16a") if selected else Color("e5dcc6"))
		var start = Vector2(clampf(point.x,chosen.position.x+8,chosen.end.x-8),clampf(point.y,chosen.position.y,chosen.end.y))
		links.append({"index":i,"from":start,"to":point,"rect":chosen,"selected":selected})
	queue_redraw()

func _draw() -> void:
	for link in links:
		var tint = Color("c3a16a") if link.selected else Color("7c735c")
		draw_line(link.from+Vector2(1,1),link.to+Vector2(1,1),Color("090a08"),3)
		draw_line(link.from,link.to,tint,1)
		draw_rect(Rect2(link.to-Vector2.ONE,Vector2.ONE*3),tint)
		if link.selected: draw_rect(link.rect.grow(1),tint,false,1)

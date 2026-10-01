extends Control

var max_value = 100.0
var value = 0.0:
	set(next):
		value = next
		queue_redraw()
var tint = Color("b8472d")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var rect = Rect2(Vector2.ZERO,size)
	draw_rect(rect.grow(2),Color("090a08"))
	draw_rect(rect.grow(1),Color("7c735c"),false,1)
	draw_rect(rect,Color("29251e"))
	var cells = maxi(1,int(size.x/7.0))
	var full = clampf(value/max_value,0,1)*cells
	for i in range(cells):
		var x = float(i)*size.x/cells
		var width = maxf(1.0,size.x/cells-1.0)
		var color = tint if i+0.5<=full else Color("353128")
		draw_rect(Rect2(x,0,width,size.y),color)
		if i+0.5<=full:
			draw_line(Vector2(x,1),Vector2(x+width,1),tint.lightened(0.25),1)
	draw_line(Vector2.ZERO,Vector2(size.x,0),Color("ada18b"),1)
	draw_line(Vector2(0,size.y),size,Color("090a08"),2)

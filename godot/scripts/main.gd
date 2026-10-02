extends Control
const Simulation = preload("res://scripts/simulation.gd")
const Arena = preload("res://scripts/arena.gd")
const POST = preload("res://shaders/post.gdshader")
const HumanHUD = preload("res://scripts/human_hud.gd")
const BG = Color("121110")
const PANEL = Color("211e1a")
const EDGE = Color("5c5140")
const TEXT = Color("e5dcc6")
const MUTED = Color("b0a38c")
const GOLD = Color("c3a16a")
const RED = Color("cf7754")

var sim = Simulation.new()
var arena
var viewport3d: SubViewport
var picture: TextureRect
var human_hud
var post: ShaderMaterial
var topbar: Panel
var sidebar: Panel
var side_scroll: ScrollContainer
var side_content: VBoxContainer
var footer: Panel
var toolbar: HFlowContainer
var metrics: Control
var log_panel: Panel
var event_label: Label
var status_label: Label
var clock_label: Label
var detail_label: Label
var precision_label: Label
var stat_labels = {}
var render_label: Label
var log_button: Button
var log_expanded = false
var fields = {}
var start_button: Button
var pause_button: Button
var mobile_button: Button
var model_dialog: AcceptDialog
var running = false
var ever_started = false
var speed = 1.0
var accumulator = 0.0
var ui_elapsed = 0.0
var sim_cost_us = 0
var config_dirty = false
var mobile_controls = false
var mobile = false
var suppress_signals = false
var global_human = {"mass":78.0,"height":1.78,"fitness":0.60,"courage":0.6,"shoes":false}
var overrides = {}
var last_target = 0
var quality = 0
var drag = false
var selected_preset = 0
var budget_alert = false
var download_callback
var last_export = ""
var touches = {}
var stat_panels = {}
var config_tabs: TabContainer
var tab_scrolls: Array = []
var menu_shade: ColorRect
var resume_after_menu = false
var action_label: Label
var menu_title: Label
var legend_label: Label

func _ready() -> void:
	_build_theme()
	_build_view()
	_build_header()
	_build_sidebar()
	_build_hud()
	_build_model_dialog()
	get_viewport().size_changed.connect(_resize_layout)
	_fit_web_scale()
	_resize_layout()
	prepare_round()
	# Automated smoke scenarios are command-line only; production opens a prepared arena.
	var args = OS.get_cmdline_user_args()
	if "--autostart" in args: start_round()
	if "--capture" in args:
		_capture.call_deferred()

func _build_theme() -> void:
	var t = Theme.new()
	t.default_font = load("res://assets/game_font.fnt")
	t.default_font_size = 16
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for cls in ["Label","Button","CheckButton","OptionButton","SpinBox","LineEdit","PopupMenu"]:
		t.set_color("font_color",cls,TEXT)
		t.set_color("font_hover_color",cls,GOLD)
		t.set_color("font_pressed_color",cls,GOLD)
	for cls in ["Button","OptionButton","LineEdit","PopupMenu"]:
		t.set_stylebox("normal",cls,_skin("ui_button"))
		t.set_stylebox("hover",cls,_skin("ui_selected"))
		t.set_stylebox("pressed",cls,_skin("ui_selected"))
		t.set_stylebox("focus",cls,_style(Color.TRANSPARENT,GOLD))
		t.set_stylebox("panel",cls,_skin("ui_panel"))
		t.set_stylebox("normal","LineEdit",_style(Color("161411"),EDGE))
	t.set_stylebox("panel","PopupMenu",_style(PANEL,EDGE))
	t.set_constant("v_separation","VBoxContainer",8)
	t.set_constant("h_separation","HBoxContainer",10)
	t.set_stylebox("background","ProgressBar",_meter_style(Color("42392e")))
	t.set_stylebox("fill","ProgressBar",_meter_style(GOLD))
	for cls in ["Label","Button","OptionButton"]:
		t.set_color("font_shadow_color",cls,Color(0,0,0,0.95))
		t.set_constant("shadow_offset_x",cls,2)
		t.set_constant("shadow_offset_y",cls,2)
	t.set_stylebox("panel","TabContainer",StyleBoxEmpty.new())
	for state in ["tab_selected","tab_unselected","tab_hovered"]:
		var tab_skin = _skin("ui_button" if state=="tab_unselected" else "ui_selected")
		tab_skin.content_margin_left = 5; tab_skin.content_margin_right = 5
		t.set_stylebox(state,"TabContainer",tab_skin)
	t.set_color("font_selected_color","TabContainer",TEXT)
	t.set_color("font_unselected_color","TabContainer",MUTED)
	t.set_font_size("font_size","TabContainer",14)
	theme = t

func _skin(name_value: String) -> StyleBoxTexture:
	var skin = StyleBoxTexture.new()
	skin.texture = load("res://assets/"+name_value+".png")
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		skin.set_texture_margin(side,7)
		skin.set_content_margin(side,10)
	return skin

func _meter_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new(); style.bg_color = color
	style.content_margin_top = 0; style.content_margin_bottom = 0
	style.content_margin_left = 0; style.content_margin_right = 0
	return style

func _style(fill: Color, border: Color = EDGE, width: int = 1) -> StyleBoxFlat:
	var s = StyleBoxFlat.new(); s.bg_color = fill
	s.border_color = border; s.set_border_width_all(width)
	s.border_blend = false
	s.shadow_color = Color(0,0,0,0.32); s.shadow_size = 3; s.shadow_offset = Vector2(0,2)
	s.content_margin_left = 10; s.content_margin_right = 10
	s.content_margin_top = 8; s.content_margin_bottom = 8
	return s

func _panel(parent: Node, fill: Color = PANEL) -> Panel:
	var p = Panel.new(); p.add_theme_stylebox_override("panel",_skin("ui_panel"))
	parent.add_child(p); return p

func _label(text: String, font_size: int = 14, color: Color = TEXT) -> Label:
	var l = Label.new(); l.text = text
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(text: String, callback: Callable) -> Button:
	var b = Button.new(); b.text = text; b.custom_minimum_size.y = 44
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback); return b

func _build_view() -> void:
	var background = ColorRect.new(); background.color = BG; background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(background)
	viewport3d = SubViewport.new(); viewport3d.size = Vector2i(800,600)
	viewport3d.own_world_3d = true; viewport3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport3d.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport3d)
	arena = Arena.new(); viewport3d.add_child(arena)
	picture = TextureRect.new(); picture.texture = viewport3d.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	post = ShaderMaterial.new(); post.shader = POST
	picture.material = post
	picture.gui_input.connect(_view_input)
	add_child(picture)
	human_hud = HumanHUD.new(); human_hud.arena = arena; human_hud.picture = picture
	add_child(human_hud)

func _build_header() -> void:
	topbar = _panel(self,Color("171410"))
	topbar.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	topbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var brand = _label("ENXAME",32,TEXT); brand.position = Vector2(18,11); topbar.add_child(brand)
	var version = _label("HUMANOS × FORMIGAS",14,MUTED); version.position = Vector2(148,18); topbar.add_child(version)
	version.name = "Subtitle"
	mobile_button = _button("MENU",_toggle_controls); topbar.add_child(mobile_button)
	var model = _button("Modelo",func():model_dialog.popup_centered(Vector2i(mini(720,int(get_viewport_rect().size.x)-24),mini(700,int(get_viewport_rect().size.y)-36))))
	model.name = "Model"; topbar.add_child(model)
	status_label = _label("PRONTO",14,GOLD); topbar.add_child(status_label)
	clock_label = _label("00:00.0",20,TEXT); topbar.add_child(clock_label)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _section(title: String) -> void:
	var pad = Control.new(); pad.custom_minimum_size.y = 8; side_content.add_child(pad)
	side_content.add_child(_label(title,14,GOLD))
	var line = ColorRect.new(); line.color = Color("514b3d"); line.custom_minimum_size.y = 1; side_content.add_child(line)

func _config_page(title: String) -> void:
	var scroll = ScrollContainer.new(); scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	config_tabs.add_child(scroll); tab_scrolls.append(scroll)
	side_scroll = scroll
	side_content = VBoxContainer.new(); side_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_content.add_theme_constant_override("separation",10)
	scroll.add_child(side_content)

func _spin(key: String, title: String, minimum: float, maximum: float, step: float, value: float, suffix: String = "") -> SpinBox:
	var row = HBoxContainer.new(); side_content.add_child(row)
	var l = _label(title); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(l)
	var input = SpinBox.new(); input.min_value = minimum; input.max_value = maximum
	input.step = step; input.value = value; input.suffix = suffix
	input.custom_minimum_size = Vector2(150 if key=="ants" else 118,40)
	row.add_child(input); fields[key] = input
	input.value_changed.connect(func(_v):_field_changed(key))
	return input

func _select(key: String, title: String, items: Array, selected: int = 0) -> OptionButton:
	side_content.add_child(_label(title,13,MUTED))
	var input = OptionButton.new(); input.custom_minimum_size.y = 38
	for item in items: input.add_item(str(item))
	input.selected = selected; side_content.add_child(input); fields[key] = input
	input.item_selected.connect(func(_v):_field_changed(key))
	return input

func _check(key: String, title: String, value: bool = false) -> CheckButton:
	var b = CheckButton.new(); b.text = title; b.button_pressed = value
	b.custom_minimum_size.y = 36; side_content.add_child(b); fields[key] = b
	b.toggled.connect(func(_v):_field_changed(key))
	return b

func _build_sidebar() -> void:
	menu_shade = ColorRect.new(); menu_shade.color = Color(0.025,0.026,0.020,0.79)
	menu_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(menu_shade)
	sidebar = _panel(self)
	menu_title = _label("NOVA RODADA",24,TEXT); sidebar.add_child(menu_title)
	config_tabs = TabContainer.new(); config_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	sidebar.add_child(config_tabs)
	_config_page("LUTA")
	var presets = GridContainer.new(); presets.columns = 2; side_content.add_child(presets)
	for i in range(4):
		var names = ["CONTATO","1 MILHÃO","10 MI","TOCANDIRA"]
		var b = _button(names[i],_preset.bind(i)); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size",14); presets.add_child(b)
	_section("PARTICIPANTES")
	_spin("ants","Formigas",0,Simulation.MAX_POPULATION,1,12000)
	_spin("humans","Humanos",0,32,1,2)
	var items: Array = []
	for s in Simulation.PROFILES: items.append(s.name)
	_select("species","Espécie de formiga",items)
	precision_label = _label("",12,MUTED); precision_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_content.add_child(precision_label)
	_select("scenario","Contexto da colônia",["Defesa do ninho","Exploração sem ninho","Colônia em alarme"])
	_config_page("CORPO")
	_section("HUMANOS")
	_spin("human_target","Editar humano",0,32,1,0)
	var tip = _label("0 = todos · 1–32 = indivíduo",12,MUTED); side_content.add_child(tip)
	_spin("mass","Peso",40,180,1,78,"kg")
	_spin("height","Altura",1.30,2.20,0.01,1.78,"m")
	_spin("fitness","Preparo físico",0,100,5,60,"%")
	_spin("courage","Tolerância",0,100,5,60,"%")
	_check("shoes","Calçado fechado",false)
	_select("behaviour","Comportamento humano",["Reação automática","Evitar formigas","Defender / pisar","Permanecer imóvel"])
	_config_page("ARENA")
	_section("ARENA E AMBIENTE")
	_spin("size","Diâmetro",4,30,1,8,"m")
	var surfaces: Array = []
	for s in Simulation.SURFACES: surfaces.append(s.name)
	_select("surface","Piso",surfaces)
	_spin("temperature","Temperatura",0,50,1,28,"°C")
	_spin("humidity","Umidade",0,100,5,65,"%")
	_spin("wind","Vento",0,15,0.5,0,"m/s")
	_spin("rain","Chuva",0,30,1,0,"mm/h")
	_check("escape","Permitir fuga pela borda",false)
	_section("RODADA")
	_spin("duration","Duração",30,3600,30,600,"s")
	_spin("seed","Semente",1,999999,1,1977)
	var last = _label("Mesma semente + configuração = mesma rodada.\nMudanças são aplicadas ao reiniciar.",12,MUTED)
	last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; side_content.add_child(last)
	_config_page("VISUAL")
	_section("CÂMERA E ESCALA")
	_select("camera","Câmera",["Orbital","Vista superior","Seguir humano"])
	_select("magnification","Tamanho visual das formigas",["Escala real 1:1","Ampliação 8×","Ampliação 16×","Ampliação 32×"],1)
	_check("pheromone","Exibir feromônios",false)
	_check("retro","Efeito PS1",true)
	side_content.add_child(_label("A ampliação não altera a física.",12,MUTED))
	var zoom_row = HBoxContainer.new(); side_content.add_child(zoom_row)
	zoom_row.add_child(_button("Aproximar",func():arena.zoom(-1.0)))
	zoom_row.add_child(_button("Afastar",func():arena.zoom(1.0)))
	side_content.add_child(_button("Exportar CSV",export_csv))
	side_content.add_child(_button("COMO FUNCIONA",func():model_dialog.popup_centered(Vector2i(mini(720,int(get_viewport_rect().size.x)-24),mini(700,int(get_viewport_rect().size.y)-36)))))
	side_content.add_child(_button("REGISTRO DA RODADA",func():log_expanded = true; mobile_controls = false; _resize_layout()))
	footer = _panel(sidebar,Color("2a2218"))
	footer.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	start_button = _button("ENTRAR NA ARENA",start_round)
	start_button.add_theme_stylebox_override("normal",_skin("ui_selected"))
	start_button.add_theme_color_override("font_color",TEXT)
	footer.add_child(start_button)
	legend_label = _label("ARRASTE PARA OLHAR · PINÇA PARA APROXIMAR",12,MUTED)
	legend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; footer.add_child(legend_label)

func _build_hud() -> void:
	metrics = Control.new(); metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(metrics)
	for data in [["human","HUMANOS","02/02",TEXT],["ants","FORMIGAS","12.000",TEXT]]:
		var p = Panel.new(); p.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE; metrics.add_child(p); stat_panels[data[0]] = p
		var title = _label(data[1],14,MUTED); p.add_child(title)
		var value = _label(data[2],24,data[3]); p.add_child(value); stat_labels[data[0]] = value
	toolbar = HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation",6)
	toolbar.add_theme_constant_override("v_separation",6); add_child(toolbar)
	pause_button = _button("INICIAR",toggle_pause); toolbar.add_child(pause_button)
	pause_button.add_theme_stylebox_override("normal",_skin("ui_selected"))
	toolbar.add_child(_button("REFAZER",prepare_round))
	var speed_select = OptionButton.new(); speed_select.custom_minimum_size = Vector2(68,44)
	for text_value in ["0,5×","1×","4×","8×","16×","32×"]: speed_select.add_item(text_value)
	speed_select.selected = 1; speed_select.item_selected.connect(func(i):speed = [0.5,1.0,4.0,8.0,16.0,32.0][i])
	toolbar.add_child(speed_select)
	var cameras = OptionButton.new(); cameras.custom_minimum_size = Vector2(110,44)
	for text_value in ["ÓRBITA","TOPO","SEGUIR"]: cameras.add_item(text_value)
	cameras.item_selected.connect(func(i):arena.camera_mode = i; fields.camera.selected = i)
	toolbar.add_child(cameras)
	var magnify = OptionButton.new(); magnify.custom_minimum_size = Vector2(144,44)
	for text_value in ["ESCALA 1:1","FORMIGAS 8×","FORMIGAS 16×","FORMIGAS 32×"]: magnify.add_item(text_value)
	magnify.selected = 1; magnify.item_selected.connect(func(i):arena.set_magnification([1.0,8.0,16.0,32.0][i]); fields.magnification.selected = i)
	toolbar.add_child(magnify)
	var scent = _button("RASTROS",func():arena.set_scent(not arena.show_scent))
	scent.toggle_mode = true; toolbar.add_child(scent)
	var retro = _button("PS1",func():_toggle_retro())
	retro.toggle_mode = true; retro.button_pressed = true; toolbar.add_child(retro)
	toolbar.add_child(_button("CSV",export_csv))
	log_panel = _panel(self)
	event_label = _label("Arena preparada.",16,TEXT)
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; log_panel.add_child(event_label)
	detail_label = _label("",14,MUTED)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; log_panel.add_child(detail_label)
	log_button = _button("VOLTAR",func():log_expanded = false; mobile_controls = true; _resize_layout())
	log_panel.add_child(log_button)
	render_label = _label("",13,MUTED); add_child(render_label)
	action_label = _label("",14,TEXT); add_child(action_label)

func _build_model_dialog() -> void:
	model_dialog = AcceptDialog.new(); model_dialog.title = "Como funciona o modelo"
	model_dialog.ok_button_text = "Entendido"
	add_child(model_dialog)
	var scroll = ScrollContainer.new(); scroll.custom_minimum_size = Vector2(300,390)
	model_dialog.add_child(scroll)
	var text = RichTextLabel.new(); text.bbcode_enabled = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; text.fit_content = true
	text.custom_minimum_size.x = 280
	text.text = "[color=#d5b36f][b]Simulação comportamental, sem validação experimental[/b][/color]\n\n" \
		+"Distâncias, velocidades, área das pisadas e tempo usam unidades reais. A ampliação das formigas afeta somente a imagem.\n\n" \
		+"[b]Formigas[/b]\nCaminhada exploratória persistente; alarme local com decaimento; recrutamento condicionado à defesa do ninho; contato com os pés; subida e mordidas ou ferroadas conforme a espécie. Não recebem um alvo global.\n\n" \
		+"[b]Humanos[/b]\nEvitam concentração local, pisam quando estão ameaçados, removem formigas do corpo e acumulam fadiga e dor. Peso, altura, condicionamento, tolerância, calçado, piso e calor modificam as ações.\n\n" \
		+"[b]Escala e desempenho[/b]\nAté 10 milhões de formigas; 6.000 trajetórias no solo. Acima disso, cada agente representa um grupo inteiro. Cada trajetória desenha até 8 detalhes: malhas perto da câmera e silhuetas à distância. O restante aparece numa camada animada de densidade no piso. Formigas no corpo são contabilizadas separadamente. A soma de ativas, removidas e fugitivas conserva a população. Colisões e recrutamento de grupos aproximam uma distribuição; a precisão espacial cai com o agrupamento.\n\n" \
		+"[b]O que é hipótese[/b]\nVelocidades de referência, raio sensorial, probabilidades de contato, esmagamento, retirada, coeficientes de dor e resposta ambiental são parâmetros de um modelo exploratório, não medições deste confronto. Dor 0–100 é um índice interno: não é escala clínica, toxicidade ou chance de morte. Nenhum humano é declarado morto.\n\n" \
		+"[b]Condições de contorno[/b]\nArena regular de oito lados, diâmetro entre faces opostas. Sem fuga: barreira idealizada impede a saída de formigas. Com fuga: uma formiga que alcança a borda sai. Uma única espécie e colônia por rodada; operárias de tamanho médio; terreno homogêneo; sem rainha, reprodução, castas ou contato corporal 3D detalhado.\n\n" \
		+"[b]Fim da rodada[/b]\nHumanos retiram-se após um limiar contínuo de dor ou exaustão. Formigas podem ser removidas ou fugir. O encerramento por tempo admite coexistência: não força um vencedor.\n\n" \
		+"[b]Referências de comportamento[/b]\nNC State Extension: Biology & Behavior of Red Imported Fire Ant.\nUF/IFAS: Camponotus floridanus, Pheidole megacephala.\nHaddad et al., 2005: ferroadas de Paraponera / Dinoponera.\nSchmidt, 2019: dor e letalidade não são equivalentes.\nAs fontes completas estão no arquivo MODEL.md do projeto.\n\n" \
		+"[b]Controles[/b]\nArraste a arena para orbitar; roda do mouse ou gesto de pinça para aproximar. Espaço pausa; R prepara novamente; 1 / 2 / 3 trocam a câmera."
	scroll.add_child(text)

func _field_changed(key: String) -> void:
	if suppress_signals: return
	if key=="camera": arena.camera_mode = fields.camera.selected; return
	if key=="magnification": arena.set_magnification([1.0,8.0,16.0,32.0][fields.magnification.selected]); return
	if key=="pheromone": arena.set_scent(fields.pheromone.button_pressed); return
	if key=="retro":
		post.set_shader_parameter("enabled",fields.retro.button_pressed)
		arena.set_snap(fields.retro.button_pressed)
		quality = 0 if fields.retro.button_pressed else 1; _resize_layout(); return
	if key=="human_target":
		_load_human_target(int(fields.human_target.value)); return
	if key=="humans":
		fields.human_target.max_value = fields.humans.value
	if key in ["mass","height","fitness","courage","shoes"]:
		var profile = {"mass":fields.mass.value,"height":fields.height.value,"fitness":fields.fitness.value/100.0,"courage":fields.courage.value/100.0,"shoes":fields.shoes.button_pressed}
		var target = int(fields.human_target.value)
		if target==0: global_human = profile; overrides.clear()
		else: overrides[target-1] = profile
	config_dirty = true
	start_button.text = "APLICAR E ENTRAR" if ever_started else "ENTRAR NA ARENA"
	_update_precision()
	if not running and not ever_started:
		# Coalesce multiple spinbox changes into one prepare, keeping inputs snappy.
		if not has_meta("prepare_queued"):
			set_meta("prepare_queued",true); _queued_prepare.call_deferred()

func _queued_prepare() -> void:
	remove_meta("prepare_queued")
	if not running and not ever_started: prepare_round()

func _load_human_target(target: int) -> void:
	var profile = global_human if target==0 else overrides.get(target-1,global_human)
	suppress_signals = true
	fields.mass.value = profile.mass; fields.height.value = profile.height
	fields.fitness.value = profile.fitness*100.0; fields.courage.value = profile.courage*100.0
	fields.shoes.button_pressed = profile.shoes
	suppress_signals = false; last_target = target
	if arena!=null: arena.selected_human = maxi(0,target-1)

func _options() -> Dictionary:
	var profiles: Array = []
	for i in range(int(fields.humans.value)): profiles.append(overrides.get(i,global_human).duplicate())
	return {"ants":int(fields.ants.value),"humans":int(fields.humans.value),"species":fields.species.selected,
		"scenario":fields.scenario.selected,"behaviour":fields.behaviour.selected,"size":fields.size.value,
		"surface":fields.surface.selected,"temperature":fields.temperature.value,"humidity":fields.humidity.value,
		"wind":fields.wind.value,"rain":fields.rain.value,"escape":fields.escape.button_pressed,
		"duration":fields.duration.value,"seed":int(fields.seed.value),"human_profiles":profiles}

func prepare_round() -> void:
	running = false; ever_started = false; accumulator = 0.0; budget_alert = false
	sim.configure(_options()); arena.set_simulation(sim); human_hud.reset()
	config_dirty = false; start_button.text = "ENTRAR NA ARENA"
	pause_button.text = "INICIAR"; _update_precision(); _update_hud()

func start_round() -> void:
	if config_dirty or sim.finished or not ever_started:
		sim.configure(_options()); arena.set_simulation(sim); human_hud.reset(); accumulator = 0.0
	ever_started = true; running = not sim.finished
	config_dirty = false; start_button.text = "NOVA RODADA"
	pause_button.text = "PAUSAR"
	mobile_controls = false; log_expanded = false; resume_after_menu = false; _resize_layout()
	_update_hud()

func toggle_pause() -> void:
	if not ever_started: start_round(); return
	if sim.finished: prepare_round(); start_round(); return
	running = not running; pause_button.text = "PAUSAR" if running else "CONTINUAR"
	_update_hud()

func _preset(index: int) -> void:
	suppress_signals = true
	fields.ants.value = [12000,1000000,10000000,1500][index]
	fields.humans.value = [2,4,4,1][index]
	fields.species.selected = 1 if index==3 else 0
	fields.scenario.selected = 0
	fields.size.value = 8
	fields.temperature.value = 28; fields.humidity.value = 65
	fields.rain.value = 0; fields.wind.value = 0
	fields.behaviour.selected = 0
	fields.surface.selected = 0
	fields.escape.button_pressed = false
	fields.human_target.value = 0; fields.human_target.max_value = fields.humans.value
	global_human = {"mass":78.0,"height":1.78,"fitness":0.6,"courage":0.6,"shoes":false}
	overrides.clear(); _load_human_target(0)
	suppress_signals = false
	prepare_round()

func _update_precision() -> void:
	if precision_label==null: return
	var s = Simulation.PROFILES[fields.species.selected]
	precision_label.text = s.latin+"\n"+s.note
	if fields.ants.value>Simulation.MAX_AGENTS:
		precision_label.text += "\nAgrupamento automático acima de 6.000."

func _process(delta: float) -> void:
	ui_elapsed += delta
	arena.simulation_running = running
	if running:
		accumulator += minf(delta,0.15)*speed
		var begin = Time.get_ticks_usec()
		var ticks = 0
		while accumulator>=Simulation.STEP and ticks<24:
			sim.tick(); accumulator -= Simulation.STEP; ticks += 1
			if sim.finished: running = false; accumulator = 0.0; break
			if Time.get_ticks_usec()-begin>18000: break
		sim_cost_us = Time.get_ticks_usec()-begin
		# Never discard simulation time or inflate results to match a requested speed.
		budget_alert = accumulator>0.7
		if accumulator>3.0: accumulator = 3.0 # real-time backlog bounded; virtual time advances only in tick().
	if ui_elapsed>=0.2:
		ui_elapsed = 0.0; _update_hud()

func _number(value: int) -> String:
	var s = str(value); var output = ""
	for i in range(s.length()):
		if i>0 and (s.length()-i)%3==0: output += "."
		output += s[i]
	return output

func _time(seconds: float) -> String:
	return "%02d:%04.1f"%[int(seconds/60.0),fmod(seconds,60.0)]

func _compact(value: int) -> String:
	if value>=1000000: return ("%.2f mi"%(value/1000000.0)).replace(".",",")
	if value>=10000: return ("%.1f mil"%(value/1000.0)).replace(".",",")
	return _number(value)

func _update_hud() -> void:
	if status_label==null: return
	var stats = sim.summary()
	stat_labels.human.text = "%02d/%02d"%[stats.active,sim.humans.size()]
	stat_labels.ants.text = _compact(stats.alive)
	stat_labels.ants.tooltip_text = _number(stats.alive)+" formigas vivas, incluindo as que estão nos corpos."
	clock_label.text = _time(sim.elapsed)
	status_label.text = "ENCERRADO" if sim.finished else ("EM CURSO" if running else ("PAUSADO" if ever_started else "PRONTO"))
	status_label.add_theme_color_override("font_color",RED if sim.finished else GOLD)
	if sim.humans.size()>0:
		var index = clampi(arena.selected_human,0,sim.humans.size()-1)
		action_label.text = "%02d · %s"%[index+1,str(sim.humans[index].state).to_upper()]
	else: action_label.text = "ARENA VAZIA"
	if sim.finished: pause_button.text = "NOVA"
	var entries: Array = []
	for i in range(maxi(0,sim.events.size()-3),sim.events.size()):
		var e = sim.events[i]; entries.append("%s  %s"%[_time(e.time),e.message])
	event_label.text = "\n".join(entries)
	var contact_word = "Ferroadas" if int(sim.config.species)<2 else "Mordidas"
	detail_label.text = "Removidas %s · No corpo %s\n%s %s · Fugitivas %s"%[_compact(stats.crushed),_compact(stats.attached),contact_word,_compact(stats.exposures),_compact(stats.escaped)]
	render_label.text = ("INDIVÍDUOS" if stats.cohort==1 else "GRUPOS ATÉ "+_number(stats.cohort))+" · VISUAL "+str(int(arena.magnification))+"×"
	if mobile: render_label.text = ("INDIVÍDUOS" if stats.cohort==1 else "GRUPOS "+_number(stats.cohort))+" · "+str(int(arena.magnification))+"×"
	if config_dirty: render_label.text += " · AJUSTES PENDENTES"
	render_label.tooltip_text = "%s trajetórias · %s detalhes 3D · densidade no piso · %.0f FPS"%[_number(stats.agents),_number(arena.detail_ant_count),Engine.get_frames_per_second()]
	if budget_alert: render_label.text += " · TEMPO LIMITADO"
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.formicariumState = "+JSON.stringify({"time":sim.elapsed,"alive":stats.alive,"active":stats.active,"running":running,"fps":Engine.get_frames_per_second(),"agents":stats.agents,"population":sim.population,"conserved":sim.conserved_population(),"detail_ants":arena.detail_ant_count,"density_ants":arena.density_population,"ui_version":3}),true)

func _toggle_controls() -> void:
	mobile_controls = not mobile_controls
	if mobile_controls:
		resume_after_menu = running; running = false
	else:
		if resume_after_menu and not sim.finished: running = true
		resume_after_menu = false
	_update_hud(); _resize_layout()

func _toggle_retro() -> void:
	var enabled = not bool(post.get_shader_parameter("enabled"))
	post.set_shader_parameter("enabled",enabled); arena.set_snap(enabled)
	quality = 0 if enabled else 1; _resize_layout()

func _fit_web_scale() -> void:
	if not OS.has_feature("web"): return
	var raw = JavaScriptBridge.eval("JSON.stringify({w:window.innerWidth,h:window.innerHeight})",true)
	if raw==null: return
	var dims = JSON.parse_string(str(raw))
	if dims is Dictionary:
		var size_value = Vector2i(int(dims.w),int(dims.h))
		if get_window().content_scale_size!=size_value:
			get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			get_window().content_scale_size = size_value

func _resize_layout() -> void:
	if sidebar==null: return
	_fit_web_scale()
	var screen = get_viewport_rect().size
	mobile = screen.x<780.0
	var inset = 18.0 if screen.x>=350 else 14.0
	topbar.position = Vector2.ZERO; topbar.size = Vector2(screen.x,90)
	topbar.get_node("Subtitle").visible = false
	topbar.get_child(0).visible = mobile_controls
	topbar.get_child(0).position = Vector2(inset,16)
	topbar.get_child(0).add_theme_font_size_override("font_size",28)
	var model: Button = topbar.get_node("Model")
	model.visible = mobile_controls and not mobile
	model.position = Vector2(screen.x-202,16); model.size = Vector2(92,44)
	mobile_button.text = "VOLTAR" if mobile_controls else "MENU"
	mobile_button.position = Vector2(screen.x-inset-88,16); mobile_button.size = Vector2(88,44)
	clock_label.position = Vector2(screen.x*0.5-48,22); clock_label.size = Vector2(96,24)
	clock_label.add_theme_font_size_override("font_size",16 if mobile else 20)
	clock_label.visible = not mobile_controls and not log_expanded
	status_label.position = Vector2(screen.x*0.5-72,48); status_label.size = Vector2(144,20)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size",12 if mobile else 14)
	status_label.visible = not mobile_controls and not log_expanded
	var side_w = minf(570.0,screen.x-28.0)
	var side_h = minf(718.0,screen.y-102.0)
	sidebar.position = Vector2((screen.x-side_w)*0.5,78+(screen.y-102-side_h)*0.5)
	sidebar.size = Vector2(side_w,side_h); sidebar.visible = mobile_controls
	menu_title.position = Vector2(20,16); menu_title.size = Vector2(side_w-40,30)
	menu_title.text = "PAUSA" if ever_started and not sim.finished else "NOVA RODADA"
	config_tabs.position = Vector2(18,62); config_tabs.size = Vector2(side_w-36,side_h-160)
	for scroll in tab_scrolls:
		scroll.get_child(0).custom_minimum_size.x = side_w-56
	footer.position = Vector2(12,side_h-86); footer.size = Vector2(side_w-24,74)
	start_button.position = Vector2(8,0); start_button.size = Vector2(side_w-40,46)
	legend_label.position = Vector2(4,54); legend_label.size = Vector2(side_w-32,18)
	legend_label.text = "ARRASTE · PINÇA PARA APROXIMAR" if mobile else "ARRASTE PARA OLHAR · RODA PARA APROXIMAR · ESC PARA O MENU"
	picture.position = Vector2.ZERO; picture.size = screen
	human_hud.position = picture.position; human_hud.size = screen
	human_hud.visible = not mobile_controls and not log_expanded
	var res_h = 360 if quality==0 else 720
	viewport3d.size = Vector2i(maxi(160,int(screen.x/maxf(1.0,screen.y)*res_h)),res_h)
	arena.mobile_quality = mobile
	metrics.position = Vector2.ZERO; metrics.size = screen
	metrics.visible = not mobile_controls and not log_expanded
	var left_w = minf(230.0,(screen.x-48.0)*0.5)
	stat_panels.human.position = Vector2(inset,18); stat_panels.human.size = Vector2(90,50)
	stat_panels.human.get_child(0).position = Vector2.ZERO
	stat_labels.human.position = Vector2(0,18); stat_labels.human.size = Vector2(90,32)
	stat_labels.human.add_theme_font_size_override("font_size",24)
	stat_panels.ants.position = Vector2(screen.x-inset-left_w,76); stat_panels.ants.size = Vector2(left_w,54)
	stat_panels.ants.get_child(0).position = Vector2.ZERO
	stat_panels.ants.get_child(0).size = Vector2(left_w,20)
	stat_panels.ants.get_child(0).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_labels.ants.position = Vector2(0,20); stat_labels.ants.size = Vector2(left_w,32)
	stat_labels.ants.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_labels.ants.add_theme_font_size_override("font_size",24 if mobile else 32)
	var visible_width = 0.0
	for i in range(toolbar.get_child_count()):
		var child = toolbar.get_child(i)
		child.visible = i in [0,2,3] or (i==1 and not mobile)
		child.add_theme_font_size_override("font_size",14 if mobile else 16)
		if i==2: child.custom_minimum_size.x = 64
		if i==3: child.custom_minimum_size.x = 100 if mobile else 120
		if child.visible: visible_width += child.get_combined_minimum_size().x+6
	visible_width -= 6
	toolbar.position = Vector2((screen.x-visible_width)*0.5,screen.y-62)
	toolbar.size = Vector2(visible_width,44)
	toolbar.visible = not mobile_controls and not log_expanded
	action_label.position = Vector2(inset,screen.y-98); action_label.size = Vector2(screen.x-inset*2,24)
	action_label.visible = not mobile_controls and not log_expanded
	log_panel.position = Vector2((screen.x-side_w)*0.5,maxf(86,(screen.y-310)*0.5))
	log_panel.size = Vector2(side_w,310); log_panel.visible = log_expanded
	event_label.position = Vector2(20,20); event_label.size = Vector2(side_w-40,168)
	detail_label.position = Vector2(20,186); detail_label.size = Vector2(side_w-40,62)
	log_button.position = Vector2(20,254); log_button.size = Vector2(side_w-40,44)
	render_label.visible = false
	menu_shade.visible = mobile_controls or log_expanded
	move_child(menu_shade,get_child_count()-1); move_child(sidebar,get_child_count()-1)
	move_child(log_panel,get_child_count()-1); move_child(topbar,get_child_count()-1)
	move_child(model_dialog,get_child_count()-1)

func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT or event.button_index==MOUSE_BUTTON_RIGHT: drag = event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP: arena.zoom(-0.65)
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN: arena.zoom(0.65)
	elif event is InputEventMouseMotion and drag and touches.is_empty():
		arena.orbit(event.relative.x,event.relative.y)
	elif event is InputEventMagnifyGesture:
		arena.zoom((1.0-event.factor)*4.0)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and picture.get_global_rect().has_point(event.position) and not (mobile and mobile_controls):
			touches[event.index] = event.position
		else: touches.erase(event.index)
	elif event is InputEventScreenDrag and touches.has(event.index):
		if touches.size()==1: arena.orbit(event.relative.x,event.relative.y)
		elif touches.size()>=2:
			var points = touches.values()
			var previous_distance = points[0].distance_to(points[1])
			touches[event.index] = event.position; points = touches.values()
			var next_distance = points[0].distance_to(points[1])
			arena.zoom((previous_distance-next_distance)*0.015)
		touches[event.index] = event.position

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if event.keycode==KEY_ESCAPE: _toggle_controls()
	if event.keycode==KEY_SPACE and not mobile_controls: toggle_pause()
	if event.keycode==KEY_R: prepare_round()
	if event.keycode==KEY_1: arena.camera_mode = 0
	if event.keycode==KEY_2: arena.camera_mode = 1
	if event.keycode==KEY_3: arena.camera_mode = 2
	if event.keycode==KEY_PLUS or event.keycode==KEY_EQUAL: arena.zoom(-1.0)
	if event.keycode==KEY_MINUS: arena.zoom(1.0)

func export_csv() -> void:
	var csv = "tempo_s;formigas_ativas;humanos_ativos;dor_media;energia_media;contatos;mordidas_ferroadas\n"
	for row in sim.history:
		csv += "%.1f;%d;%d;%.3f;%.3f;%d;%d\n"%[row.time,row.alive,row.active,row.pain,row.stamina,row.contacts,row.exposures]
	last_export = csv
	var name_value = "enxame-semente-%d.csv"%int(sim.config.seed)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(csv.to_utf8_buffer(),name_value,"text/csv")
	else:
		var path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join(name_value)
		var f = FileAccess.open(path,FileAccess.WRITE)
		if f:
			f.store_string(csv); sim._event("CSV salvo em Downloads: "+name_value)
		else: sim._event("Não foi possível salvar o CSV em Downloads.")

func _capture() -> void:
	for frame in range(80): await get_tree().process_frame
	var image = get_viewport().get_texture().get_image()
	var path = "user://enxame-preview.png"
	image.save_png(path)
	print("CAPTURE_SAVED "+path)
	get_tree().quit()

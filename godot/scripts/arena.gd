extends Node3D
const Sim = preload("res://scripts/simulation.gd")
const RETRO = preload("res://shaders/retro.gdshader")
const ANT_SHADER = preload("res://shaders/ants.gdshader")
const SWARM_SHADER = preload("res://shaders/swarm.gdshader")
const ANT_CARDS = preload("res://shaders/ant_cards.gdshader")

var sim
var stage: Node3D
var rigs: Array = []
var ant_batch: MultiMeshInstance3D
var near_ant_batch: MultiMeshInstance3D
var attached_batch: MultiMeshInstance3D
var scent_batch: MultiMeshInstance3D
var camera: Camera3D
var environment: WorldEnvironment
var yaw = 0.66
var pitch = 0.76
var distance = 12.8
var camera_mode = 0
var magnification = 8.0
var mobile_quality = false
var detail_ant_count = 0
var density_population = 0
var ant_material: ShaderMaterial
var card_material: ShaderMaterial
var near_buffer = PackedFloat32Array()
var near_budget = 512
var near_ant_count = 0
var swarm_material: ShaderMaterial
var density_texture: ImageTexture
var density_image: Image
var density_counts = PackedFloat32Array()
var density_flow_x = PackedFloat32Array()
var density_flow_z = PackedFloat32Array()
var density_elapsed = 0.0
var last_density_tick = -1
var last_ground_tick = -1
var last_ground_camera = Vector3.INF
var last_ground_scale = -1.0
var detail_copies = 8
var motion_time = 0.0
var simulation_running = false
var show_scent = false
var visual_clock = 0.0
var render_elapsed = 0.0
var skin_materials: Array = []
var ant_mesh: ArrayMesh
var ant_buffer = PackedFloat32Array()
var attached_buffer = PackedFloat32Array()
var scent_buffer = PackedFloat32Array()
var materials: Array = []
var snap = true
var selected_human = 0
var fps = 0

func _ready() -> void:
	ant_mesh = _make_ant_mesh()
	camera = Camera3D.new(); add_child(camera)
	camera.current = true; camera.fov = 49.0; camera.near = 0.03; camera.far = 180.0
	environment = WorldEnvironment.new(); add_child(environment)
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045,0.054,0.047)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60,0.62,0.52)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true; env.fog_light_color = Color(0.08,0.095,0.076)
	env.fog_density = 0.014
	environment.environment = env
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65,-32,0)
	sun.light_color = Color(0.98,0.91,0.71); sun.light_energy = 1.15
	sun.shadow_enabled = false
	sun.directional_shadow_max_distance = 35.0
	add_child(sun)
	for color in [Color(0.55,0.36,0.23),Color(0.70,0.49,0.32),Color(0.35,0.25,0.18),Color(0.79,0.62,0.43),Color(0.48,0.31,0.22)]:
		skin_materials.append(_plain(color))

func set_simulation(model) -> void:
	sim = model
	motion_time = 0.0; visual_clock = 0.0
	last_density_tick = -1; last_ground_tick = -1; last_ground_scale = -1.0
	if is_instance_valid(stage):
		remove_child(stage); stage.queue_free()
	stage = Node3D.new(); add_child(stage)
	rigs.clear(); materials.clear()
	distance = sim.radius*2.4+3.2
	_build_chamber()
	_build_cage()
	for i in range(sim.humans.size()): _build_human(i)
	_build_batches()
	_update_camera()
	_update_ants()

func _plain(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _textured(name: String, scale_uv: Vector2 = Vector2.ONE, tint: Color = Color.WHITE, shader: Shader = RETRO) -> ShaderMaterial:
	var m = ShaderMaterial.new(); m.shader = shader
	m.set_shader_parameter("albedo_texture",load("res://assets/"+name+".png"))
	m.set_shader_parameter("texture_scale",scale_uv)
	m.set_shader_parameter("tint",tint)
	m.set_shader_parameter("vertex_snap",snap)
	materials.append(m)
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = BoxMesh.new(); mesh.size = size
	node.mesh = mesh; node.material_override = mat; node.position = pos
	parent.add_child(node)
	return node

func _rod(parent: Node3D, from: Vector3, to: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	var node = _box(parent,Vector3(thickness,thickness,from.distance_to(to)),(from+to)*0.5,mat)
	if from.distance_to(to)>0.001:
		var up = Vector3.FORWARD if absf((to-from).normalized().dot(Vector3.UP))>0.99 else Vector3.UP
		node.look_at_from_position((from+to)*0.5,to,up)
	return node

func _build_chamber() -> void:
	var r = sim.radius
	var wall = _textured("wall",Vector2(10,4))
	var concrete = _textured("concrete",Vector2(16,16),Color(0.52,0.53,0.46))
	var metal = _textured("metal",Vector2(3,2))
	_box(stage,Vector3(r*5.0,0.3,r*5.0),Vector3(0,-0.62,0),concrete)
	_box(stage,Vector3(r*5.0,7.0,0.50),Vector3(0,2.8,-r*2.0),wall)
	_box(stage,Vector3(0.50,7.0,r*5.0),Vector3(-r*2.0,2.8,0),wall)
	for xval in [-r*1.75,-r*0.90,0.0,r*0.90,r*1.75]:
		_box(stage,Vector3(0.3,7.5,0.3),Vector3(xval,3.0,-r*1.8),metal)
		_box(stage,Vector3(0.18,0.20,r*0.55),Vector3(xval,6.6,-r*1.65),metal)
	for side in [-1.0,1.0]:
		for row in range(3):
			var tz = side*(r+1.3+row*0.60)
			_box(stage,Vector3(r*2.0,0.20,0.43),Vector3(0,-0.1+row*0.35,tz),_plain(Color(0.12,0.14,0.11)))
	# Back wall strip lights, geometry and one cheap local lamp.
	var glow = _plain(Color(0.86,0.91,0.65),true)
	for i in range(3):
		var p = Vector3((i-1)*r*0.95,4.8,-r*0.50)
		_box(stage,Vector3(1.25,0.07,0.22),p,glow)
		_rod(stage,p+Vector3(-0.45,0,0),p+Vector3(-0.45,1.5,0),0.02,metal)
		_rod(stage,p+Vector3(0.45,0,0),p+Vector3(0.45,1.5,0),0.02,metal)
	var lamp = OmniLight3D.new(); lamp.position = Vector3(0,3.8,0)
	lamp.light_color = Color(0.84,0.90,0.66); lamp.light_energy = 0.80; lamp.omni_range = r*3.0
	stage.add_child(lamp)

func _octagon_vertices(r: float) -> PackedVector3Array:
	var c = r*tan(PI/8.0)
	return PackedVector3Array([Vector3(-c,0,-r),Vector3(c,0,-r),Vector3(r,0,-c),Vector3(r,0,c),Vector3(c,0,r),Vector3(-c,0,r),Vector3(-r,0,c),Vector3(-r,0,-c)])

func _build_cage() -> void:
	var r = sim.radius
	var verts = _octagon_vertices(r)
	var floor_mesh = SurfaceTool.new(); floor_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(8):
		for p in [Vector3.ZERO,verts[(i+1)%8],verts[i]]:
			floor_mesh.set_uv(Vector2(p.x/(r*2.0)+0.5,p.z/(r*2.0)+0.5))
			floor_mesh.add_vertex(p)
	floor_mesh.generate_normals()
	var floor_node = MeshInstance3D.new(); floor_node.mesh = floor_mesh.commit()
	var names = ["canvas","concrete","sand","soil","wood"]
	floor_node.material_override = _textured(names[int(sim.config.get("surface",0))],Vector2(r*2.8,r*2.8),Color.WHITE,SWARM_SHADER)
	swarm_material = floor_node.material_override
	stage.add_child(floor_node)
	var metal = _plain(Color(0.065,0.083,0.070))
	var trim = _plain(Color(0.37,0.31,0.19))
	var pad = _textured("canvas",Vector2(2,4),Color(0.21,0.24,0.20))
	var wiretool = SurfaceTool.new(); wiretool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(8):
		var a = verts[i]; var b = verts[(i+1)%8]
		_box(stage,Vector3(0.19,2.3,0.19),a+Vector3(0,1.05,0),pad)
		_rod(stage,a+Vector3(0,2.12,0),b+Vector3(0,2.12,0),0.085,metal)
		_rod(stage,a+Vector3(0,0.06,0),b+Vector3(0,0.06,0),0.065,trim)
		_rod(stage,a+Vector3(0,-0.23,0),b+Vector3(0,-0.23,0),0.35,metal)
		var span = a.distance_to(b)
		var dir = (b-a).normalized()
		# A combined low-cost diamond lattice. Near camera panels remain low for visibility.
		var height = 2.05 if (a.z+b.z)<0.0 else 0.58
		var spacing = 0.23
		for j in range(ceili(span/spacing)):
			var start = a+dir*(j*spacing)
			for k in range(ceili(height/spacing)):
				var p = start+Vector3(0,k*spacing+0.1,0)
				for sign_value in [-1.0,1.0]:
					var dest = p+dir*spacing+Vector3(0,sign_value*spacing,0)
					if dest.y<0.05 or dest.y>height: continue
					var off = Vector3(0,0.004,0)
					for q in [p-off,dest-off,dest+off,p-off,dest+off,p+off]: wiretool.add_vertex(q)
	wiretool.generate_normals()
	var wire = MeshInstance3D.new(); wire.mesh = wiretool.commit(); wire.material_override = metal
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(wire)
	# Painted floor markings sit in the physical plane, not an interface illustration.
	var paint = _plain(Color(0.63,0.57,0.38))
	for i in range(8):
		var a = verts[i]*0.83+Vector3(0,0.009,0)
		var b = verts[(i+1)%8]*0.83+Vector3(0,0.009,0)
		_rod(stage,a,b,0.018,paint)
	var label = Label3D.new(); label.text = "E N X A M E"
	label.font_size = 90; label.pixel_size = 0.008
	label.modulate = Color(0.50,0.46,0.30); label.outline_size = 0
	label.rotation_degrees = Vector3(-90,0,0); label.position = Vector3(0,0.012,0)
	label.no_depth_test = false; stage.add_child(label)
	var nest = _box(stage,Vector3(0.35,0.028,0.35),Vector3(sim.nearest_nest.x,0.018,sim.nearest_nest.y),_plain(Color(0.15,0.12,0.07)))
	nest.visible = int(sim.config.get("scenario",0))==0

func _build_human(index: int) -> void:
	var h = sim.humans[index]
	var root = Node3D.new(); root.position = Vector3(h.pos.x,0,h.pos.y); root.rotation.y = h.facing
	stage.add_child(root)
	var figure = Node3D.new(); root.add_child(figure)
	var scale_value = h.height/1.78; figure.scale = Vector3.ONE*scale_value
	var body = Node3D.new(); body.position.y = 0.94; figure.add_child(body)
	var skin = skin_materials[index%skin_materials.size()]
	var shorts = _plain(Color(0.19,0.22,0.17) if index%2==0 else Color(0.38,0.16,0.09))
	var tape = _plain(Color(0.70,0.68,0.53))
	var body_width = clampf(h.mass/78.0,0.70,1.45)
	var torso = MeshInstance3D.new()
	torso.mesh = _taper_mesh(Vector3(0.25*body_width,0.46,0.16),Vector3(0.36*body_width,0.46,0.21))
	torso.material_override = skin; torso.position = Vector3(0,0.21,0); body.add_child(torso)
	var pelvis = MeshInstance3D.new(); pelvis.mesh = _taper_mesh(Vector3(0.32*body_width,0.21,0.23),Vector3(0.27*body_width,0.21,0.19))
	pelvis.material_override = shorts; pelvis.position = Vector3(0,0.81,0); figure.add_child(pelvis)
	_box(body,Vector3(0.12,0.10,0.11),Vector3(0,0.51,0),skin)
	var head = Node3D.new(); head.position.y = 0.67; body.add_child(head)
	var face = MeshInstance3D.new(); face.mesh = _taper_mesh(Vector3(0.15,0.24,0.14),Vector3(0.19,0.24,0.18))
	face.material_override = skin; head.add_child(face)
	_box(head,Vector3(0.18,0.075,0.17),Vector3(0,0.125,-0.005),_plain(Color(0.08,0.072,0.055)))
	_box(head,Vector3(0.04,0.055,0.055),Vector3(0,0,0.097),skin)
	for sign_value in [-1.0,1.0]:
		_box(head,Vector3(0.028,0.025,0.013),Vector3(sign_value*0.052,0.038,0.089),_plain(Color(0.05,0.043,0.032)))
	var arms: Array = []; var forearms: Array = []; var legs: Array = []
	for sign_value in [-1.0,1.0]:
		var arm = Node3D.new(); arm.position = Vector3(sign_value*0.215*body_width,0.42,0); body.add_child(arm)
		_limb(arm,Vector2(0.052,0.052),Vector2(0.040,0.043),0.27,skin)
		var forearm = Node3D.new(); forearm.position = Vector3(0,-0.27,0); arm.add_child(forearm)
		_limb(forearm,Vector2(0.044,0.045),Vector2(0.030,0.032),0.28,skin)
		_box(forearm,Vector3(0.09,0.07,0.095),Vector3(0,-0.20,0),tape)
		_box(forearm,Vector3(0.095,0.12,0.10),Vector3(0,-0.275,0.01),skin)
		arms.append(arm); forearms.append(forearm)
		var leg = Node3D.new(); leg.position = Vector3(sign_value*0.10*body_width,0.78,0); figure.add_child(leg)
		_limb(leg,Vector2(0.070,0.079),Vector2(0.050,0.061),0.34,skin)
		_box(leg,Vector3(0.13,0.12,0.16),Vector3(0,-0.02,0),shorts)
		var lower = Node3D.new(); lower.position = Vector3(0,-0.34,0); leg.add_child(lower)
		_limb(lower,Vector2(0.050,0.055),Vector2(0.032,0.039),0.40,skin)
		var ankle = Node3D.new(); ankle.position.y = -0.40; lower.add_child(ankle)
		var footmat = _plain(Color(0.08,0.09,0.075)) if h.shoes else skin
		_box(ankle,Vector3(0.11,0.075,0.24),Vector3(0,-0.0075,0.062),footmat)
		legs.append({"upper":leg,"lower":lower,"ankle":ankle,"plant":root.to_global(Vector3(leg.position.x,0.045,0.04)*scale_value),"swing":false,"from":Vector3.ZERO,"to":Vector3.ZERO,"yaw":h.facing,"pivot":false,"pivot_time":0.0,"mode":0,"phase_start":0.62})
	var badge = Label3D.new(); badge.text = "%02d"%(index+1)
	badge.font_size = 24; badge.pixel_size = 0.005
	badge.position = Vector3(0,h.height+0.26,0); badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.modulate = Color(0.92,0.82,0.57); badge.outline_size = 4; root.add_child(badge)
	var shadow = MeshInstance3D.new(); var disk = CylinderMesh.new()
	disk.top_radius = 0.27; disk.bottom_radius = 0.27; disk.height = 0.002; disk.radial_segments = 12
	shadow.mesh = disk; shadow.material_override = _plain(Color(0.17,0.18,0.13)); shadow.position.y = 0.004
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root.add_child(shadow)
	rigs.append({"index":index,"root":root,"figure":figure,"body":body,"head":head,"arms":arms,"forearms":forearms,"legs":legs,"badge":badge,"torso":torso,"walk_pose":TAU*0.35,"move":0.0,"withdrawal":0.0,"action_pose":0.0,"last_action":0.0,"action_id":0,"stamp_from":Vector3.ZERO,"stamp_to":Vector3.ZERO,"brush_side":index%2,"clock":0.0})

func _limb(parent: Node3D, top: Vector2, bottom: Vector2, length_value: float, material: Material) -> void:
	var st = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for row in range(2):
		var ring: Array = []
		var radius: Vector2 = top if row==0 else bottom
		for i in range(8):
			var angle = i*TAU/8.0
			ring.append(Vector3(cos(angle)*radius.x,0.0 if row==0 else -length_value,sin(angle)*radius.y))
		rings.append(ring)
	for i in range(8):
		var n = (i+1)%8
		for v in [rings[0][i],rings[1][n],rings[1][i],rings[0][i],rings[0][n],rings[1][n]]: st.add_vertex(v)
		st.add_vertex(Vector3.ZERO); st.add_vertex(rings[0][n]); st.add_vertex(rings[0][i])
		st.add_vertex(Vector3(0,-length_value,0)); st.add_vertex(rings[1][i]); st.add_vertex(rings[1][n])
	st.generate_normals()
	var mesh = MeshInstance3D.new(); mesh.mesh = st.commit(); mesh.material_override = material; parent.add_child(mesh)

func _taper_mesh(bottom: Vector3, top: Vector3) -> ArrayMesh:
	var verts = [Vector3(-bottom.x/2,-bottom.y/2,-bottom.z/2),Vector3(bottom.x/2,-bottom.y/2,-bottom.z/2),Vector3(bottom.x/2,-bottom.y/2,bottom.z/2),Vector3(-bottom.x/2,-bottom.y/2,bottom.z/2),Vector3(-top.x/2,top.y/2,-top.z/2),Vector3(top.x/2,top.y/2,-top.z/2),Vector3(top.x/2,top.y/2,top.z/2),Vector3(-top.x/2,top.y/2,top.z/2)]
	var st = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
		for j in [0,2,1,0,3,2]: st.add_vertex(verts[face[j]])
	st.generate_normals(); return st.commit()

func _make_ant_mesh(copies: int = 1) -> ArrayMesh:
	var st = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for copy in range(copies):
		st.set_uv2(Vector2(copy,0))
		st.set_uv(Vector2.ZERO)
		for part in [{"pos":Vector3(0,0.10,-0.23),"size":Vector3(0.18,0.13,0.23)}, {"pos":Vector3(0,0.13,0.05),"size":Vector3(0.10,0.10,0.14)}, {"pos":Vector3(0,0.15,0.28),"size":Vector3(0.13,0.11,0.13)}]:
			var p: Vector3 = part.pos; var size_value: Vector3 = part.size
			var v = [p+Vector3(size_value.x,0,0),p+Vector3(-size_value.x,0,0),p+Vector3(0,size_value.y,0),p+Vector3(0,-size_value.y,0),p+Vector3(0,0,size_value.z),p+Vector3(0,0,-size_value.z)]
			for face in [[0,2,4],[4,2,1],[1,2,5],[5,2,0],[4,3,0],[1,3,4],[5,3,1],[0,3,5]]:
				for j in face: st.add_vertex(v[j])
		for side in [-1.0,1.0]:
			for j in range(3):
				# Alternating tripod gait: front/rear on one side and middle on the other.
				st.set_uv(Vector2(1,PI*(j%2+(1 if side>0 else 0))))
				var p = Vector3(side*0.06,0.13,-0.10+j*0.13)
				var elbow = Vector3(side*0.29,0.11,-0.18+j*0.22)
				var toe = Vector3(side*0.39,0.018,-0.26+j*0.28)
				for segment in [[p,elbow],[elbow,toe]]:
					var off = Vector3(0,0,0.018)
					for q in [segment[0]-off,segment[1]-off,segment[1]+off]: st.add_vertex(q)
			st.set_uv(Vector2(2,side))
			var p = Vector3(side*0.065,0.17,0.34)
			var end = Vector3(side*0.18,0.18,0.50)
			for q in [p,end-Vector3(0.009,0,0),end+Vector3(0.009,0,0)]: st.add_vertex(q)
	st.generate_normals(); return st.commit()

func _new_batch(count: int, mesh: Mesh, mat: Material, custom: bool = false) -> MultiMeshInstance3D:
	var node = MultiMeshInstance3D.new(); var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D; multimesh.use_colors = true
	multimesh.use_custom_data = custom
	multimesh.instance_count = maxi(1,count); multimesh.mesh = mesh
	multimesh.visible_instance_count = 0
	node.multimesh = multimesh; node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(node); return node

func _build_batches() -> void:
	detail_copies = 4 if mobile_quality else 8
	near_budget = 256 if mobile_quality else 512
	ant_material = ShaderMaterial.new(); ant_material.shader = ANT_SHADER
	ant_material.set_shader_parameter("ant_color",sim.species.color)
	card_material = ShaderMaterial.new(); card_material.shader = ANT_CARDS
	card_material.set_shader_parameter("ant_color",sim.species.color)
	ant_batch = _new_batch(sim.agent_count,_make_ant_cards(detail_copies),card_material,true)
	near_ant_batch = _new_batch(mini(near_budget,sim.agent_count),_make_ant_mesh(detail_copies),ant_material,true)
	attached_batch = _new_batch(sim.humans.size()*24,ant_mesh,ant_material,true)
	ant_buffer.resize(maxi(1,sim.agent_count)*20); ant_buffer.fill(0.0)
	near_buffer.resize(maxi(1,mini(near_budget,sim.agent_count))*20); near_buffer.fill(0.0)
	attached_buffer.resize(maxi(1,sim.humans.size()*24)*20); attached_buffer.fill(0.0)
	var plane = PlaneMesh.new(); plane.size = Vector2(sim.cell_size*0.98,sim.cell_size*0.98)
	var scentmat = _plain(Color(0.72,0.45,0.12,0.32),true)
	scentmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scentmat.vertex_color_use_as_albedo = true
	scent_batch = _new_batch(Sim.GRID*Sim.GRID,plane,scentmat)
	scent_batch.visible = show_scent
	scent_buffer.resize(Sim.GRID*Sim.GRID*16); scent_buffer.fill(0.0)
	_build_swarm_surface()
	density_elapsed = 0.0; _update_density()

func _make_ant_cards(copies: int) -> ArrayMesh:
	var st = SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for copy in range(copies):
		st.set_uv2(Vector2(copy,0))
		for uv in [Vector2(0,0),Vector2(1,1),Vector2(1,0),Vector2(0,0),Vector2(0,1),Vector2(1,1)]:
			st.set_uv(uv); st.add_vertex(Vector3((uv.x-0.5)*0.85,0.08,(uv.y-0.5)*1.10))
	return st.commit()

func _build_swarm_surface() -> void:
	swarm_material.set_shader_parameter("ant_color",sim.species.color)
	swarm_material.set_shader_parameter("ant_speed",sim.species.speed*sim.activity*sim.surface.ant_grip)
	swarm_material.set_shader_parameter("visual_length",sim.species.length*magnification)
	density_image = Image.create(Sim.GRID,Sim.GRID,false,Image.FORMAT_RGB8)
	density_image.fill(Color(0,0.5,0.5)); density_texture = ImageTexture.create_from_image(density_image)
	swarm_material.set_shader_parameter("swarm_data",density_texture)
	density_counts.resize(Sim.GRID*Sim.GRID)
	density_flow_x.resize(Sim.GRID*Sim.GRID); density_flow_z.resize(Sim.GRID*Sim.GRID)

func _write_transform(buffer: PackedFloat32Array, at: int, p: Vector3, a: float, scale_value: float, color: Color = Color.WHITE, custom: Color = Color.TRANSPARENT, stride: int = 16) -> void:
	var j = at*stride
	var c = cos(a)*scale_value; var sine = sin(a)*scale_value
	buffer[j] = c; buffer[j+1] = 0.0; buffer[j+2] = sine; buffer[j+3] = p.x
	buffer[j+4] = 0.0; buffer[j+5] = scale_value; buffer[j+6] = 0.0; buffer[j+7] = p.y
	buffer[j+8] = -sine; buffer[j+9] = 0.0; buffer[j+10] = c; buffer[j+11] = p.z
	buffer[j+12] = color.r; buffer[j+13] = color.g; buffer[j+14] = color.b; buffer[j+15] = color.a
	if stride==20:
		buffer[j+16] = custom.r; buffer[j+17] = custom.g; buffer[j+18] = custom.b; buffer[j+19] = custom.a

func _write_attached(at: int, transform: Transform3D, phase: float) -> void:
	var j = at*20; var basis = transform.basis; var point = transform.origin
	attached_buffer[j] = basis.x.x; attached_buffer[j+1] = basis.y.x; attached_buffer[j+2] = basis.z.x; attached_buffer[j+3] = point.x
	attached_buffer[j+4] = basis.x.y; attached_buffer[j+5] = basis.y.y; attached_buffer[j+6] = basis.z.y; attached_buffer[j+7] = point.y
	attached_buffer[j+8] = basis.x.z; attached_buffer[j+9] = basis.y.z; attached_buffer[j+10] = basis.z.z; attached_buffer[j+11] = point.z
	for n in range(4): attached_buffer[j+12+n] = 1.0
	attached_buffer[j+16] = 1.0; attached_buffer[j+17] = 0.0; attached_buffer[j+18] = phase; attached_buffer[j+19] = sim.activity

func _update_density() -> void:
	last_density_tick = sim.tick_index
	density_counts.fill(0.0); density_flow_x.fill(0.0); density_flow_z.fill(0.0)
	density_population = 0
	for i in range(sim.agent_count):
		var remaining = maxi(0,sim.weight[i]-detail_copies)
		if remaining==0: continue
		density_population += remaining
		var gx = clampf((sim.x[i]+sim.radius)/sim.cell_size-0.5,0,Sim.GRID-1)
		var gz = clampf((sim.z[i]+sim.radius)/sim.cell_size-0.5,0,Sim.GRID-1)
		var ix = int(floor(gx)); var iz = int(floor(gz))
		var fx = gx-ix; var fz = gz-iz
		var dx = sin(sim.heading[i]); var dz = cos(sim.heading[i])
		for oz in range(2):
			for ox in range(2):
				var c = mini(iz+oz,Sim.GRID-1)*Sim.GRID+mini(ix+ox,Sim.GRID-1)
				var mass = remaining*(fx if ox else 1.0-fx)*(fz if oz else 1.0-fz)
				density_counts[c] += mass; density_flow_x[c] += mass*dx; density_flow_z[c] += mass*dz
	swarm_material.set_shader_parameter("swarm_enabled",density_population>0)
	if density_population==0: return
	var pixels = PackedByteArray(); pixels.resize(Sim.GRID*Sim.GRID*3)
	var footprint = sim.species.length*sim.species.length*0.65
	for zcell in range(Sim.GRID):
		for xcell in range(Sim.GRID):
			var count = 0.0; var dx = 0.0; var dz = 0.0
			for oz in range(-1,2):
				for ox in range(-1,2):
					var c = clampi(zcell+oz,0,Sim.GRID-1)*Sim.GRID+clampi(xcell+ox,0,Sim.GRID-1)
					var kernel = (2.0 if ox==0 else 1.0)*(2.0 if oz==0 else 1.0)/16.0
					count += density_counts[c]*kernel
					dx += density_flow_x[c]*kernel; dz += density_flow_z[c]*kernel
			var coverage = 1.0-exp(-count*footprint/(sim.cell_size*sim.cell_size))
			var c = (zcell*Sim.GRID+xcell)*3
			pixels[c] = int(clampf(coverage,0,1)*255)
			pixels[c+1] = int((clampf(dx/maxf(count,1),-1,1)*0.5+0.5)*255)
			pixels[c+2] = int((clampf(dz/maxf(count,1),-1,1)*0.5+0.5)*255)
	density_image = Image.create_from_data(Sim.GRID,Sim.GRID,false,Image.FORMAT_RGB8,pixels)
	density_texture.update(density_image)
	swarm_material.set_shader_parameter("swarm_enabled",density_population>0)

func _update_ants(force: bool = true) -> void:
	if sim==null or not is_instance_valid(ant_batch): return
	var scale_value = float(sim.species.length)*magnification
	if force or last_ground_tick!=sim.tick_index or last_ground_camera.distance_squared_to(camera.position)>0.001 or last_ground_scale!=magnification:
		var count = 0; var close_count = 0; detail_ant_count = 0; near_ant_count = 0
		var lod_distance = clampf(scale_value*get_viewport().get_visible_rect().size.y/(2.0*tan(deg_to_rad(camera.fov*0.5))*2.5),0.7,6.0)
		for i in range(sim.agent_count):
			if sim.weight[i]<=0: continue
			var copies = mini(detail_copies,sim.weight[i]); detail_ant_count += copies
			var variation = 0.78+float(i%7)*0.055
			var custom = Color(copies,sim.cell_size*0.44/maxf(scale_value,0.0001),fposmod(i*0.618034,1),sim.activity)
			var point = Vector3(sim.x[i],0.003,sim.z[i])
			if close_count<near_budget and point.distance_squared_to(camera.position)<lod_distance*lod_distance:
				_write_transform(near_buffer,close_count,point,sim.heading[i],scale_value,Color(variation,variation,variation),custom,20)
				close_count += 1; near_ant_count += copies
			else:
				_write_transform(ant_buffer,count,point,sim.heading[i],scale_value,Color(variation,variation,variation),custom,20)
				count += 1
		ant_batch.multimesh.buffer = ant_buffer; ant_batch.multimesh.visible_instance_count = count
		near_ant_batch.multimesh.buffer = near_buffer; near_ant_batch.multimesh.visible_instance_count = close_count
		last_ground_tick = sim.tick_index; last_ground_camera = camera.position; last_ground_scale = magnification
	var attached_count = 0
	for hi in range(sim.humans.size()):
		var h = sim.humans[hi]; var rig = rigs[hi]
		for j in range(mini(24,int(h.attached))):
			var crawl = fposmod(float(j)*0.618034+sim.elapsed*0.016,1.0)
			var joint: Node3D = rig.legs[j%2].lower if j%3==0 else (rig.forearms[j%2] if j%3==1 else rig.torso)
			var local = Vector3((float(j%5)-2)*0.018,-0.06-crawl*0.17,0.055 if j%3<2 else 0.11)
			var basis = joint.global_basis*Basis(Vector3.RIGHT,PI/2)*Basis(Vector3.UP,PI)
			basis = basis.scaled(Vector3.ONE*scale_value*0.55)
			_write_attached(attached_count,Transform3D(basis,joint.to_global(local)),crawl)
			attached_count += 1
	attached_batch.multimesh.buffer = attached_buffer; attached_batch.multimesh.visible_instance_count = attached_count
	if show_scent:
		var n = 0
		for c in range(sim.alarm.size()):
			if sim.alarm[c]<0.5: continue
			var pos = Vector3(-sim.radius+(c%Sim.GRID+0.5)*sim.cell_size,0.025,-sim.radius+(int(c/Sim.GRID)+0.5)*sim.cell_size)
			if not sim._inside(Vector2(pos.x,pos.z),0.03): continue
			var intensity = clampf(sim.alarm[c]/30.0,0.2,1.0)
			_write_transform(scent_buffer,n,pos,0.0,1.0,Color(1.0,1.0,1.0,intensity))
			n += 1
		scent_batch.multimesh.buffer = scent_buffer; scent_batch.multimesh.visible_instance_count = n

func _process(delta: float) -> void:
	if sim==null: return
	if simulation_running or sim.elapsed==0: visual_clock += delta
	motion_time = lerpf(motion_time,sim.elapsed,clampf(delta*18.0,0,1))
	ant_material.set_shader_parameter("simulation_time",motion_time)
	card_material.set_shader_parameter("simulation_time",motion_time)
	swarm_material.set_shader_parameter("simulation_time",motion_time)
	for i in range(rigs.size()): _animate_human(rigs[i],sim.humans[i],delta)
	render_elapsed += delta; density_elapsed += delta
	if render_elapsed>=0.08:
		render_elapsed = 0.0; _update_ants(false)
	if density_elapsed>=0.30:
		density_elapsed = 0.0
		if sim.tick_index!=last_density_tick: _update_density()
	_update_camera()

func _bone_basis(direction: Vector3) -> Basis:
	var y = -direction.normalized()
	var x = Vector3.RIGHT-y*y.dot(Vector3.RIGHT)
	if x.length_squared()<0.01: x = Vector3.FORWARD-y*y.dot(Vector3.FORWARD)
	x = x.normalized()
	return Basis(x,y,x.cross(y).normalized())

func _joint_point(origin: Vector3, target: Vector3, first: float, second: float, bend: Vector3) -> Vector3:
	var line = target-origin
	var d = clampf(line.length(),absf(first-second)+0.01,first+second-0.005)
	var direction = line.normalized()
	var cos_angle = clampf((first*first+d*d-second*second)/(2.0*first*d),-1,1)
	var pole = bend-direction*bend.dot(direction)
	if pole.length_squared()<0.001: pole = Vector3.FORWARD-direction*Vector3.FORWARD.dot(direction)
	return origin+direction*(first*cos_angle)+pole.normalized()*(first*sqrt(maxf(0,1.0-cos_angle*cos_angle)))

func _solve_leg(leg: Dictionary, target: Vector3) -> void:
	var hip: Vector3 = leg.upper.position
	var line = target-hip
	var end = hip+line.normalized()*minf(line.length(),0.735)
	var knee = _joint_point(hip,end,0.34,0.40,Vector3(0,0,1))
	leg.upper.basis = _bone_basis(knee-hip)
	leg.lower.basis = leg.upper.basis.inverse()*_bone_basis(end-knee)
	# Flat world-space sole; the supporting foot does not spin with the pelvis.
	leg.ankle.basis = leg.lower.global_basis.orthonormalized().inverse()*Basis(Vector3.UP,leg.yaw)

func _pose_arm(rig: Dictionary, index: int, target_world: Vector3, weight: float) -> void:
	if weight<=0.001: return
	var arm: Node3D = rig.arms[index]; var forearm: Node3D = rig.forearms[index]
	var origin = arm.position
	var target: Vector3 = rig.body.to_local(target_world)
	var line = target-origin
	target = origin+line.normalized()*minf(line.length(),0.565)
	var side = -1.0 if index==0 else 1.0
	var elbow = _joint_point(origin,target,0.27,0.30,Vector3(side*0.7,-0.12,0.45))
	var upper_basis = _bone_basis(elbow-origin)
	var lower_basis = upper_basis.inverse()*_bone_basis(target-elbow)
	arm.basis = arm.basis.slerp(upper_basis,weight)
	forearm.basis = forearm.basis.slerp(lower_basis,weight)

func _gesture_weight(progress: float) -> float:
	return smoothstep(0.0,0.23,progress)*(1.0-smoothstep(0.74,1.0,progress))

func _animate_human(rig: Dictionary, h: Dictionary, delta: float) -> void:
	var blend = 1.0-exp(-delta*14.0)
	var before: Vector3 = rig.root.position
	var target = Vector3(h.pos.x,0,h.pos.y)
	rig.root.position = before.lerp(target,blend)
	var old_clock: float = rig.clock
	rig.clock = lerpf(rig.clock,sim.elapsed,blend)
	var virtual_delta = maxf(0.0,rig.clock-old_clock)
	var yaw_delta = angle_difference(rig.root.rotation.y,h.facing)
	rig.root.rotation.y += clampf(yaw_delta,-virtual_delta*2.8,virtual_delta*2.8)
	var velocity: Vector2 = h.velocity
	var actual_distance = before.distance_to(rig.root.position)
	var scale_value: float = h.height/1.78
	var pace = clampf(velocity.length()/1.2,0,1)
	var cycle_length = scale_value*(0.64+pace*0.35)
	rig.walk_pose += actual_distance/cycle_length*TAU
	rig.move = lerpf(rig.move,pace if h.active else 0.0,blend)
	rig.withdrawal = move_toward(rig.withdrawal,0.0 if h.active else 1.0,delta*1.15)
	var duration = 1.2 if h.action_kind==2 else 0.55
	var progress = clampf(1.0-h.action/duration,0,1)
	var gesture = _gesture_weight(progress) if h.action>0.0 and h.active else 0.0
	var brushing = gesture if h.action_kind==2 else 0.0
	var stamping = gesture if h.action_kind==1 else 0.0
	if h.action_id!=rig.action_id and h.action_kind==2:
		rig.brush_side = 0 if rig.root.to_local(rig.legs[0].ankle.global_position).z>rig.root.to_local(rig.legs[1].ankle.global_position).z else 1
	var side_index: int = rig.brush_side if h.action_kind==2 else h.action_side
	var side = -1.0 if side_index==0 else 1.0
	var fatigue = 1.0-h.stamina/100.0
	var calf_brush = brushing if h.action_area==0 else 0.0
	var breath = sin(visual_clock*(1.6+fatigue*1.7))*0.0025
	rig.figure.position = Vector3(-side*stamping*0.027,-0.038+breath-rig.withdrawal*0.22-calf_brush*0.30-rig.move*0.02-rig.move*0.006*(1.0-cos(rig.walk_pose*2.0)),0)
	rig.figure.rotation = Vector3.ZERO
	rig.body.rotation = Vector3(fatigue*0.075+calf_brush*0.85+brushing*0.06+rig.withdrawal*0.40,0,0)
	rig.head.rotation = Vector3(0.07+brushing*0.16+rig.withdrawal*0.18,0,0)
	var ground_y = 0.045*scale_value
	if h.action_id!=rig.action_id:
		rig.action_id = h.action_id
		if h.action_kind==1:
			rig.stamp_from = rig.legs[side_index].ankle.global_position
			rig.stamp_from.y = ground_y
			rig.stamp_to = Vector3(h.action_target.x,ground_y,h.action_target.y)
	var forward = Vector3(velocity.x,0,velocity.y).normalized() if velocity.length()>0.04 else rig.root.basis.z
	var step_length = cycle_length*0.31
	var foot_targets: Array = []
	for j in range(2):
		var leg: Dictionary = rig.legs[j]
		var phase = fposmod(rig.walk_pose+j*PI,TAU)/TAU
		var neutral: Vector3 = rig.root.to_global(Vector3(leg.upper.position.x*scale_value,ground_y,0.04*scale_value))
		var world_foot: Vector3 = leg.plant
		if h.action_kind==1 and h.action>0.0 and j==side_index:
			var travel = smoothstep(0.12,0.58,progress)
			world_foot = rig.stamp_from.lerp(rig.stamp_to,travel)
			var lift = smoothstep(0.05,0.28,progress)*(1.0-smoothstep(0.36,0.60,progress))
			world_foot.y = ground_y+lift*0.15*scale_value
			if progress>=0.60: leg.plant = rig.stamp_to; leg.yaw = h.stomp_facing
			leg.swing = lift>0.01; leg.pivot = false; leg.mode = 2
		elif velocity.length()>0.07 and h.action<=0.0 and h.active:
			if leg.mode!=1: leg.swing = false
			var in_swing = phase>=0.62
			if in_swing and not leg.swing:
				leg.from = leg.plant; leg.phase_start = phase
				leg.to = neutral+forward*(step_length+cycle_length*(1.0-phase))
				leg.to.y = ground_y
			if in_swing:
				var next_landing = neutral+forward*(step_length+cycle_length*(1.0-phase))
				leg.to = leg.to.lerp(next_landing,1.0-exp(-virtual_delta*18.0))
				leg.to.y = ground_y
				var t = (phase-leg.phase_start)/maxf(0.01,1.0-leg.phase_start)
				world_foot = leg.from.lerp(leg.to,t*t*(3.0-2.0*t))
				world_foot.y = ground_y+sin(t*PI)*(0.035+pace*0.035)*scale_value
			else:
				if leg.swing: leg.plant = leg.to; leg.yaw = rig.root.rotation.y
				world_foot = leg.plant
			leg.swing = in_swing; leg.pivot = false; leg.mode = 1
		else:
			# Finish a small repositioning step before planting; avoid instant resets.
			var misplaced = Vector2(leg.plant.x-neutral.x,leg.plant.z-neutral.z).length()>0.15*scale_value
			var turned = absf(angle_difference(leg.yaw,rig.root.rotation.y))>0.38
			if not leg.pivot and (misplaced or turned or leg.swing) and not rig.legs[1-j].pivot:
				leg.pivot = true; leg.pivot_time = 0.0
				leg.from = leg.ankle.global_position; leg.from.y = maxf(ground_y,leg.from.y)
				leg.to = neutral
			if leg.pivot:
				leg.pivot_time += maxf(virtual_delta,delta if not h.active else 0.0)
				var t = clampf(leg.pivot_time/0.25,0,1)
				world_foot = leg.from.lerp(leg.to,smoothstep(0,1,t))
				world_foot.y += sin(t*PI)*0.035*scale_value
				leg.swing = true
				if t>=1: leg.pivot = false; leg.swing = false; leg.plant = leg.to; leg.yaw = rig.root.rotation.y
			else: leg.swing = false
			leg.mode = 0
		foot_targets.append(world_foot)
		var arm_swing = sin(rig.walk_pose+j*PI)*rig.move*0.12*(1.0-maxf(brushing,stamping))
		rig.arms[j].rotation = Vector3(-0.05+arm_swing,0,-0.055 if j==0 else 0.055)
		rig.forearms[j].rotation = Vector3(-0.24-fatigue*0.10,0,0)
	# Compute both contact targets before lowering the pelvis, then solve both legs.
	# This also covers the exact frame a swinging foot touches the floor.
	var pelvis_drop = 0.0
	for j in range(2):
		var point: Vector3 = foot_targets[j]
		if point.y>ground_y+0.01: continue
		var hip_world: Vector3 = rig.legs[j].upper.global_position
		var across = Vector2(hip_world.x-point.x,hip_world.z-point.z).length()/scale_value
		var reach_y = sqrt(maxf(0.12,0.735*0.735-across*across))*scale_value
		pelvis_drop = maxf(pelvis_drop,hip_world.y-point.y-reach_y)
	rig.figure.position.y -= minf(pelvis_drop,0.14)
	for j in range(2): _solve_leg(rig.legs[j],rig.figure.to_local(foot_targets[j]))
	if brushing>0:
		var sweep = smoothstep(0.25,0.68,progress)
		var brush_target: Vector3
		if h.action_area==0:
			brush_target = rig.legs[side_index].ankle.global_position+Vector3(0,(0.47-sweep*0.20)*scale_value,0)
			brush_target += rig.root.basis.z*0.10*scale_value
		else:
			brush_target = rig.body.to_global(Vector3(side*0.06,0.31-sweep*0.18,0.145))
		_pose_arm(rig,side_index,brush_target,brushing)
		var brace: Vector3 = rig.legs[1-side_index].upper.global_position+Vector3(0,-0.08*scale_value,0)
		brace += rig.root.basis.z*0.075*scale_value
		_pose_arm(rig,1-side_index,brace,calf_brush)
	if rig.withdrawal>0:
		for j in range(2):
			var rest: Vector3 = rig.legs[j].upper.global_position+Vector3(0,-0.08*scale_value,0)
			rest += rig.root.basis.z*0.085*scale_value
			_pose_arm(rig,j,rest,rig.withdrawal)
	rig.badge.visible = camera_mode!=2 or rig.index!=clampi(selected_human,0,rigs.size()-1)
	rig.badge.position.y = h.height+0.18+rig.figure.position.y
	rig.badge.modulate = Color(0.69,0.35,0.22) if not h.active else Color(0.92,0.82,0.57)

func _update_camera() -> void:
	if camera==null or sim==null: return
	var target = Vector3(0,0.4,0)
	var viewport_size = get_viewport().get_visible_rect().size
	var framing = maxf(1.0,0.95/maxf(0.25,viewport_size.x/viewport_size.y))
	if camera_mode==2 and sim.humans.size()>0:
		var h = sim.humans[clampi(selected_human,0,sim.humans.size()-1)]
		target = rigs[clampi(selected_human,0,rigs.size()-1)].root.position+Vector3(0,0.9,0)
		camera.position = target+Vector3(sin(yaw)*3.2,1.35,cos(yaw)*3.2)
	elif camera_mode==1:
		camera.position = Vector3(0,distance*framing,0.001)
	else:
		camera.position = target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance*framing
	camera.look_at(target,Vector3.UP)

func orbit(dx: float, dy: float) -> void:
	yaw -= dx*0.008; pitch = clampf(pitch+dy*0.007,0.22,1.48)

func zoom(amount: float) -> void:
	distance = clampf(distance+amount,2.2,sim.radius*5.0+12.0)

func set_magnification(value: float) -> void:
	magnification = value
	if swarm_material: swarm_material.set_shader_parameter("visual_length",sim.species.length*magnification)
	_update_ants()

func set_scent(value: bool) -> void:
	show_scent = value
	if is_instance_valid(scent_batch): scent_batch.visible = value
	_update_ants()

func set_snap(value: bool) -> void:
	snap = value
	for mat in materials: mat.set_shader_parameter("vertex_snap",value)

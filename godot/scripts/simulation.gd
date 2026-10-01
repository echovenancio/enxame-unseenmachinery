extends RefCounted
## Fixed-step, seeded simulation. SI units. No visual magnification in collision maths.
## Cohorts above the agent budget conserve integer population, including attached ants.

const STEP = 0.1
const GRID = 64
const MAX_AGENTS = 6000
const MAX_POPULATION = 10000000
const PROFILES = [
	{"name":"Lava-pés", "latin":"Solenopsis invicta", "length":0.004, "speed":0.045, "alarm":1.0, "defence":0.90, "sting":0.25, "pain":0.035, "recovery":0.025, "temp":28.0, "color":Color(0.24,0.075,0.025), "note":"2,4–6 mm · morde e ferroa repetidamente · recrutamento por alarme"},
	{"name":"Tocandira", "latin":"Paraponera clavata", "length":0.025, "speed":0.075, "alarm":0.40, "defence":0.65, "sting":0.035, "pain":4.0, "recovery":0.002, "temp":27.0, "color":Color(0.045,0.045,0.038), "note":"20–30 mm · ferroada muito dolorosa · resposta defensiva local"},
	{"name":"Carpinteira", "latin":"Camponotus floridanus", "length":0.009, "speed":0.065, "alarm":0.65, "defence":0.45, "sting":0.10, "pain":0.045, "recovery":0.05, "temp":26.0, "color":Color(0.17,0.09,0.04), "note":"4–13 mm · sem ferrão · mordida defensiva e ácido fórmico"},
	{"name":"Cabeçuda", "latin":"Pheidole megacephala", "length":0.003, "speed":0.033, "alarm":0.65, "defence":0.25, "sting":0.04, "pain":0.001, "recovery":0.08, "temp":28.0, "color":Color(0.14,0.12,0.075), "note":"2–4 mm · sem ferrão funcional · mordida pouco dolorosa"}
]
const SURFACES = [
	{"name":"Lona de MMA", "grip":0.90, "ant_grip":0.95, "crush":0.94, "color":Color(0.35,0.37,0.28)},
	{"name":"Concreto", "grip":0.95, "ant_grip":0.82, "crush":0.97, "color":Color(0.38,0.37,0.32)},
	{"name":"Areia", "grip":0.60, "ant_grip":0.60, "crush":0.42, "color":Color(0.48,0.39,0.22)},
	{"name":"Terra", "grip":0.78, "ant_grip":0.90, "crush":0.64, "color":Color(0.29,0.25,0.17)},
	{"name":"Madeira", "grip":0.84, "ant_grip":0.90, "crush":0.92, "color":Color(0.35,0.27,0.17)}
]

var config = {}
var species = {}
var surface = {}
var rng = RandomNumberGenerator.new()
var humans: Array = []
var x = PackedFloat32Array()
var z = PackedFloat32Array()
var heading = PackedFloat32Array()
var weight = PackedInt32Array()
var alarm = PackedFloat32Array()
var density = PackedFloat32Array()
var first = PackedInt32Array()
var next = PackedInt32Array()
var human_near = PackedInt32Array()
var near_dist = PackedFloat32Array()
var population = 0
var alive = 0
var crushed = 0
var escaped = 0
var contacts = 0
var exposures = 0
var stomps = 0
var elapsed = 0.0
var result = ""
var finished = false
var radius = 4.0
var cell_size = 0.125
var agent_count = 0
var cohort_size = 1
var activity = 1.0
var events: Array = []
var history: Array = []
var last_history = -1
var tick_index = 0
var nearest_nest = Vector2.ZERO

func configure(options: Dictionary) -> void:
	config = options.duplicate(true)
	species = PROFILES[clampi(int(config.get("species",0)),0,PROFILES.size()-1)]
	surface = SURFACES[clampi(int(config.get("surface",0)),0,SURFACES.size()-1)]
	rng.seed = int(config.get("seed",1977))
	radius = clampf(float(config.get("size",8.0))*0.5,2.0,15.0)
	cell_size = radius*2.0/GRID
	population = clampi(int(config.get("ants",12000)),0,MAX_POPULATION)
	alive = population
	crushed = 0; escaped = 0; contacts = 0; exposures = 0; stomps = 0
	elapsed = 0.0; finished = false; result = ""; tick_index = 0
	events.clear(); history.clear(); last_history = -1
	nearest_nest = Vector2(-radius*0.5,0.0)
	agent_count = mini(population,MAX_AGENTS)
	cohort_size = maxi(1,ceili(float(population)/MAX_AGENTS))
	x.resize(agent_count); z.resize(agent_count); heading.resize(agent_count)
	weight.resize(agent_count); next.resize(agent_count)
	alarm.resize(GRID*GRID); alarm.fill(0.0)
	density.resize(GRID*GRID); first.resize(GRID*GRID)
	human_near.resize(GRID*GRID); near_dist.resize(GRID*GRID)
	var quotient = population/maxi(1,agent_count)
	var remainder = population%maxi(1,agent_count)
	for i in range(agent_count):
		var p = _random_point()
		if int(config.get("scenario",0)) == 0 and rng.randf()<0.65:
			p = nearest_nest+Vector2(rng.randfn(0.0,radius*0.26),rng.randfn(0.0,radius*0.28))
			p = _contain(p)
		x[i] = p.x; z[i] = p.y
		heading[i] = rng.randf()*TAU
		weight[i] = int(quotient)+(1 if i<remainder else 0)
	humans.clear()
	var profiles = config.get("human_profiles",[])
	var count = clampi(int(config.get("humans",2)),0,32)
	for i in range(count):
		var profile = profiles[i] if i<profiles.size() else {}
		var p = Vector2(radius*0.33, (float(i)-float(count-1)*0.5)*0.70)
		if count>8:
			p = Vector2(radius*0.25+float(i%4)*0.65,(float(i/4)-float(ceili(count/4.0)-1)*0.5)*0.65)
		p = _contain(p,0.35)
		humans.append({"pos":p, "previous":p, "velocity":Vector2.ZERO, "facing":-PI/2,
			"mass":float(profile.get("mass",78.0)), "height":float(profile.get("height",1.78)),
			"fitness":float(profile.get("fitness",0.6)), "courage":float(profile.get("courage",0.6)),
			"shoes":bool(profile.get("shoes",false)), "pain":0.0, "stamina":100.0,
			"attached":0, "exposure":0, "exposure_fraction":0.0, "active":true,
			"state":"Observando", "action":0.0, "action_kind":0, "action_id":0,
			"action_target":p, "action_side":i%2, "action_area":0, "stomp_facing":-PI/2, "cooldown":rng.randf_range(0.3,2.0),
			"intent":Vector2.ZERO,"decision_time":0.0,"decision_mode":-1,
			"panic_time":0.0, "walk":rng.randf()*TAU, "slip":0.0})
	activity = _activity()
	_rebuild_grid()
	_event("Arena preparada. Unidades físicas em metros.")
	if cohort_size>1:
		_event("População agrupada: até %d formigas por agente."%cohort_size)
	_record_history()
	if population == 0:
		_finish("Sem formigas — humanos sem oposição" if count>0 else "Arena vazia")
	elif count == 0:
		_finish("Sem humanos — colônia sem oposição")

func tick(dt: float = STEP) -> void:
	if finished: return
	dt = STEP # Public contract: same fixed timestep independent of rendering/speed.
	tick_index += 1
	elapsed += dt
	_decay_pheromone(dt)
	_rebuild_grid()
	_update_humans(dt)
	_build_human_field()
	_update_ants(dt)
	if tick_index%10 == 0: _record_history()
	var active = 0
	for h in humans:
		if h.active: active += 1
	if active == 0: _finish("Humanos retirados por dor ou exaustão")
	elif alive == 0: _finish("Humanos controlaram a arena")
	elif elapsed>=float(config.get("duration",600.0)):
		_finish("Tempo encerrado — coexistência na arena")

func _activity() -> float:
	var temp = float(config.get("temperature",28.0))
	var thermal = exp(-pow((temp-float(species.temp))/15.0,2.0))
	var humidity = lerpf(0.55,1.0,clampf(float(config.get("humidity",65.0))/60.0,0.0,1.0))
	return clampf(thermal*humidity,0.01,1.0)

func _decay_pheromone(dt: float) -> void:
	var wind = float(config.get("wind",0.0))
	var rain = float(config.get("rain",0.0))
	var thermal = maxf(0.0,float(config.get("temperature",28.0))-28.0)
	var decay = exp(-dt*(0.045+wind*0.014+rain*0.006+thermal*0.006))
	# Alarm is a substrate/local field. Wind accelerates its dispersal, not a homing signal.
	for c in range(alarm.size()): alarm[c] *= decay

func _rebuild_grid() -> void:
	density.fill(0.0); first.fill(-1)
	for i in range(agent_count):
		if weight[i]<=0: continue
		var c = _cell(x[i],z[i])
		density[c] += weight[i]
		next[i] = first[c]; first[c] = i

func _build_human_field() -> void:
	human_near.fill(-1); near_dist.fill(100000.0)
	var reach = ceili(1.15/cell_size)
	for hi in range(humans.size()):
		var h = humans[hi]
		if not h.active: continue
		var p: Vector2 = h.pos
		var cx = clampi(int((p.x+radius)/cell_size),0,GRID-1)
		var cz = clampi(int((p.y+radius)/cell_size),0,GRID-1)
		for gz in range(maxi(0,cz-reach),mini(GRID,cz+reach+1)):
			for gx in range(maxi(0,cx-reach),mini(GRID,cx+reach+1)):
				var c = gz*GRID+gx
				var d = Vector2(-radius+(gx+0.5)*cell_size,-radius+(gz+0.5)*cell_size).distance_squared_to(p)
				if d<near_dist[c]: near_dist[c] = d; human_near[c] = hi

func _update_humans(dt: float) -> void:
	var rain = float(config.get("rain",0.0))
	var grip = float(surface.grip)*lerpf(1.0,0.58,clampf(rain/25.0,0.0,1.0))
	var heat = maxf(0.0,float(config.get("temperature",28.0))-26.0)*0.022
	for hi in range(humans.size()):
		var h = humans[hi]
		h.previous = h.pos
		h.action = maxf(0.0,h.action-dt)
		h.cooldown -= dt
		h.slip = maxf(0.0,h.slip-dt)
		if not h.active:
			h.velocity = Vector2.ZERO
			continue
		if h.attached>0:
			var skin = 0.40 if h.shoes else 1.0
			var rate = float(species.sting)*activity*skin
			h.exposure_fraction += h.attached*rate*dt
			var hits = int(h.exposure_fraction)
			h.exposure_fraction -= hits
			h.exposure += hits; exposures += hits
			h.pain = minf(120.0,h.pain+hits*float(species.pain)*sqrt(78.0/h.mass))
		h.pain = maxf(0.0,h.pain-float(species.recovery)*dt)
		var local = _local_density(h.pos,0.55)
		var fear = clampf(h.pain/80.0+float(h.attached)/maxf(30.0,400.0*pow(0.004/species.length,1.25)),0.0,2.0)
		var behaviour = int(config.get("behaviour",0))
		var preferred: Vector2 = h.velocity.normalized() if h.velocity.length()>0.08 else Vector2(sin(h.facing),cos(h.facing))
		var away = _safest_direction(h.pos,preferred)
		var target = Vector2.ZERO
		if behaviour == 3:
			h.state = "Imóvel"
		elif fear>0.50 or behaviour == 1:
			target = away
			h.state = "Evitando contato"
		elif local>0.0:
			target = away*0.30
			h.state = "Defendendo-se"
		else:
			var search = Vector2(sin(elapsed*0.12+hi*2.1),cos(elapsed*0.13+hi*1.7))
			target = search*0.30
			if behaviour == 2: target = (nearest_nest-h.pos).normalized()*0.65
			h.state = "Procurando espaço"
		var decision_mode = 3 if behaviour==3 else (1 if fear>0.50 or behaviour==1 else (2 if local>0.0 else 0))
		h.decision_time -= dt
		if not _inside(h.pos+h.intent*0.55,0.30): h.decision_time = 0.0
		if h.decision_time<=0.0 or (decision_mode==1 and h.decision_mode!=1):
			h.intent = target; h.decision_mode = decision_mode
			h.decision_time = 0.9+(1.0-h.fitness)*0.40
		else: target = h.intent
		if h.cooldown<=0.0:
			if h.attached>0:
				_brush(hi)
			elif local>0.0 and behaviour!=1 and behaviour!=3:
				_stomp(hi,grip)
			else:
				h.cooldown = 0.5
		if h.action>0.0:
			h.state = "Removendo formigas" if h.action_kind==2 else "Pisando"
		var speed = (0.7+h.fitness*0.75)*grip*clampf(h.stamina/75.0,0.18,1.0)
		if h.pain>40.0: speed *= lerpf(1.0,0.30,clampf((h.pain-40.0)/60.0,0.0,1.0))
		if h.action>0.0 or h.slip>0.0: speed *= 0.20
		var separation = Vector2.ZERO
		for hj in range(humans.size()):
			if hi==hj: continue
			var delta: Vector2 = h.pos-humans[hj].pos
			var dist = delta.length()
			if dist<0.55 and dist>0.0001: separation += delta/dist*(0.55-dist)*2.0
		var desired: Vector2 = target*speed+separation
		if behaviour == 3: desired = separation
		# Momentum prevents instant reversals and repeated pivots on the density grid.
		var velocity: Vector2 = h.velocity.move_toward(desired,dt*(1.8+h.fitness*1.2))
		h.pos = _contain(h.pos+velocity*dt,0.25)
		h.velocity = (h.pos-h.previous)/dt
		if velocity.length_squared()>0.003 and h.action<=0.0:
			h.facing = atan2(velocity.x,velocity.y)
		h.walk += h.velocity.length()*dt
		var effort = velocity.length()*0.28*(h.mass/78.0)*(1.25-h.fitness*0.65)+heat+fear*0.06
		var recover = 0.25+h.fitness*0.22 if velocity.length()<0.15 and h.action<=0.0 else 0.04
		h.stamina = clampf(h.stamina+(recover-effort)*dt,0.0,100.0)
		if h.pain>=100.0 or h.stamina<3.0: h.panic_time += dt
		else: h.panic_time = maxf(0.0,h.panic_time-dt)
		var tolerance = 2.0+h.courage*7.0
		if h.panic_time>=tolerance:
			h.active = false; h.state = "Retirou-se"
			_event("Humano %02d retirou-se: dor %.0f / energia %.0f."%[hi+1,h.pain,h.stamina])

func _update_ants(dt: float) -> void:
	var ant_speed = float(species.speed)*activity*float(surface.ant_grip)
	var scenario = int(config.get("scenario",0))
	var width = float(species.length)
	var temp = float(config.get("temperature",28.0))
	for i in range(agent_count):
		if weight[i]<=0: continue
		var p = Vector2(x[i],z[i])
		var cell = _cell(p.x,p.y)
		var hi = human_near[cell]
		var move_angle = heading[i]
		var forward = Vector2(sin(move_angle),cos(move_angle))
		var left = p+forward.rotated(-0.55)*0.15
		var right = p+forward.rotated(0.55)*0.15
		var l = alarm[_cell(left.x,left.y)]
		var r = alarm[_cell(right.x,right.y)]
		var here = alarm[cell]
		# Local gradient following plus persistent random walk; no global target.
		move_angle += clampf((l-r)*0.015,-0.22,0.22)*float(species.alarm)
		move_angle += rng.randf_range(-0.20,0.20)*sqrt(dt/STEP)
		if scenario==0 and p.distance_squared_to(nearest_nest)<pow(radius*0.32,2.0):
			here = maxf(here,1.5)
		if hi>=0:
			var h = humans[hi]
			var d: Vector2 = h.pos-p
			var dist = d.length()
			var defended = here>0.35 and scenario!=1
			if dist<0.55:
				# A nearby moving foot provokes alarm. Attraction only in a defensive context.
				if h.velocity.length()>0.18 or scenario==2:
					alarm[cell] = minf(80.0,alarm[cell]+dt*4.0*float(species.alarm))
				if defended or scenario==2:
					var angle = atan2(d.x,d.y)
					move_angle = lerp_angle(move_angle,angle,0.18*float(species.defence))
				elif h.action>0.0:
					move_angle = lerp_angle(move_angle,atan2(-d.x,-d.y),0.35)
			if dist<0.22+width:
				var probability = (1.0-exp(-dt*(0.5+float(species.defence)*1.4)))*activity
				if h.velocity.length()>0.8: probability *= 0.35
				if h.shoes: probability *= 0.28
				var cap = maxi(6,int(900.0*pow(0.004/width,1.5)*pow(h.height/1.78,2.0)))
				var take = mini(_stochastic_count(weight[i],probability),maxi(0,cap-h.attached))
				if take>0:
					h.attached += take; contacts += take; weight[i] -= take
					alarm[cell] = minf(80.0,alarm[cell]+5.0*float(species.alarm))
					if contacts == take: _event("Primeiro contato. A colônia reage localmente.")
		var moved = p+Vector2(sin(move_angle),cos(move_angle))*ant_speed*dt
		if not _inside(moved,0.015):
			if bool(config.get("escape",false)):
				escaped += weight[i]; alive -= weight[i]; weight[i] = 0
				continue
			else:
				moved = _contain(moved,0.018)
				move_angle += PI*rng.randf_range(0.65,1.35)
		x[i] = moved.x; z[i] = moved.y; heading[i] = fposmod(move_angle,TAU)
		# Extreme temperature losses are explicitly heuristic, not species lethality data.
		if (temp<3.0 or temp>46.0) and tick_index%10==0:
			var lost = _stochastic_count(weight[i],0.004)
			weight[i] -= lost; crushed += lost; alive -= lost

func _stomp(hi: int, grip: float) -> void:
	var h = humans[hi]
	var best = h.pos
	var most = -1.0
	for j in range(12):
		# A step targets reachable ground ahead instead of spinning toward every peak.
		var a = h.facing+lerpf(-1.1,1.1,float(j)/11.0)
		var p = h.pos+Vector2(sin(a),cos(a))*0.24
		var d = _local_density(p,0.13)
		if d>most: most = d; best = p
	var dir: Vector2 = (best-h.pos).normalized()
	if dir.length_squared()<0.01: dir = Vector2(sin(h.facing),cos(h.facing))
	var side = dir.orthogonal()
	var half_length = h.height*0.078
	var half_width = 0.042+h.mass*0.00015
	var reach = ceili((half_length+half_width)/cell_size)+1
	var cx = clampi(int((best.x+radius)/cell_size),0,GRID-1)
	var cz = clampi(int((best.y+radius)/cell_size),0,GRID-1)
	var killed = 0
	var pressure = clampf(h.mass/60.0,0.5,1.1)
	var chance = clampf(float(surface.crush)*pressure*grip,0.1,0.99)
	for gz in range(maxi(0,cz-reach),mini(GRID,cz+reach+1)):
		for gx in range(maxi(0,cx-reach),mini(GRID,cx+reach+1)):
			var i = first[gz*GRID+gx]
			while i>=0:
				var q = Vector2(x[i],z[i])-best
				if weight[i]>0 and absf(q.dot(dir))<half_length+species.length*0.5 and absf(q.dot(side))<half_width+species.length*0.25:
					var dead = _stochastic_count(weight[i],chance)
					weight[i] -= dead; killed += dead
				i = next[i]
	alive -= killed; crushed += killed; stomps += 1
	var cell = _cell(best.x,best.y)
	alarm[cell] = minf(80.0,alarm[cell]+4.0*float(species.alarm))
	h.action = 0.55; h.action_kind = 1
	h.action_id += 1
	var lateral = dir.dot(Vector2(cos(h.facing),-sin(h.facing)))
	h.action_side = h.action_id%2 if absf(lateral)<0.15 else (0 if lateral<0 else 1)
	h.action_target = best
	h.stomp_facing = atan2(dir.x,dir.y)
	h.cooldown = (0.75+(1.0-h.fitness)*0.70)*(1.0+h.pain/120.0)
	h.stamina = maxf(0.0,h.stamina-(0.28+h.mass*0.004)*(1.25-h.fitness*0.45))
	h.state = "Pisando"
	if grip<0.65 and rng.randf()<0.05*(1.0-h.fitness):
		h.slip = 1.8; h.stamina = maxf(0.0,h.stamina-2.0); h.state = "Recuperando equilíbrio"

func _brush(hi: int) -> void:
	var h = humans[hi]
	var removed = _stochastic_count(h.attached,0.55+h.fitness*0.25)
	var dead = _stochastic_count(removed,0.35)
	h.attached -= removed
	alive -= dead; crushed += dead
	_return_ground(removed-dead,h.pos+Vector2(rng.randf_range(-0.3,0.3),rng.randf_range(-0.3,0.3)))
	h.action = 1.2; h.action_kind = 2; h.state = "Removendo formigas"
	h.action_id += 1; h.action_side = h.action_id%2
	h.action_area = 1 if (h.action_id+hi)%4==0 else 0
	h.cooldown = 2.0+(1.0-h.fitness)*0.8
	h.stamina = maxf(0.0,h.stamina-0.45)

func _return_ground(count: int, p: Vector2) -> void:
	if count<=0 or agent_count<=0: return
	p = _contain(p)
	var nearest = -1
	var best = INF
	for i in range(agent_count):
		if weight[i]==0:
			var restored = mini(count,cohort_size)
			var spread = _contain(p+Vector2(rng.randf_range(-0.06,0.06),rng.randf_range(-0.06,0.06)))
			x[i] = spread.x; z[i] = spread.y; weight[i] = restored
			heading[i] = rng.randf()*TAU
			count -= restored
			if count<=0: return
			continue
		var d = Vector2(x[i],z[i]).distance_squared_to(p)
		if d<best: best = d; nearest = i
	# Merge locally if all cohort slots are occupied. Population is still exact.
	if nearest>=0:
		var total = weight[nearest]+count
		x[nearest] = (x[nearest]*weight[nearest]+p.x*count)/total
		z[nearest] = (z[nearest]*weight[nearest]+p.y*count)/total
		weight[nearest] = total

func _stochastic_count(n: int, chance: float) -> int:
	if n<=0: return 0
	chance = clampf(chance,0.0,1.0)
	if n==1: return 1 if rng.randf()<chance else 0
	if n<=8:
		var amount = 0
		for j in range(n):
			if rng.randf()<chance: amount += 1
		return amount
	# Moment-matched bounded binomial approximation for large cohorts.
	return clampi(roundi(rng.randfn(n*chance,sqrt(n*chance*(1.0-chance)))),0,n)

func _local_density(p: Vector2, reach: float) -> float:
	var cx = clampi(int((p.x+radius)/cell_size),0,GRID-1)
	var cz = clampi(int((p.y+radius)/cell_size),0,GRID-1)
	var cells = maxi(1,ceili(reach/cell_size))
	var sum = 0.0
	for gz in range(maxi(0,cz-cells),mini(GRID,cz+cells+1)):
		for gx in range(maxi(0,cx-cells),mini(GRID,cx+cells+1)):
			sum += density[gz*GRID+gx]
	return sum

func _safest_direction(p: Vector2, preferred: Vector2 = Vector2.ZERO) -> Vector2:
	var best = INF
	var direction = Vector2.ZERO
	var turn_cost = maxf(1.0,_local_density(p,0.20)*0.18)
	for j in range(8):
		var d = Vector2(sin(j*TAU/8.0),cos(j*TAU/8.0))
		var sample = p+d*0.70
		if not _inside(sample,0.3): continue
		var score = _local_density(sample,0.20)+(1.0-d.dot(preferred))*turn_cost
		if score<best: best = score; direction = d
	return direction

func _cell(px: float, pz: float) -> int:
	return clampi(int((pz+radius)/cell_size),0,GRID-1)*GRID+clampi(int((px+radius)/cell_size),0,GRID-1)

func _inside(p: Vector2, margin: float = 0.0) -> bool:
	var r = radius-margin
	return absf(p.x)<=r and absf(p.y)<=r and absf(p.x)+absf(p.y)<=r*sqrt(2.0)

func _contain(p: Vector2, margin: float = 0.03) -> Vector2:
	var r = maxf(0.1,radius-margin)
	p.x = clampf(p.x,-r,r); p.y = clampf(p.y,-r,r)
	var diagonal = r*sqrt(2.0)
	if absf(p.x)+absf(p.y)>diagonal: p *= diagonal/(absf(p.x)+absf(p.y))
	return p

func _random_point() -> Vector2:
	for attempt in range(100):
		var p = Vector2(rng.randf_range(-radius,radius),rng.randf_range(-radius,radius))
		if _inside(p,0.05): return p
	return Vector2.ZERO

func _event(message: String) -> void:
	events.append({"time":elapsed,"message":message})
	if events.size()>32: events.pop_front()

func _finish(message: String) -> void:
	finished = true; result = message
	_event(message)
	_record_history()

func _record_history() -> void:
	var sec = int(elapsed)
	if sec==last_history: return
	last_history = sec
	var stats = summary()
	history.append({"time":elapsed,"alive":alive,"active":stats.active,"pain":stats.pain,"stamina":stats.stamina,"contacts":contacts,"exposures":exposures})

func summary() -> Dictionary:
	var active = 0
	var pain = 0.0
	var stamina = 0.0
	var attached = 0
	var live_agents = 0
	var max_weight = 1
	for h in humans:
		if h.active: active += 1
		pain += h.pain; stamina += h.stamina; attached += h.attached
	for w in weight:
		if w>0: live_agents += 1
		max_weight = maxi(max_weight,w)
	return {"alive":alive,"crushed":crushed,"escaped":escaped,"active":active,
		"pain":pain/maxi(1,humans.size()),"stamina":stamina/maxi(1,humans.size()),
		"attached":attached,"contacts":contacts,"exposures":exposures,"stomps":stomps,
		"agents":live_agents,"cohort":max_weight,"elapsed":elapsed,"result":result,"activity":activity}

func conserved_population() -> int:
	var total = crushed+escaped
	for w in weight: total += w
	for h in humans: total += h.attached
	return total

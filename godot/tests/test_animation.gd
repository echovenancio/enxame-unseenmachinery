extends SceneTree
var failures = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("ANIMATION_FAILURE "+message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440,900)
	var scene = load("res://main.tscn").instantiate(); root.add_child(scene)
	await process_frame
	scene.suppress_signals = true
	scene.fields.ants.value = 3000; scene.fields.humans.value = 3
	scene.fields.scenario.selected = 2; scene.fields.behaviour.selected = 2
	scene.suppress_signals = false; scene.prepare_round()
	# Check the articulation at both ends of the configurable body proportions.
	scene.sim.humans[0].height = 1.30; scene.sim.humans[0].mass = 40.0
	scene.sim.humans[2].height = 2.20; scene.sim.humans[2].mass = 180.0
	scene.arena.set_simulation(scene.sim)
	var min_sole = INF; var max_stance = -INF
	for frame in range(180):
		scene.sim.tick()
		for i in range(scene.arena.rigs.size()):
			var rig = scene.arena.rigs[i]; var h = scene.sim.humans[i]
			scene.arena._animate_human(rig,h,0.1)
			for leg in rig.legs:
				var sole = leg.ankle.global_position.y-h.height/1.78*0.045
				check(is_finite(sole),"Finite sole position")
				min_sole = minf(min_sole,sole)
				check(sole>=-0.045,"Foot stays above the floor")
				if h.active and h.action<=0.0 and not leg.swing:
					max_stance = maxf(max_stance,sole)
					if sole>0.08:
						print("STANCE_FAILURE frame=",frame," sole=",sole," human=",i," velocity=",h.velocity," action=",h.action," phase=",rig.walk_pose," plant=",leg.plant," ankle=",leg.ankle.global_position," hip=",leg.upper.global_position," root=",rig.root.position," figure=",rig.figure.position," mode=",leg.mode)
						quit(1); return
	# Explicit gestures keep coverage independent of stochastic ant contacts.
	for h in scene.sim.humans:
		h.active = true; h.velocity = Vector2.ZERO; h.stamina = 100.0; h.action = 0.0
	scene.sim.humans[0].pos = Vector2.ZERO
	scene.sim.humans[1].pos = Vector2(scene.sim.radius*0.85,0)
	scene.sim.humans[2].pos = Vector2(-scene.sim.radius*0.55,-scene.sim.radius*0.55)
	scene.arena.set_simulation(scene.sim)
	for rig in scene.arena.rigs:
		var h = scene.sim.humans[rig.index]
		for frame in range(30): scene.arena._animate_human(rig,h,1.0/60.0)
		for kind in [1,2]:
			for side in range(2):
				h.action_kind = kind; h.action_side = side; h.action_area = 0; h.action_id += 1
				h.action_target = h.pos+Vector2(sin(h.facing),cos(h.facing))*0.24
				var duration = 0.55 if kind==1 else 1.2
				var peak_lift = 0.0
				for frame in range(73):
					h.action = maxf(0.0,duration-frame/60.0)
					scene.sim.elapsed += 1.0/60.0
					scene.arena._animate_human(rig,h,1.0/60.0)
					check(rig.figure.position.y/h.height*1.78>-0.16,"Defense keeps the hips upright")
					check(rig.body.rotation.x<0.35,"Defense uses a gentle torso bend")
					for leg in rig.legs:
						check(leg.ankle.global_position.y>=0.0,"Gesture foot stays above ground")
						peak_lift = maxf(peak_lift,leg.ankle.global_position.y-h.height/1.78*0.045)
				check(peak_lift>0.12*h.height/1.78,"Gesture visibly lifts a foot")
				check(not rig.wings[0].visible and not rig.wings[1].visible,"Wings stay hidden during defense")
	# Departures must finish even with the simulation clock stopped at round end.
	var elapsed: float = scene.sim.elapsed
	var population: int = scene.sim.conserved_population()
	for i in range(scene.arena.rigs.size()):
		var rig = scene.arena.rigs[i]; var h = scene.sim.humans[i]
		h.active = false; h.action = 0; h.attached += 4
		var model_position: Vector2 = h.pos
		var departure: Vector3 = rig.root.position
		var left_arena = false
		for frame in range(330):
			scene.arena._animate_human(rig,h,1.0/60.0)
			check(h.pos==model_position,"Visual flight preserves the simulation position")
			if frame==18:
				check(rig.wings[0].visible and rig.wings[1].visible,"A pair of wings grows during withdrawal")
				check(rig.wings[0].scale.x>0.1 and rig.wings[0].scale.x<1.0,"Wings grow progressively")
				check(rig.root.position.distance_to(departure)<0.01,"Wings grow before takeoff")
				var frozen_pose: Transform3D = rig.root.transform
				var frozen_wing: Transform3D = rig.wings[0].transform
				scene.arena._animate_human(rig,h,0.0)
				check(rig.root.transform==frozen_pose and rig.wings[0].transform==frozen_wing,"Zero animation delta freezes departure")
				if i==0:
					var frozen_time: float = rig.flight_time
					scene.sim.finished = false; scene.arena.simulation_running = false
					scene.arena._process(1.0/60.0)
					check(rig.flight_time==frozen_time,"Pause freezes departure")
					scene.sim.finished = true
					scene.arena._process(1.0/60.0)
					check(rig.flight_time>frozen_time,"Round end lets departure continue")
			if rig.flight_time>1.7 and rig.root.visible:
				check(rig.withdrawal>=0.99,"Wings fully unfold before flight")
				for leg in rig.legs:
					check(leg.ankle.global_position.y>2.3,"Flying feet clear the cage")
				check(absf(rig.shadow.global_position.y-0.004)<0.001,"Shadow stays on the floor")
			if not scene.sim._inside(Vector2(rig.root.position.x,rig.root.position.z)): left_arena = true
		check(left_arena,"Withdrawal travels beyond the octagon")
		check(not rig.root.visible and not rig.shadow.visible,"Departed human and shadow disappear")
	check(scene.sim.elapsed==elapsed,"Departure finishes without advancing simulation time")
	# Attached insects must disappear with their departed host, despite using a separate MultiMesh.
	scene.arena._update_ants()
	check(scene.arena.attached_batch.multimesh.visible_instance_count==0,"Departed humans leave no floating attached ants")
	for h in scene.sim.humans: h.attached -= 4
	check(scene.sim.conserved_population()==population,"Visual flight preserves the ant population")
	# A new round brings back grounded humans with no leftover wings or flight state.
	scene.prepare_round()
	for rig in scene.arena.rigs:
		check(rig.root.visible and rig.flight_time<0.0,"New round resets departure")
		check(not rig.wings[0].visible and not rig.wings[1].visible,"New round hides the wings")
	print("ANIMATION_TEST_RESULT failures=",failures," min_sole=",min_sole," max_stance=",max_stance)
	quit(1 if failures else 0)

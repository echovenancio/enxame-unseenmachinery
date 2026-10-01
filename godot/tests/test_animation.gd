extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440,900)
	var scene = load("res://main.tscn").instantiate(); root.add_child(scene)
	await process_frame
	scene.suppress_signals = true
	scene.fields.ants.value = 3000; scene.fields.scenario.selected = 2; scene.fields.behaviour.selected = 2
	scene.suppress_signals = false; scene.prepare_round()
	var min_sole = INF; var max_stance = -INF
	for frame in range(180):
		scene.sim.tick()
		for i in range(scene.arena.rigs.size()):
			var rig = scene.arena.rigs[i]; var h = scene.sim.humans[i]
			scene.arena._animate_human(rig,h,0.1)
			for leg in rig.legs:
				var sole = leg.ankle.global_position.y-h.height/1.78*0.045
				assert(is_finite(sole))
				min_sole = minf(min_sole,sole)
				assert(sole>=-0.045)
				if h.active and h.action<=0.0 and not leg.swing:
					max_stance = maxf(max_stance,sole)
					if sole>0.08:
						print("STANCE_FAILURE frame=",frame," sole=",sole," human=",i," velocity=",h.velocity," action=",h.action," phase=",rig.walk_pose," plant=",leg.plant," ankle=",leg.ankle.global_position," hip=",leg.upper.global_position," root=",rig.root.position," figure=",rig.figure.position," mode=",leg.mode)
						quit(1); return
	for i in range(scene.arena.rigs.size()):
		var rig = scene.arena.rigs[i]; var h = scene.sim.humans[i]
		h.active = false; h.action = 0
		for frame in range(60): scene.arena._animate_human(rig,h,0.0167)
		assert(rig.withdrawal>=0.99)
		assert(absf(rig.figure.rotation.z)<0.01)
		for leg in rig.legs:
			var sole = leg.ankle.global_position.y-h.height/1.78*0.045
			assert(absf(sole)<0.04)
	print("ANIMATION_TEST_PASS min_sole=",min_sole," max_stance=",max_stance)
	quit()

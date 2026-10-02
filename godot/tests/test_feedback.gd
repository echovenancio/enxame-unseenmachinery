extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1; printerr("FEEDBACK_FAILURE "+message)

func run() -> void:
	var scene = load("res://main.tscn").instantiate(); root.add_child(scene)
	await process_frame
	scene.set_process(false); scene.arena.set_process(false); scene.human_hud.set_process(false)
	scene.sim.configure({"ants":80,"humans":1,"scenario":2,"behaviour":2})
	scene.arena.set_simulation(scene.sim); scene.human_hud.reset()
	var h: Dictionary = scene.sim.humans[0]
	var point: Vector2 = h.pos+Vector2(sin(h.facing-1.1),cos(h.facing-1.1))*0.24
	for i in range(scene.sim.agent_count):
		scene.sim.x[i] = point.x; scene.sim.z[i] = point.y
	scene.sim._rebuild_grid(); scene.sim._stomp(0,0.9)
	check(scene.sim.crushed>0,"Fixture produces real stomp deaths")
	var recorded = 0
	for event in scene.sim.death_events:
		recorded += event.count
		check(event.pos.distance_to(point)<0.0001,"Ground death records the killed ant's position")
	check(recorded==scene.sim.crushed,"Death notifications match actual losses")
	check(scene.sim.conserved_population()==80,"Recording effects preserves population")
	scene.arena._update_death_effects(0.0)
	check(scene.arena.death_batch.multimesh.visible_instance_count==0,"Stomp effects wait for the foot to land")
	h.action = 0.1; scene.arena._update_death_effects(0.05)
	check(scene.arena.death_batch.multimesh.visible_instance_count>0,"Landing emits death particles")
	if scene.arena.death_bursts.is_empty(): quit(1); return
	var particles: MultiMesh = scene.arena.death_batch.multimesh
	for i in range(particles.visible_instance_count):
		# Inspect the submitted transforms; the headless rendering backend has no GPU readback.
		var pos = Vector3(scene.arena.death_buffer[i*16+3],scene.arena.death_buffer[i*16+7],scene.arena.death_buffer[i*16+11])
		check(Vector2(pos.x,pos.z).distance_to(point)<0.2,"Particles originate at the death location")
	var age: float = scene.arena.death_bursts[0].age
	scene.arena._update_death_effects(0.0)
	check(scene.arena.death_bursts[0].age==age,"Pause freezes effect lifetime")
	scene.arena._update_death_effects(0.7)
	check(scene.arena.death_batch.multimesh.visible_instance_count==0,"Death particles expire")
	scene.arena._update_death_effects(0.0)
	check(scene.arena.death_batch.multimesh.visible_instance_count==0,"Consumed deaths do not replay")
	# Brush deaths come from attached ants, rather than the ground density.
	scene.sim.configure({"ants":80,"humans":1}); h = scene.sim.humans[0]
	for i in range(40): scene.sim.weight[i] = 0
	h.attached = 40
	scene.arena.set_simulation(scene.sim); scene.sim._brush(0)
	scene.arena._update_death_effects(0.05)
	check(scene.sim.crushed>0 and scene.arena.death_bursts.size()>0,"Brush deaths emit feedback")
	for burst in scene.arena.death_bursts: check(burst.position.y>0.2,"Attached-ant effects originate on the body")
	check(scene.sim.conserved_population()==80,"Brush feedback preserves population")
	# A large thermal loss is sampled for visuals, while counts retain every death.
	var heat = Simulation.new()
	heat.configure({"ants":10000000,"humans":1,"temperature":60.0,"behaviour":3})
	heat.tick_index = 10; heat._update_ants(Simulation.STEP)
	check(heat.death_serial>Simulation.MAX_DEATH_EVENTS,"Stress fixture exceeds the effect event budget")
	check(heat.death_events.size()<=Simulation.MAX_DEATH_EVENTS,"Death queue stays bounded")
	check(heat.conserved_population()==10000000,"Large loss preserves population")
	scene.arena.set_simulation(heat)
	# Replay the retained notifications as if consumed on the same rendering frame.
	scene.arena.last_death_serial = 0; scene.arena._update_death_effects(0.05)
	check(scene.arena.death_bursts.size()<=scene.arena.MAX_DEATH_BURSTS,"Live burst budget stays bounded")
	check(scene.arena.death_batch.multimesh.visible_instance_count<=512,"Particle budget stays bounded")
	heat.configure({"ants":30,"humans":0}); scene.arena.set_simulation(heat)
	check(heat.death_events.is_empty() and scene.arena.death_bursts.is_empty(),"New round clears death feedback")
	print("FEEDBACK_TEST_RESULT failures=",failures)
	quit(1 if failures else 0)

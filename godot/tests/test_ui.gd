extends SceneTree
func _init() -> void:run.call_deferred()
func run() -> void:
 root.size = Vector2i(1440,900)
 var scene = load("res://main.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 var begin = Time.get_ticks_usec()
 for i in range(15):scene.arena._update_ants()
 print("RENDER_BUFFER_MS ",(Time.get_ticks_usec()-begin)/15000.0)
 print("BUFFER_FIRST_X ",scene.arena.ant_buffer[3]," EXPECTED ",scene.sim.x[0])
 print("BUFFER_LENGTH ",scene.arena.ant_buffer.size()," INSTANCES ",scene.arena.ant_batch.multimesh.visible_instance_count)
 assert(is_equal_approx(scene.arena.ant_buffer[3],scene.sim.x[0]))
 scene.fields.humans.value = 3
 await process_frame
 scene.fields.human_target.value = 2
 scene.fields.mass.value = 115
 scene.fields.height.value = 2.02
 scene.start_round()
 assert(scene.sim.humans.size()==3)
 assert(scene.sim.humans[0].mass==78.0 and scene.sim.humans[1].mass==115.0)
 assert(is_equal_approx(scene.sim.humans[1].height,2.02))
 scene.toggle_pause()
 assert(not scene.running)
 scene.toggle_pause()
 assert(scene.running)
 scene.fields.temperature.value = 12
 assert(scene.sim.config.temperature==28.0)
 scene.start_round()
 assert(scene.sim.config.temperature==12.0)
 scene.fields.ants.value = 7
 scene.start_round()
 assert(scene.sim.population==7)
 assert(scene.sim.conserved_population()==7)
 scene.fields.ants.value = 1000000
 scene.prepare_round()
 var million_coverage = coverage(scene.arena.density_image)
 scene.fields.ants.value = 10000000
 scene.prepare_round()
 assert(scene.sim.population==10000000)
 assert(scene.sim.agent_count==6000)
 print("DETAIL_BUDGET ",scene.arena.detail_copies," COUNT ",scene.arena.detail_ant_count," VIEWPORT ",root.size)
 assert(scene.arena.detail_ant_count==48000)
 assert(scene.arena.density_population==9952000)
 assert(scene.arena.detail_ant_count+scene.arena.density_population==scene.sim.population)
 var ten_million_coverage = coverage(scene.arena.density_image)
 print("DENSITY_COVERAGE one_million=",million_coverage," ten_million=",ten_million_coverage)
 assert(ten_million_coverage>million_coverage*2)
 root.size = Vector2i(390,844)
 await process_frame
 scene._resize_layout()
 scene.prepare_round()
 assert(scene.arena.detail_ant_count==24000)
 assert(scene.arena.detail_ant_count+scene.arena.density_population==10000000)
 assert(scene.metrics.get_child_count()==4)
 assert(scene.toolbar.position.y+scene.toolbar.size.y<=root.size.y)
 for panel in scene.metrics.get_children():
  assert(panel.get_child(1).position.x+panel.get_child(1).size.x<=panel.size.x)
 assert(not scene.log_panel.visible)
 assert(scene.speed==1.0)
 scene.start_round()
 scene._toggle_controls()
 assert(scene.sidebar.visible and not scene.metrics.visible and not scene.running)
 scene._toggle_controls()
 assert(scene.running and not scene.sidebar.visible)
 scene._toggle_controls()
 assert(scene.sidebar.visible and not scene.metrics.visible)
 scene.start_round()
 assert(not scene.sidebar.visible and scene.metrics.visible)
 print("UI_TEST_PASS")
 quit()

func coverage(image: Image) -> float:
 var total = 0.0
 for y in range(image.get_height()):
  for x in range(image.get_width()): total += image.get_pixel(x,y).r
 return total

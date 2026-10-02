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
 assert(scene.human_hud.cards.size()==3)
 scene.sim.humans[0].pain = 24; scene.sim.humans[0].stamina = 82
 scene.sim.humans[1].pain = 67; scene.sim.humans[1].stamina = 35
 scene.human_hud.update_positions()
 assert(scene.human_hud.cards[0].pain.value==24 and scene.human_hud.cards[0].energy.value==82)
 assert(scene.human_hud.cards[1].pain.value==67 and scene.human_hud.cards[1].energy.value==35)
 assert(scene.human_hud.cards[0].title.text=="HUMANO 01" and scene.human_hud.cards[1].title.text=="HUMANO 02")
 for mode in [0,1,2]:
  scene.arena.camera_mode = mode; scene.arena._update_camera()
  scene.human_hud.update_positions(); check_cards(scene)
 scene.arena.camera_mode = 0; scene.arena._update_camera()
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
 assert(scene.metrics.get_child_count()==2)
 scene.human_hud.update_positions()
 check_cards(scene)
 assert(scene.toolbar.position.y+scene.toolbar.size.y<=root.size.y)
 for panel in scene.metrics.get_children():
  assert(panel.get_child(1).position.x+panel.get_child(1).size.x<=panel.size.x)
 assert(not scene.log_panel.visible)
 assert(scene.speed==1.0)
 scene.start_round()
 scene._toggle_controls()
 assert(scene.sidebar.visible and not scene.metrics.visible and not scene.running)
 assert(not scene.human_hud.visible)
 scene._toggle_controls()
 assert(scene.running and not scene.sidebar.visible)
 assert(scene.human_hud.visible)
 scene._toggle_controls()
 assert(scene.sidebar.visible and not scene.metrics.visible)
 scene.start_round()
 assert(not scene.sidebar.visible and scene.metrics.visible)
 scene.sim.humans[0].active = false
 for frame in range(330):scene.arena._animate_human(scene.arena.rigs[0],scene.sim.humans[0],1.0/60.0)
 scene.human_hud.update_positions()
 assert(not scene.human_hud.cards[0].panel.visible)
 scene.fields.humans.value = 0; scene.prepare_round()
 assert(scene.human_hud.cards.is_empty())
 print("UI_TEST_PASS")
 quit()

func check_cards(scene) -> void:
 var visible_cards: Array[Rect2] = []
 for card in scene.human_hud.cards:
  if not card.panel.visible:continue
  var rect: Rect2 = card.panel.get_rect()
  assert(Rect2(Vector2.ZERO,scene.human_hud.size).encloses(rect))
  for other in visible_cards:assert(not rect.intersects(other))
  visible_cards.append(rect)
 assert(visible_cards.size()>0)
 for link in scene.human_hud.links:
  var anchor: Vector3 = scene.arena.rigs[link.index].badge.global_position
  var expected: Vector2 = scene.arena.camera.unproject_position(anchor)*scene.picture.size/Vector2(scene.viewport3d.size)
  assert(link.to.distance_to(expected)<0.01)

func coverage(image: Image) -> float:
 var total = 0.0
 for y in range(image.get_height()):
  for x in range(image.get_width()): total += image.get_pixel(x,y).r
 return total

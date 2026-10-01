extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var view = load("res://main.tscn").instantiate()
	root.add_child(view); current_scene = view
	await process_frame
	view.suppress_signals = true
	view.fields.ants.value = 3500
	view.fields.scenario.selected = 2
	view.fields.behaviour.selected = 2
	view.suppress_signals = false; view.prepare_round()
	view._toggle_controls()
	var followed_gesture = false
	for frame in range(24*22):
		await process_frame
		if frame==24:
			view.config_tabs.current_tab = 1
		if frame==48:
			view.config_tabs.current_tab = 0
		if frame==72:
			view.start_button.pressed.emit()
			view.toolbar.get_child(3).selected = 2
			view.toolbar.get_child(3).item_selected.emit(2)
			view.arena.yaw = -1.05
		if frame==24*18:
			view.toolbar.get_child(3).selected = 0
			view.toolbar.get_child(3).item_selected.emit(0)
		if frame>=24*8 and frame<24*16 and not followed_gesture:
			for i in range(view.sim.humans.size()):
				var h = view.sim.humans[i]
				if h.action_kind==2 and h.action>0.8 and h.action<1.1 and h.action_area==0:
					view.arena.selected_human = i; followed_gesture = true
		if frame%96==0: print("GAMEPLAY_PROGRESS ",frame/24,"s")
	print("GAMEPLAY_DONE ",JSON.stringify(view.sim.summary()))
	quit()

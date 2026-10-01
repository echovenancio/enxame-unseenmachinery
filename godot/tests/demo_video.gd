extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func camera(view, index: int) -> void:
	view.toolbar.get_child(3).selected = index
	view.toolbar.get_child(3).item_selected.emit(index)

func run() -> void:
	var view = load("res://main.tscn").instantiate()
	root.add_child(view); current_scene = view
	await process_frame
	view.suppress_signals = true
	view.fields.ants.value = 3500; view.fields.scenario.selected = 2; view.fields.behaviour.selected = 2
	view.suppress_signals = false; view.prepare_round(); camera(view,2)
	for frame in range(24*14):
		await process_frame
		if frame==24: view.pause_button.pressed.emit()
		if frame==24*7:
			camera(view,0)
			view.fields.ants.value = 1000000; view.prepare_round(); view.start_round()
			view.toolbar.get_child(2).selected = 1; view.toolbar.get_child(2).item_selected.emit(1)
		if frame==24*10:
			view.fields.ants.value = 10000000; view.prepare_round(); view.start_round()
		if frame%72==0: print("DEMO_PROGRESS ",frame/24,"s")
	print("DEMO_DONE ",JSON.stringify(view.sim.summary()))
	quit()

extends SceneTree

# ---------------------------------------------------
# 火事の強さの計測：大きなビル（tower_builder.gd）の何か所かで出火させ、消えるまでに焼け落ちた部屋の数と、
# 消えるまでの時間を数える。火事の強さ（燃え広がる速さ・警備員の数）を見直すのに使う。
#
# 実行方法（ウィンドウ付きで起動する）:
#   godot --path . -s res://tools/fire_check.gd -- [警備室の数（省略すると7）]
# ---------------------------------------------------

const TowerBuilder := preload("res://tools/tower_builder.gd")
# 出火させる場所（オフィスの階の真ん中・高い階の住宅・低い階の端）
const STARTS := [Vector2i(1, 10), Vector2i(12, 2), Vector2i(-7, 15)]

func _init() -> void:
	var guards := 7
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		guards = int(args[0])
	root.mouse_passthrough = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var total := 0
	for start in STARTS:
		var main: Node2D = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		for i in 3:
			await process_frame
		main.save_system.autosave_enabled = false
		main.start_game()
		main.tutorial_system.finished = true
		TowerBuilder.build(main, guards)
		main.clock.set_time(1, 20, 0) # 出火する時刻（夜で、社員は帰っている）
		for i in 3:
			await process_frame
		var incidents = main.incident_system
		incidents.start_fire(start)
		var started: float = main.clock.minute
		Engine.time_scale = 16.0
		while incidents.has_fire():
			await process_frame
		Engine.time_scale = 1.0
		var ruins: int = main.message_log.filter(func(line): return line.contains("焼け落ちました")).size() # 焼け落ちた部屋の数
		var minutes: float = main.clock.minute - started
		if minutes < 0.0:
			minutes += 24 * 60
		print("%s（x=%d）から出火（警備室%d）: 焼け落ちた部屋 %d・消えるまで %d分" % [main.get_floor_name(start.y), start.x, guards, ruins, int(minutes)])
		total += ruins
		main.queue_free()
		await process_frame
	print("合計: 焼け落ちた部屋 %d（%d回の火事）" % [total, STARTS.size()])
	quit()

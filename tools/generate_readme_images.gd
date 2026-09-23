extends SceneTree

# ---------------------------------------------------
# README.md に載せる画像を作る（ドット絵を変えたら実行し直す）
#
# 実行方法（ウィンドウ付きで起動する。ゲーム画面の撮影に描画が必要なため --headless では不可）:
#   godot --path . -s res://tools/generate_readme_images.gd
#
# 作る画像（docs/images/ 以下）:
#   buildings/<種類>.png   … 建物のドット絵（4倍）
#   people/<名前>.png      … 人のドット絵（種類ごと・ストレスの段階ごと、8倍）
#   elevator/<名前>.png    … エレベーターのカゴ（8倍）
#   screenshots/*.png      … サンプルのビルのゲーム画面（昼・夜・ビルの状況）と、急行エレベーターの乗り換え
#   events/*.png           … イベント（火災・爆破予告・ゴキブリ・衛生の悪化・VIP・埋蔵金）の場面
# ---------------------------------------------------

const PixelArt := preload("res://scripts/view/pixel_art.gd")
const Resident := preload("res://scripts/actors/resident.gd")
const HotelSystem := preload("res://scripts/systems/hotel_system.gd")
const HousingSystem := preload("res://scripts/systems/housing_system.gd")
const EventSystem := preload("res://scripts/systems/event_system.gd")
const ParkingSystem := preload("res://scripts/systems/parking_system.gd")
const IncidentSystem := preload("res://scripts/systems/incident_system.gd")
const VisitorSystem := preload("res://scripts/systems/visitor_system.gd")
const ElevatorCar := preload("res://scripts/actors/elevator_car.gd")
const VipSystem := preload("res://scripts/systems/vip_system.gd")

const OUT := "res://docs/images"
const BUILDING_SCALE := 4
const PERSON_SCALE := 8

func _init() -> void:
	root.mouse_passthrough = true
	# ウィンドウが他のウィンドウの裏に隠れると、macOSに処理を間引かれて止まることがあるので、
	# 常に最前面に表示する（マウスは受け付けないので、前面にあってもほかの作業の邪魔にはならない）
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	for dir in ["buildings", "people", "elevator", "screenshots", "events"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join(dir)))

	save_building_images()
	save_people_images()
	save_elevator_images()
	await save_screenshots()
	await save_express_screenshot()
	await save_event_screenshots()
	print("README用の画像を作りました: ", ProjectSettings.globalize_path(OUT))
	quit()

# 画像を整数倍に拡大して保存する（ドット絵がぼやけないように最近傍で拡大）
func save_scaled(image: Image, scale: int, path: String) -> void:
	image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	image.save_png(ProjectSettings.globalize_path(path))

func save_building_images() -> void:
	for type in PixelArt.TILES:
		save_scaled(PixelArt.make_tile_image(type), BUILDING_SCALE, OUT.path_join("buildings/%s.png" % type))

# 人のドット絵（resident.gd の BODY_SPRITE）を、服と顔の色を変えて画像にする
func make_person_image(clothes: Color, face := Resident.BODY_COLORS["s"]) -> Image:
	var rows: Array = Resident.BODY_SPRITE
	var image := Image.create(rows[0].length() + 2, rows.size() + 2, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			var ch: String = rows[y][x]
			if ch == ".":
				continue
			var color: Color = clothes if ch == "c" else (face if ch == "s" else Resident.BODY_COLORS[ch])
			image.set_pixel(x + 1, y + 1, color)
	return image

func save_people_images() -> void:
	var people := {
		"worker": Color.WHITE,                               # 社員
		"guest": HotelSystem.GUEST_COLOR,                    # 宿泊客
		"housekeeper": HotelSystem.HOUSEKEEPER_COLOR,        # 清掃員
		"guard": IncidentSystem.GUARD_COLOR,                 # 警備員
		"housing": HousingSystem.RESIDENT_COLOR,             # 住宅の入居者
		"wedding": EventSystem.EVENT_TYPES.wedding.color,    # 結婚式の来客
		"event": EventSystem.EVENT_TYPES.event_hall.color,   # イベントの来客
		"parking": ParkingSystem.VISITOR_COLOR,              # 車で来たお客さん
		"restaurant_customer": VisitorSystem.SHOP_TYPES.restaurant.color, # 飲食店の外からの客
		"fastfood_customer": VisitorSystem.SHOP_TYPES.fastfood.color,     # ファストフードの外からの客
		"shop_customer": VisitorSystem.SHOP_TYPES.shop.color,             # ショップのお客さん
		"cinema_customer": VisitorSystem.CINEMA.color,                    # 映画のお客さん
		"vip": VipSystem.VIP_COLOR,                           # VIP
		"selected": Color(1.0, 0.85, 0.1),                   # 選択中（住人モード）
	}
	# ストレスは顔（肌）の色で表す（服は種類の色のまま）
	var faces := {
		"stress_low": Resident.BODY_COLORS["s"], # ストレス 0〜39
		"stress_mid": Resident.PINK_COLOR,       # ストレス 40〜69
		"stress_high": Resident.RED_COLOR,       # ストレス 70〜100
		"stress_angry": Resident.ANGRY_COLOR,    # 激怒（赤と交互に点滅する明るい方）
	}
	for name in people:
		save_scaled(make_person_image(people[name]), PERSON_SCALE, OUT.path_join("people/%s.png" % name))
	for name in faces:
		save_scaled(make_person_image(Color.WHITE, faces[name]), PERSON_SCALE, OUT.path_join("people/%s.png" % name))

# エレベーターのカゴ（elevator_car.gd の描き方と同じ色・形）
func save_elevator_images() -> void:
	# 急行のカゴ（金色の扉）
	var express := Image.create(16, 18, false, Image.FORMAT_RGBA8)
	express.fill_rect(Rect2i(1, 4, 14, 14), Color.BLACK)
	express.fill_rect(Rect2i(2, 5, 12, 12), ElevatorCar.EXPRESS_COLOR)
	express.fill_rect(Rect2i(8, 5, 1, 12), Color(0.3, 0.3, 0.35))
	express.fill_rect(Rect2i(2, 15, 3, 2), Color(0.3, 1.0, 0.4))
	save_scaled(express, PERSON_SCALE, OUT.path_join("elevator/express_closed.png"))
	for open in [false, true]:
		var image := Image.create(16, 18, false, Image.FORMAT_RGBA8)
		# 進行方向の▲
		for i in 4:
			for x in range(8 - i, 8 + i):
				image.set_pixel(x, 1 + i, Color(0.3, 1.0, 0.4))
		image.fill_rect(Rect2i(1, 4, 14, 14), Color.BLACK)
		if open:
			image.fill_rect(Rect2i(2, 5, 12, 12), Color(1.0, 0.95, 0.7))
			image.fill_rect(Rect2i(2, 5, 2, 12), Color(0.75, 0.78, 0.85))
			image.fill_rect(Rect2i(12, 5, 2, 12), Color(0.75, 0.78, 0.85))
		else:
			image.fill_rect(Rect2i(2, 5, 12, 12), Color(0.75, 0.78, 0.85))
			image.fill_rect(Rect2i(8, 5, 1, 12), Color(0.3, 0.3, 0.35))
		# 乗っている人数のゲージ（開いている方は満員の赤）
		image.fill_rect(Rect2i(2, 15, 12 if open else 6, 2), Color(1.0, 0.3, 0.3) if open else Color(0.3, 1.0, 0.4))
		save_scaled(image, PERSON_SCALE, OUT.path_join("elevator/%s.png" % ("open_full" if open else "closed")))

# サンプルのビルを建てて、昼と夜のゲーム画面を撮る
func save_screenshots() -> void:
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	m.start_game() # タイトル画面を閉じる
	m.tutorial_system.finished = true # はじめての案内のバーを写さない
	m.funds = 100000000
	# 更地から建てる: 1階はロビー（入口は左端）、2階から上にテナント、x=8 のシャフトでつなぐ
	# 建物は下の階に建物がないと建てられないので、1階から上へ（地下は1階から下へ）順に建てる
	build(m, "lobby", range(-12, 8).map(func(x): return Vector2i(x, 18)))
	build(m, "lobby", range(9, 19).map(func(x): return Vector2i(x, 18)))
	build(m, "elevator", range(18, 10, -1).map(func(y): return Vector2i(8, y)))
	build(m, "elevator", [Vector2i(8, 19)])
	m.elevator_system.add_car(Vector2i(8, 12))
	m.elevator_system.add_car(Vector2i(8, 15))
	for y in [17, 16, 15]:
		build(m, "office", [Vector2i(-12, y), Vector2i(-8, y), Vector2i(-4, y), Vector2i(0, y), Vector2i(4, y)])
	build(m, "office", [Vector2i(-4, 14), Vector2i(0, 14), Vector2i(4, 14)]) # 5階はエレベーターから左端まで歩いて行ける
	build(m, "small_office", [Vector2i(-12, 14)])
	build(m, "large_office", [Vector2i(-10, 14)])
	build(m, "event_hall", [Vector2i(2, 13)])
	build(m, "restaurant", [Vector2i(9, 17)])
	build(m, "hotel", [Vector2i(12, 17)])
	build(m, "hotel_twin", [Vector2i(14, 17)])
	build(m, "housekeeping", [Vector2i(17, 17)])
	build(m, "hotel_suite", [Vector2i(9, 16)])
	build(m, "housing", [Vector2i(13, 16)])
	build(m, "security", [Vector2i(16, 16)])
	build(m, "medical", [Vector2i(9, 15)])
	build(m, "recycling", [Vector2i(12, 15)])
	build(m, "fastfood", [Vector2i(15, 15)])
	build(m, "wedding", [Vector2i(9, 14)])
	build(m, "subway", [Vector2i(9, 19)])
	m.select_mode("office")
	m.camera.zoom = Vector2(2.4, 2.4)
	m.camera.focus_on(m.tile_map.to_global(m.tile_map.map_to_local(Vector2i(3, 15))))

	# 昼（昼休み。飲食店とエレベーターが混み合う）
	m.clock.set_time(1, 7, 59)
	Engine.time_scale = 16.0
	while m.clock.minute_of_day() < 12 * 60 + 25:
		await process_frame
	await capture(m, "screenshots/day.png")
	# 夜（客室・住宅・設備に明かりが灯る）
	m.clock.set_time(1, 16, 59)
	while m.clock.minute_of_day() < 21 * 60 + 30:
		await process_frame
	Engine.time_scale = 1.0
	await capture(m, "screenshots/night.png")
	# ★を押して開く「ビルの状況」（同じ日の昼に戻して撮る。日をまたぐと決算や目標の画面が出るため）
	m.clock.set_time(1, 13, 0)
	m.ui.goal_panel.visible = false
	m.ui.stats_panel.visible = true
	await capture(m, "screenshots/stats_panel.png")
	m.ui.stats_panel.visible = false
	m.queue_free()
	await process_frame

func build(m, type: String, origins: Array) -> void:
	m.select_mode(type)
	for origin in origins:
		m.build_at(origin)

func capture(m, path: String) -> void:
	m.clock.set_process(false)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT.path_join(path)))
	m.clock.set_process(true)

# ---------------------------------------------------
# 1つの場面を撮るための、まっさらなゲームを用意する（昼の13時で時計は止めておく）
# ---------------------------------------------------
func new_world():
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	m.start_game()
	m.tutorial_system.finished = true
	m.clear_world()
	m.funds = 100000000
	m.clock.set_time(1, 13, 0)
	m.clock.set_process(false)
	m.camera.zoom = Vector2(3.0, 3.0)
	return m

# 建てたときのメッセージを消す（イベントのメッセージだけが写るように）
func quiet(m) -> void:
	m.message_log.clear()
	m.ui.show_messages(m.message_log)

func focus(m, cell: Vector2i) -> void:
	m.camera.focus_on(m.tile_map.to_global(m.tile_map.map_to_local(cell)))

# 撮って、その場面のゲームを片づける
func shoot(m, path: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT.path_join(path)))
	Engine.time_scale = 1.0
	m.queue_free()
	await process_frame

# 事件の場面を撮るための、小さなビル（1〜4階。x=8 にエレベーター、左右にテナント）
func small_tower(m) -> void:
	build(m, "lobby", range(4, 8).map(func(x): return Vector2i(x, 18)))
	build(m, "lobby", range(9, 21).map(func(x): return Vector2i(x, 18)))
	build(m, "elevator", range(18, 14, -1).map(func(y): return Vector2i(8, y)))
	build(m, "security", [Vector2i(9, 17)])
	build(m, "shop", [Vector2i(11, 17), Vector2i(14, 17)])
	build(m, "restaurant", [Vector2i(17, 17)])
	build(m, "frame", [Vector2i(20, 17)])
	build(m, "office", [Vector2i(4, 17), Vector2i(4, 16), Vector2i(9, 16), Vector2i(13, 16), Vector2i(17, 16)])
	build(m, "hotel", [Vector2i(4, 15), Vector2i(6, 15), Vector2i(9, 15), Vector2i(11, 15)])
	build(m, "hotel_twin", [Vector2i(13, 15), Vector2i(16, 15)])
	quiet(m)

func save_express_screenshot() -> void:
	# 急行エレベーターで15階のスカイロビーへ上がり、標準エレベーターに乗り換える（経路を線で出す）
	var m = await new_world()
	build(m, "lobby", range(0, 8).map(func(x): return Vector2i(x, 18)))
	build(m, "lobby", range(9, 17).map(func(x): return Vector2i(x, 18)))
	build(m, "express_elevator", range(18, 3, -1).map(func(y): return Vector2i(8, y)))
	build(m, "elevator", range(18, 4, -1).map(func(y): return Vector2i(17, y))) # 2〜14階へ行く標準エレベーター
	for y in range(17, 4, -1): # 2階〜14階はオフィス
		build(m, "office", [Vector2i(0, y), Vector2i(4, y), Vector2i(9, y), Vector2i(13, y)])
	# 15階のスカイロビー（x=12 は、そこから上へ行く標準エレベーターのために空けておく）
	build(m, "sky_lobby", [9, 10, 11, 13, 14, 15, 16].map(func(x): return Vector2i(x, 4)))
	build(m, "sky_lobby", range(0, 8).map(func(x): return Vector2i(x, 4)))
	build(m, "elevator", range(4, -1, -1).map(func(y): return Vector2i(12, y))) # 15階から上の標準エレベーター
	for y in range(3, -1, -1): # 16階〜19階（右側だけ）
		build(m, "office", [Vector2i(13, y)])
		build(m, "frame", [Vector2i(9, y), Vector2i(10, y), Vector2i(11, y)])
	quiet(m)
	var worker = m.spawn_resident(Vector2i(1, 18))
	worker.go_to(Vector2i(14, 1))
	m.show_routes = true
	# 急行のカゴに乗って上がっている途中を撮る（経路の線で、15階で乗り換えるのがわかる）
	m.clock.set_process(true)
	Engine.time_scale = 4.0
	var waited := 0
	while (worker.state != worker.State.RIDING or worker.car.current_floor() > 12) and waited < 3000:
		waited += 1 # 念のため、いつまでも待たない
		await process_frame
	m.clock.set_process(false)
	Engine.time_scale = 1.0
	m.camera.zoom = Vector2(1.6, 1.6)
	focus(m, Vector2i(9, 9))
	await shoot(m, "screenshots/express.png")

func save_event_screenshots() -> void:
	# 火災: 燃えているマス（炎）と、焼け落ちた部屋（焼け跡）
	var m = await new_world()
	small_tower(m)
	m.incident_system.start_fire(Vector2i(14, 17))
	m.incident_system.spread_fire()
	m.incident_system.spread_fire()
	m.destroy_unit(Vector2i(17, 17))
	focus(m, Vector2i(13, 16))
	await shoot(m, "events/fire.png")

	# 爆破予告: 身代金を払うか決める画面
	m = await new_world()
	small_tower(m)
	m.funds = 10000000
	m.update_funds_display()
	m.incident_system.start_bomb(Vector2i(14, 17))
	focus(m, Vector2i(13, 16))
	await shoot(m, "events/bomb_ransom.png")

	# 爆弾の捜索: 支払わないと、警備員が近いテナントから順に調べて回る（★を押すと進み具合が出る）
	m = await new_world()
	small_tower(m)
	build(m, "lobby", [Vector2i(21, 18), Vector2i(22, 18)])
	build(m, "security", [Vector2i(21, 17)])
	quiet(m)
	m.incident_system.start_bomb(Vector2i(16, 15))
	m.incident_system.refuse_ransom()
	m.clock.set_process(true)
	Engine.time_scale = 8.0
	while m.incident_system.has_bomb() and m.incident_system.bomb.searched.size() < 3:
		await process_frame
	m.clock.set_process(false)
	Engine.time_scale = 1.0
	m.ui.stats_panel.visible = true
	focus(m, Vector2i(13, 15))
	await shoot(m, "events/bomb_search.png")

	# 爆発: 爆弾の棟と、まわりのテナントがまとめて焼け跡になる
	m = await new_world()
	small_tower(m)
	m.incident_system.start_bomb(Vector2i(14, 17))
	m.incident_system.bomb.decided = true
	m.ui.hide_ransom_panel()
	m.incident_system.explode()
	focus(m, Vector2i(13, 16))
	await shoot(m, "events/blast.png")

	# ゴキブリ: 掃除されない客室や、汚れたビルのテナントに出る
	m = await new_world()
	small_tower(m)
	for origin in [Vector2i(9, 15), Vector2i(11, 15), Vector2i(11, 17), Vector2i(13, 16)]:
		m.incident_system.roaches[origin] = true
	m.hotel_system.rooms[Vector2i(9, 15)].state = m.hotel_system.RoomState.DIRTY
	m.hotel_system.rooms[Vector2i(11, 15)].state = m.hotel_system.RoomState.DIRTY
	focus(m, Vector2i(12, 16))
	await shoot(m, "events/roach.png")

	# 衛生の悪化: ビル全体が茶色くくすみ、汚れの点が付く
	m = await new_world()
	small_tower(m)
	m.economy_system.pollution = 4
	focus(m, Vector2i(12, 16))
	await shoot(m, "events/pollution.png")

	# VIP: VIP専用のエレベーター（右端の金色の帯）で、スイートへ向かう
	m = await new_world()
	build(m, "lobby", range(4, 8).map(func(x): return Vector2i(x, 18)))
	build(m, "lobby", range(10, 20).map(func(x): return Vector2i(x, 18)))
	build(m, "elevator", range(18, 13, -1).map(func(y): return Vector2i(8, y)))
	build(m, "elevator", range(18, 13, -1).map(func(y): return Vector2i(9, y)))
	for y in [17, 16, 15]:
		build(m, "office", [Vector2i(4, y), Vector2i(10, y), Vector2i(14, y)])
	build(m, "frame", range(4, 8).map(func(x): return Vector2i(x, 14)))
	build(m, "hotel_suite", [Vector2i(10, 14)])
	m.elevator_system.toggle_vip_only(Vector2i(9, 18))
	m.elevator_system.set_home(Vector2i(9, 18))
	quiet(m)
	m.clock.set_time(1, 16, 0)
	m.vip_system.invite() # 小さなビルでは★4の条件がそろわないので、直接呼ぶ
	m.clock.set_process(true)
	Engine.time_scale = 4.0
	var vip = m.vip_system.vip
	while is_instance_valid(vip) and vip.state != vip.State.RIDING:
		await process_frame
	for i in 20:
		await process_frame
	m.clock.set_process(false)
	Engine.time_scale = 1.0
	m.show_routes = true
	focus(m, Vector2i(10, 16))
	await shoot(m, "events/vip.png")

	# 埋蔵金: 地下を掘ると、宝箱と金塊が飛び出す
	m = await new_world()
	build(m, "lobby", range(4, 16).map(func(x): return Vector2i(x, 18)))
	var incidents = m.incident_system
	# 見えるところで掘り当てるマスを探す（ほかのマスでは見つからないよう、先に掘ったことにしておく）
	var lucky := Vector2i.ZERO
	for y in range(19, 30):
		for x in range(4, 16):
			var cell := Vector2i(x, y)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([cell, "treasure"])
			if lucky == Vector2i.ZERO and y >= 22 and rng.randf() < incidents.treasure_chance(y - m.ground_y):
				lucky = cell
			else:
				incidents.dug[cell] = true
	for y in range(19, lucky.y):
		build(m, "frame", range(4, 16).map(func(x): return Vector2i(x, y)))
	quiet(m)
	build(m, "frame", [lucky]) # ここで掘り当てる
	for i in 6:
		await process_frame
	focus(m, lucky + Vector2i(0, -2))
	await shoot(m, "events/treasure.png")

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
#   screenshots/*.png      … サンプルのビルのゲーム画面（昼・夜）
# ---------------------------------------------------

const PixelArt := preload("res://pixel_art.gd")
const Resident := preload("res://resident.gd")
const HotelSystem := preload("res://hotel_system.gd")
const HousingSystem := preload("res://housing_system.gd")
const EventSystem := preload("res://event_system.gd")

const OUT := "res://docs/images"
const BUILDING_SCALE := 4
const PERSON_SCALE := 8

func _init() -> void:
	root.mouse_passthrough = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	for dir in ["buildings", "people", "elevator", "screenshots"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join(dir)))

	save_building_images()
	save_people_images()
	save_elevator_images()
	await save_screenshots()
	print("README用の画像を作りました: ", ProjectSettings.globalize_path(OUT))
	quit()

# 画像を整数倍に拡大して保存する（ドット絵がぼやけないように最近傍で拡大）
func save_scaled(image: Image, scale: int, path: String) -> void:
	image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	image.save_png(ProjectSettings.globalize_path(path))

func save_building_images() -> void:
	for type in PixelArt.TILES:
		save_scaled(PixelArt.make_tile_image(type), BUILDING_SCALE, OUT.path_join("buildings/%s.png" % type))

# 人のドット絵（resident.gd の BODY_SPRITE）を、服の色を変えて画像にする
func make_person_image(clothes: Color) -> Image:
	var rows: Array = Resident.BODY_SPRITE
	var image := Image.create(rows[0].length() + 2, rows.size() + 2, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			var ch: String = rows[y][x]
			if ch == ".":
				continue
			image.set_pixel(x + 1, y + 1, clothes if ch == "c" else Resident.BODY_COLORS[ch])
	return image

func save_people_images() -> void:
	var people := {
		"worker": Color.WHITE,                               # 社員
		"guest": HotelSystem.GUEST_COLOR,                    # 宿泊客
		"housekeeper": HotelSystem.HOUSEKEEPER_COLOR,        # 清掃員
		"housing": HousingSystem.RESIDENT_COLOR,             # 住宅の入居者
		"wedding": EventSystem.EVENT_TYPES.wedding.color,    # 結婚式の来客
		"event": EventSystem.EVENT_TYPES.event_hall.color,   # イベントの来客
		"selected": Color(1.0, 0.85, 0.1),                   # 選択中（住人モード）
		"stress_low": Color.WHITE,                           # ストレス 0〜39
		"stress_mid": Resident.PINK_COLOR,                   # ストレス 40〜69
		"stress_high": Resident.RED_COLOR,                   # ストレス 70〜100
	}
	for name in people:
		save_scaled(make_person_image(people[name]), PERSON_SCALE, OUT.path_join("people/%s.png" % name))

# エレベーターのカゴ（elevator_car.gd の描き方と同じ色・形）
func save_elevator_images() -> void:
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
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	m.funds = 100000000
	# 更地から建てる: 1階はロビー（入口は左端）、2階から上にテナント、x=8 のシャフトでつなぐ
	build(m, "lobby", range(-12, 8).map(func(x): return Vector2i(x, 18)))
	build(m, "elevator", range(11, 20).map(func(y): return Vector2i(8, y)))
	m.elevator_system.add_car(Vector2i(8, 12))
	m.elevator_system.add_car(Vector2i(8, 15))
	for y in [15, 16, 17]:
		build(m, "office", [Vector2i(-12, y), Vector2i(-8, y), Vector2i(-4, y), Vector2i(0, y), Vector2i(4, y)])
	build(m, "office", [Vector2i(0, 14), Vector2i(4, 14)])
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

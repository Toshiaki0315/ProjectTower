extends Node2D

# ---------------------------------------------------
# 夜の明かり：空が暗くなるほど建物のタイルを暗くし、人がいる部屋にだけ明かりを灯す。
#   明かりが灯るマス（get_lit_cells）:
#     オフィス          … 社員が自分の席にいるマス
#     客室              … 宿泊客がいる部屋の全マス
#     住宅              … 家にいる人の部屋のマス
#     飲食店・会場      … 客がいる間、建物の全マス
#     階段・エレベーター・設備 … いつも（一晩中灯っている）
#   街灯: ビルの外の地面（1階の高さの空きマス）に LAMP_SPACING マスおきに立ち、夜に灯る
#   入口の照明: 1階の入口・地下鉄駅の扉の周りが、夜に光る
# 明かりは加算合成で重ねるので、暗くしたタイルの上で暖かい色に光って見える。
# TileMapLayerの子として追加するので、座標はタイルマップ座標系。
# ---------------------------------------------------

const NIGHT_TINT := Color(0.35, 0.4, 0.55) # 真っ暗な夜のときの建物の色（タイルに掛ける）
const LIGHT_COLOR := Color(0.6, 0.45, 0.2) # 明かりの色（加算する）
const ALWAYS_LIT := ["lobby", "lobby2", "lobby3", "sky_lobby", "stairs", "escalator", "elevator", "express_elevator", "service_elevator", "housekeeping", "recycling", "security", "medical", "subway"]
const LAMP_SPACING := 4        # 街灯の間隔（マス）
const LAMP_HEIGHT := 13.0      # 街灯の高さ（ドット）
const GLOW_COLOR := Color(1.0, 0.75, 0.35) # 街灯・入口の照明の光の色

var world: Node2D # main.gd

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 7 # タイルや部屋の状態の表示より手前、カゴ・住人より奥
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive

func _process(_delta: float) -> void:
	# 建物のタイルだけを暗くする（self_modulate は子の住人やカゴには効かない）
	var darkness: float = world.clock.darkness()
	world.tile_map.self_modulate = Color.WHITE.lerp(NIGHT_TINT, darkness)
	queue_redraw()

# 今、明かりが灯っているマス（マス -> true）
func get_lit_cells() -> Dictionary:
	var lit := {}
	for type in ALWAYS_LIT:
		for cell in world.find_cells_of_type(type):
			lit[cell] = true
	# オフィス: 社員が席にいるマス
	var workers: Dictionary = world.commute_system.workers
	for office in workers:
		if is_present(workers[office].resident, office):
			lit[office] = true
	# 客室: 宿泊客がいる部屋の全マス
	for room_cell in world.hotel_system.rooms:
		var room = world.hotel_system.rooms[room_cell]
		for guest in room.guests:
			if is_instance_valid(guest) and world.get_unit_cells(room_cell).has(guest.cell) and not guest.is_moving():
				for c in world.get_unit_cells(room_cell):
					lit[c] = true
				break
	# 住宅: 家にいる人の部屋
	for home in world.housing_system.homes.values():
		for m in home.members:
			if world.housing_system.is_at_home(m):
				lit[m.room] = true
	# 飲食店・会場: 客がいる間、建物の全マス
	for restaurant in world.find_units_of_type("restaurant"):
		if world.commerce_system.count_eating_at(restaurant) > 0:
			for c in world.get_unit_cells(restaurant):
				lit[c] = true
	for hall in world.event_system.halls:
		if world.event_system.count_at_hall(hall) > 0:
			for c in world.get_unit_cells(hall):
				lit[c] = true
	return lit

# 画面に映っている範囲（visible_rect、タイルマップ座標系）にある街灯の、灯りの位置の一覧
# 街灯は1階の高さの、建物のない空きマスに LAMP_SPACING マスおきに立つ
func get_street_lamps(visible_rect: Rect2) -> Array[Vector2]:
	var lamps: Array[Vector2] = []
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	var first := int(floor(visible_rect.position.x / tile_size.x)) - 1
	var last := int(ceil(visible_rect.end.x / tile_size.x)) + 1
	var floor_y: float = (world.ground_y + 1) * tile_size.y # 地面の高さ（1階の床の下端 = 地面の線）
	for x in range(first, last + 1):
		if posmod(x, LAMP_SPACING) != 0 or not world.is_cell_empty(Vector2i(x, world.ground_y)):
			continue
		lamps.append(Vector2((x + 0.5) * tile_size.x, floor_y - LAMP_HEIGHT))
	return lamps

# 入口の照明の位置の一覧（扉のある左端の、少し上）
func get_entrance_lights() -> Array[Vector2]:
	var lights: Array[Vector2] = []
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	for entrance in world.get_entrances():
		lights.append(Vector2(entrance) * tile_size + Vector2(3, 4))
	return lights

func is_present(resident, cell: Vector2i) -> bool:
	return is_instance_valid(resident) and resident.cell == cell and not resident.is_moving()

func _draw() -> void:
	var darkness: float = world.clock.darkness()
	if darkness <= 0.0:
		return
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	var color := LIGHT_COLOR * darkness
	color.a = 1.0
	for cell in get_lit_cells():
		# 天井と床の線は残して、部屋の中だけを明るくする
		draw_rect(Rect2(Vector2(cell) * tile_size + Vector2(0, 1), Vector2(tile_size.x, tile_size.y - 3)), color)
	
	# 街灯と入口の照明: 中心が明るく、外へ行くほど弱い光の輪を重ねる
	var visible_rect: Rect2 = get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	for pos in get_street_lamps(visible_rect) + get_entrance_lights():
		draw_glow(pos, darkness)

func draw_glow(pos: Vector2, darkness: float) -> void:
	for ring in [[14.0, 0.12], [9.0, 0.18], [5.0, 0.3], [2.0, 0.6]]:
		var c: Color = GLOW_COLOR * (ring[1] * darkness)
		c.a = 1.0
		draw_circle(pos, ring[0], c)

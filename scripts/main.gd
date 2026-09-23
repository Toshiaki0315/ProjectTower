extends Node2D

const Resident := preload("res://scripts/actors/resident.gd")
const PixelArt := preload("res://scripts/view/pixel_art.gd")
const GridOverlay := preload("res://scripts/view/grid_overlay.gd")
const ElevatorSystem := preload("res://scripts/systems/elevator_system.gd")
const ParkingSystem := preload("res://scripts/systems/parking_system.gd")
const VisitorSystem := preload("res://scripts/systems/visitor_system.gd")
const NoiseSystem := preload("res://scripts/systems/noise_system.gd")
const VipSystem := preload("res://scripts/systems/vip_system.gd")
const IncidentSystem := preload("res://scripts/systems/incident_system.gd")
const WeatherSystem := preload("res://scripts/systems/weather_system.gd")
const SaveSystem := preload("res://scripts/systems/save_system.gd")
const Ui := preload("res://scripts/view/ui.gd")
const Buildings := preload("res://scripts/systems/buildings.gd")
const Pathfinding := preload("res://scripts/systems/pathfinding.gd")
const Effects := preload("res://scripts/view/effects.gd")
const AudioSystem := preload("res://scripts/systems/audio_system.gd")
const GoalSystem := preload("res://scripts/systems/goal_system.gd")
const TutorialSystem := preload("res://scripts/systems/tutorial_system.gd")
const GameClock := preload("res://scripts/systems/game_clock.gd")
const CommuteSystem := preload("res://scripts/systems/commute_system.gd")
const EconomySystem := preload("res://scripts/systems/economy_system.gd")
const HotelSystem := preload("res://scripts/systems/hotel_system.gd")
const CommerceSystem := preload("res://scripts/systems/commerce_system.gd")
const RatingSystem := preload("res://scripts/systems/rating_system.gd")
const HousingSystem := preload("res://scripts/systems/housing_system.gd")
const EventSystem := preload("res://scripts/systems/event_system.gd")
const Lighting := preload("res://scripts/view/lighting.gd")
const CinemaScreen := preload("res://scripts/view/cinema_screen.gd")
const SkyEvents := preload("res://scripts/view/sky_events.gd")
const TenantSystem := preload("res://scripts/systems/tenant_system.gd")

@onready var tile_map = $TileMapLayer
@onready var camera = $Camera2D

# 建物の表と、建てる・撤去するルールは buildings.gd が持つ
const BUILDINGS := Buildings.TABLE
const SKY_LOBBY_INTERVAL := Buildings.SKY_LOBBY_INTERVAL
const MAX_FLOORS_ABOVE := Buildings.MAX_FLOORS_ABOVE
const MAX_FLOORS_BELOW := Buildings.MAX_FLOORS_BELOW
const MAX_WIDTH := Buildings.MAX_WIDTH
const OFFICE_TYPES := Buildings.OFFICE_TYPES
const SUBWAY_MIN_DEPTH := Buildings.SUBWAY_MIN_DEPTH
const CURRENCY := "Cr" # お金の単位（クレジット）。画面に出る金額はすべてこの単位で書く
const DEMOLISH_RATE := 0.1      # 撤去費用: 建設費のこの割合を払う（撤去しても建設費は戻らない）
const MIN_DEMOLISH_FEE := 2000  # 撤去費用の最低額（焼け跡・空きフロア・ロビーなども、これだけはかかる）
const MODE_RESIDENT := "resident" # 住人を配置・移動させるモード
const MODE_ADD_CAR := "add_car"   # エレベーターのシャフトにカゴを追加するモード
const MODE_SET_HOME := "set_home" # エレベーターの待機階（呼び出しがないとカゴが戻る階）を決めるモード
const MODE_SERVICE := "service"   # エレベーターの稼働時間帯を切り替えるモード
const MODE_VIP_ONLY := "vip_only" # エレベーターをVIP専用にする（VIPの来館中はVIPだけが乗れる）
const MODE_RENT := "rent"         # オフィスの家賃（安い・普通・高い）を切り替えるモード
const MODE_DEMOLISH := "demolish" # 左クリックで撤去するモード（右クリックでも撤去できる）

# 建設メニューの並び（見出しごとにまとめる）。BUILDINGS に建物を足したら、ここにも入れる
const MODE_GROUPS := [
	{"name": "テナント", "modes": ["small_office", "office", "large_office", "hotel", "hotel_twin", "hotel_suite", "restaurant", "fastfood", "shop", "cinema", "housing", "wedding", "event_hall"]},
	{"name": "ロビー・移動", "modes": ["lobby", "lobby2", "lobby3", "sky_lobby", "frame", "stairs", "escalator", "elevator", "express_elevator", "large_elevator", "service_elevator", "add_car", "set_home", "service", "vip_only"]},
	{"name": "設備", "modes": ["housekeeping", "recycling", "security", "medical", "subway", "ramp", "parking", "helipad", "garden"]},
	{"name": "その他", "modes": ["rent", "demolish", "resident"]},
]
const SCROLL_MARGIN_ROWS := 10 # スクロールできる範囲の、建物の上下に足す余白（行数）

var funds: int = 2000000
var current_mode: String = "lobby" # 更地から始めるので、最初はロビーを選んでおく
# 画面の部品は ui.gd が持つ。ほかのファイル・テストから使えるよう、ここから読めるようにする
var ui                     # scripts/view/ui.gd
var funds_label: Label:
	get: return ui.funds_label
var clock_label: Label:
	get: return ui.clock_label
var stats_label: Label:
	get: return ui.stats_label
var stats_button: Button:
	get: return ui.stats_button
var stats_panel: Control:
	get: return ui.stats_panel
var speed_button: Button:
	get: return ui.speed_button
var route_button: Button:
	get: return ui.route_button
var menu_bar: MenuBar:
	get: return ui.menu_bar
var mode_select: OptionButton:
	get: return ui.mode_select
var message_label: Label:
	get: return ui.message_label
var hover_label: Label:
	get: return ui.hover_label
var hover_tooltip: Control:
	get: return ui.hover_tooltip
var help_panel: Control:
	get: return ui.help_panel
var log_panel: Control:
	get: return ui.log_panel
var log_label: Label:
	get: return ui.log_label
var chart_panel: Control:
	get: return ui.chart_panel
var tutorial_panel: Control:
	get: return ui.tutorial_panel
var tutorial_label: Label:
	get: return ui.tutorial_label
var title_panel: Control:
	get: return ui.title_panel
var goal_panel: Control:
	get: return ui.goal_panel
var goal_title: Label:
	get: return ui.goal_title
var goal_text: Label:
	get: return ui.goal_text
var v_scroll: VScrollBar:
	get: return ui.v_scroll

# ゲームの中身（仕組み・状態）
const GROUND_FLOOR_Y := 18
const SPEEDS := [1, 4, 16]    # ゲームの速度（押すたびにこの順に切り替わる）
const MEDICAL_RECOVER_BONUS := 0.5 # メディカルセンター1施設で、ストレスの回復が何割速くなるか
const GARDEN_RECOVER_BONUS := 0.3  # 屋上庭園1つで、ストレスの回復が何割速くなるか
const MEDICAL_RECOVER_MAX := 2.5   # 回復の速さの上限（何倍まで）
const MESSAGE_LOG_MAX := 500  # ⌘Lで見られるメッセージの記録の数

var building_grid: Dictionary = {} # マス -> {type, origin}
var residents: Array = []          # 配置済みの住人
var selected_resident = null       # 行き先の指示を待っている住人
var started := false               # ゲームが始まっているか（タイトル画面の間は false）
var drag_button := 0               # 押したままなぞっているマウスのボタン（0なら押していない）
var drag_last_cell := Vector2i.ZERO # なぞっている間に、最後に処理したマス
var show_routes := false           # 経路（人の通り道）を線で表示するか
var test_tools := false            # テスト用の道具（「住人（テスト）」）を建設メニューに出すか。テストのときだけ true にする
var message_log: Array[String] = [] # ゲーム開始からのメッセージ（時刻つき）
var last_message := ""             # 一番新しいメッセージ（時刻なし）

# 見た目
var buildings    # 建物の表と、建てる・撤去するルール
var pathfinding  # 移動ルールと経路探索
var grid_overlay # マス目の表示
var effects      # 建設・撤去・お金の演出
var lighting     # 夜の明かり
var cinema_screen # 映画館のスクリーン（上映中・開場中・閉館の見た目）
var sky_events   # 空のイベント（飛行機・鳥・気球・虹・流れ星・ロケット・UFO・花火。見た目だけ）

# 仕組み（systems）
var clock           # ゲーム内の時計
var elevator_system # エレベーターのシャフトとカゴの管理
var parking_system  # 地下駐車場とスロープ（車で来るお客さん）
var visitor_system  # 外から来るお客さん（店の客・車で来た客）の動き
var noise_system    # 騒音（うるさい建物のまわりのマスに広がる）
var vip_system      # VIPの宿泊（★4への昇格イベント）
var incident_system # 事件（爆破予告・火災・ゴキブリ・埋蔵金）
var weather_system  # 天気（晴れ・くもり・雨）
var save_system     # セーブ／ロード
var audio_system    # 音（効果音とBGM）
var goal_system     # 目標（シナリオ）
var tutorial_system # はじめての案内
var commute_system  # オフィスの社員の出退勤
var economy_system  # 毎日の決算（賃料収入と維持費）
var hotel_system    # ホテルの客室・宿泊客・清掃員
var commerce_system # 飲食店（社員の昼食）
var rating_system   # ビルの評価（★）
var housing_system  # 住宅と入居者
var event_system    # 結婚式場・イベントホール（休日の来客）
var tenant_system   # テナント（オフィス）の評価

var ground_y := GROUND_FLOOR_Y

# ゲームの部品（仕組みと見た目）の一覧。ここに1行足すだけで組み込める。
#   name:   main の変数名        script: その部品のスクリプト
#   parent: "map" ならタイルマップの子にする（マスに重ねて描くもの）
#   rebuild: true なら、作った直後に建物に合わせて中身を作る
const PARTS := [
	{"name": "buildings", "script": Buildings},       # 建物の表とルール（タイルの用意より先に必要）
	{"name": "pathfinding", "script": Pathfinding},   # 移動ルールと経路探索
	{"name": "clock", "script": GameClock},           # ゲーム内の時計
	{"name": "elevator_system", "script": ElevatorSystem, "rebuild": true},
	{"name": "commute_system", "script": CommuteSystem, "rebuild": true},
	{"name": "hotel_system", "script": HotelSystem, "parent": "map", "rebuild": true},
	{"name": "housing_system", "script": HousingSystem, "rebuild": true},
	{"name": "event_system", "script": EventSystem, "rebuild": true},
	{"name": "commerce_system", "script": CommerceSystem},
	{"name": "visitor_system", "script": VisitorSystem},
	{"name": "parking_system", "script": ParkingSystem},
	{"name": "noise_system", "script": NoiseSystem},
	{"name": "rating_system", "script": RatingSystem},
	{"name": "economy_system", "script": EconomySystem},
	{"name": "tenant_system", "script": TenantSystem, "parent": "map"},
	{"name": "vip_system", "script": VipSystem},
	{"name": "incident_system", "script": IncidentSystem},
	{"name": "weather_system", "script": WeatherSystem},
	{"name": "goal_system", "script": GoalSystem},
	{"name": "tutorial_system", "script": TutorialSystem},
	{"name": "save_system", "script": SaveSystem},
	{"name": "audio_system", "script": AudioSystem},
	{"name": "lighting", "script": Lighting, "parent": "map"},
	{"name": "grid_overlay", "script": GridOverlay, "parent": "map"},
	{"name": "cinema_screen", "script": CinemaScreen, "parent": "map"},
	{"name": "sky_events", "script": SkyEvents, "parent": "map"},
	{"name": "effects", "script": Effects, "parent": "map"},
	{"name": "ui", "script": Ui},
]

func _ready() -> void:
	# 建物の表とルールを先に作ってから、ドット絵のタイルとグリッド情報を用意する
	create_part(PARTS[0])
	apply_pixel_art_tiles()
	apply_tile_types()
	load_grid_from_tilemap()
	for part in PARTS.slice(1):
		create_part(part)
	tile_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # 拡大してもタイルをぼかさない
	clock.set_process(false) # タイトル画面の間は時間を止めておく
	focus_camera_on_building()
	ui.build()
	update_funds_display()

# 部品を1つ作って、main から使えるようにする
func create_part(part: Dictionary) -> void:
	var node = part.script.new()
	set(part.name, node)
	# 先に木に入れてから setup する（setup の中で子ノードを作る部品があるため）
	if part.get("parent", "") == "map":
		tile_map.add_child(node)
	else:
		add_child(node)
	if node.has_method("setup"):
		node.setup(self)
	if part.get("rebuild", false):
		node.rebuild()

func _process(_delta: float) -> void:
	grid_overlay.update_hover()
	ui.update()

func _notification(what: int) -> void:
	# マウスがウィンドウの外に出たらマスの強調表示を消す
	if what == NOTIFICATION_WM_MOUSE_EXIT and grid_overlay:
		grid_overlay.hover_enabled = false

# 建物全体が画面中央に来るようにカメラを合わせる
func focus_camera_on_building():
	var used: Rect2i = tile_map.get_used_rect()
	if used.size == Vector2i.ZERO:
		# 更地: 地面の線が画面の下寄りに来るように、1階の少し上を中央にする
		camera.focus_on(tile_map.to_global(Vector2(0, (ground_y - 1) * tile_map.tile_set.tile_size.y)))
		return
	var center_local = (tile_map.map_to_local(used.position) + tile_map.map_to_local(used.end - Vector2i.ONE)) / 2.0
	camera.focus_on(tile_map.to_global(center_local))

# ---------------------------------------------------
# 画面（UI）: 組み立てと毎フレームの更新は scripts/view/ui.gd が受け持つ。
# ここには、ほかのファイルから呼ばれる入り口だけを置く。
# ---------------------------------------------------

func select_mode(mode: String):
	current_mode = mode
	if mode != MODE_RESIDENT:
		select_resident(null)
	ui.update_mode_select()

func get_mode_label(mode: String) -> String:
	return ui.get_mode_label(mode)

func get_mode_info(mode: String) -> String:
	return ui.get_mode_info(mode)

func update_funds_display():
	ui.update_funds_display()

# 金額を3桁ごとのカンマ区切りにする（signed が true なら、プラスでも符号を付ける）
# 金額を単位つきで書く（例: 12,000Cr / 符号つきなら +12,000Cr）
func money_text(amount: int, signed := false) -> String:
	return format_money(amount, signed) + CURRENCY

# 金額を3桁ごとのカンマ区切りで書く（単位は付けない）
func format_money(amount: int, signed := false) -> String:
	var text := str(absi(amount))
	var out := ""
	for i in text.length():
		if i > 0 and (text.length() - i) % 3 == 0:
			out += ","
		out += text[i]
	if amount < 0:
		return "-" + out
	return ("+" if signed else "") + out

# 画面とログにメッセージを出す
func show_message(text: String):
	last_message = text
	if text == "": # 表示を消すだけ（記録には残さない）
		ui.clear_message()
		return
	message_log.append("%d日目 %02d:%02d  %s" % [clock.day, clock.minute_of_day() / 60, clock.minute_of_day() % 60, text] if clock else text)
	if message_log.size() > MESSAGE_LOG_MAX:
		message_log.remove_at(0)
	ui.show_messages(message_log)
	print(text)

# 目標の達成などを画面で知らせる
func show_goal_panel(title: String, text: String) -> void:
	ui.show_goal_panel(title, text)

# ゲームを始める（タイトル画面を閉じて、時計を動かす）
func start_game() -> void:
	started = true
	ui.hide_title()
	clock.set_process(true)

# ---------------------------------------------------
# グリッド情報の管理
# ---------------------------------------------------

# 建物のタイルをドット絵（pixel_art.gd）にする。
# TileSetにソースがなければ作り、あれば画像を差し替える（エディタで置いたオフィス・階段も含む）
func apply_pixel_art_tiles():
	var tile_set: TileSet = tile_map.tile_set
	for type in BUILDINGS:
		var id: int = BUILDINGS[type].source_id
		if tile_set.has_source(id):
			# 1枚の画像を複数タイルに分けているソースは、同じ並びでドット絵を敷き詰めた画像に差し替える
			var source := tile_set.get_source(id) as TileSetAtlasSource
			var grid: Vector2i = source.get_atlas_grid_size()
			source.texture = ImageTexture.create_from_image(PixelArt.make_atlas_image(type, grid.x, grid.y))
		else:
			# 複数マスの建物は、絵の区画ごとにタイルを作る（横 i 番目・上から j 番目の区画がタイル (i, j)）
			var source := TileSetAtlasSource.new()
			source.texture = ImageTexture.create_from_image(PixelArt.make_tile_image(type))
			source.texture_region_size = tile_set.tile_size
			for j in get_height(type):
				for i in get_width(type):
					source.create_tile(Vector2i(i, j))
			tile_set.add_source(source, id)
		assert(PixelArt.tile_width(type) == get_width(type), "%s のドット絵の横幅が BUILDINGS の width と違います" % type)
		assert(PixelArt.tile_height(type) == get_height(type), "%s のドット絵の高さが BUILDINGS の height と違います" % type)

# BUILDINGSの定義をもとに、TileSetのカスタムデータ「type」を設定する
# （メモリ上のみ。.tscnには保存されないため、エディタ上では空のまま見える）
func apply_tile_types():
	var tile_set: TileSet = tile_map.tile_set
	for type in BUILDINGS:
		var source := tile_set.get_source(BUILDINGS[type].source_id) as TileSetAtlasSource
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			source.get_tile_data(coords, 0).set_custom_data("type", type)

# エディタで事前に置いたタイルをグリッド情報に取り込む
# 同じ行で左右につながった同じ種類のマスを、左から建物の横幅ずつユニットにまとめる
func load_grid_from_tilemap():
	building_grid.clear()
	var cells: Array[Vector2i] = []
	for cell in tile_map.get_used_cells():
		if BUILDINGS.has(get_type_from_tile(cell)):
			cells.append(cell)
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell in cells:
		var type := get_type_from_tile(cell)
		var left := cell + Vector2i.LEFT
		var origin := cell
		# 左隣が同じ種類で、そのユニットにまだ空きがあれば、同じユニットに入れる
		if building_grid.has(left) and building_grid[left].type == type:
			var left_origin: Vector2i = building_grid[left].origin
			if cell.x - left_origin.x < get_width(type):
				origin = left_origin
		building_grid[cell] = {"type": type, "origin": origin}
		# ユニットの何マス目かに合わせて、ドット絵の区画を置き直す
		tile_map.set_cell(cell, BUILDINGS[type].source_id, Vector2i(cell.x - origin.x, 0))

# タイルのカスタムデータ「type」から建物の種類を取得する（空マスなら ""）
func get_type_from_tile(cell: Vector2i) -> String:
	var tile_data: TileData = tile_map.get_cell_tile_data(cell)
	if tile_data == null:
		return ""
	return tile_data.get_custom_data("type")

# 指定マスの建物の種類を返す（空マスなら ""）
func get_building_type(cell: Vector2i) -> String:
	if building_grid.has(cell):
		return building_grid[cell].type
	return ""

func is_cell_empty(cell: Vector2i) -> bool:
	return not building_grid.has(cell)

# 建物の大きさとルール（中身は buildings.gd）
func get_width(type: String) -> int:
	return buildings.get_width(type)

func get_height(type: String) -> int:
	return buildings.get_height(type)

func is_lobby_type(type: String) -> bool:
	return buildings.is_lobby_type(type)

func get_footprint(origin: Vector2i, type: String) -> Array[Vector2i]:
	return buildings.get_footprint(origin, type)

func get_build_problem(origin: Vector2i, type: String) -> String:
	return buildings.get_build_problem(origin, type)

func get_support_problem(origin: Vector2i, type: String) -> String:
	return buildings.get_support_problem(origin, type)

func get_demolish_problem(cell: Vector2i) -> String:
	return buildings.get_demolish_problem(cell)

func get_size_limit_problem(origin: Vector2i, type: String) -> String:
	return buildings.get_size_limit_problem(origin, type)

# 何階か（1階は地面の線のすぐ上の段。地下は B1階・B2階…）
func get_floor_name(y: int) -> String:
	if y > ground_y:
		return "B%d階" % (y - ground_y)
	return "%d階" % (ground_y - y + 1)

# スカイロビーを建てられる階か（15階・30階・45階…）
func is_express_stop_floor(y: int) -> bool:
	return y == ground_y or is_sky_lobby_floor(y)

func is_sky_lobby_floor(y: int) -> bool:
	var floor_number := ground_y - y + 1
	return floor_number > 1 and floor_number % SKY_LOBBY_INTERVAL == 0

# 人が歩けるマスか（建物があって、その建物の一番下の階＝床のある階）
# 吹き抜けロビーの上の部分のように、床のない上の階のマスには入れない
func is_walkable(cell: Vector2i) -> bool:
	return building_grid.has(cell) and building_grid[cell].origin.y == cell.y

# 指定マスを含む建物（ユニット）の全マス
func get_unit_cells(cell: Vector2i) -> Array[Vector2i]:
	if not building_grid.has(cell):
		return []
	return get_footprint(building_grid[cell].origin, building_grid[cell].type)

# 指定した種類の建物の左端のマス（= 建物1つにつき1マス）をすべて返す
func find_units_of_type(type: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in building_grid:
		if building_grid[cell].type == type and building_grid[cell].origin == cell:
			result.append(cell)
	return result

# オフィス（小・普通・大）の左端のマスをすべて返す
func find_office_units() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for type in OFFICE_TYPES:
		result.append_array(find_units_of_type(type))
	return result

# オフィス（小・普通・大）のマスをすべて返す（1マスにつき社員1人）
func find_office_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for type in OFFICE_TYPES:
		result.append_array(find_cells_of_type(type))
	return result

# 指定した種類の建物がある座標をすべて返す（住人AIの目的地探索用）
func find_cells_of_type(type: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in building_grid:
		if building_grid[cell].type == type:
			result.append(cell)
	return result

# ---------------------------------------------------
# 移動ルールと経路探索（中身は scripts/systems/pathfinding.gd）
# ---------------------------------------------------

func get_moves(cell: Vector2i, staff := false, vip := false) -> Array:
	return pathfinding.get_moves(cell, staff, vip)

func can_move(from: Vector2i, to: Vector2i, staff := false, vip := false) -> bool:
	return pathfinding.can_move(from, to, staff, vip)

func find_path(from: Vector2i, to: Vector2i, staff := false, vip := false) -> Array[Vector2i]:
	return pathfinding.find_path(from, to, staff, vip)

func is_escalator_foot(cell: Vector2i) -> bool:
	return pathfinding.is_escalator_foot(cell)

func is_escalator_ride(from: Vector2i, to: Vector2i) -> bool:
	return pathfinding.is_escalator_ride(from, to)

func is_elevator_ride(from: Vector2i, to: Vector2i) -> bool:
	return pathfinding.is_elevator_ride(from, to)

# 今のモードでそのマスを左クリックしたときに操作が成立するか（強調表示の色分けに使う）
func can_click_cell(cell: Vector2i) -> bool:
	if current_mode == MODE_RESIDENT:
		return not is_cell_empty(cell)
	if current_mode == MODE_ADD_CAR:
		return elevator_system.get_add_car_problem(cell) == ""
	if current_mode == MODE_SET_HOME or current_mode == MODE_SERVICE:
		return elevator_system.is_shaft_type(get_building_type(cell))
	if current_mode == MODE_VIP_ONLY:
		return elevator_system.is_shaft_type(get_building_type(cell)) and get_building_type(cell) != "service_elevator"
	if current_mode == MODE_RENT:
		return OFFICE_TYPES.has(get_building_type(cell))
	if current_mode == MODE_DEMOLISH:
		# 支えているマスも「空きフロアを残して撤去」ができる（跡地そのものは支えている間は撤去できない）。
		# 撤去費用が足りないときは撤去できない
		return not is_cell_empty(cell) \
			and (get_building_type(cell) != Buildings.FRAME_TYPE or get_demolish_problem(cell) == "") \
			and funds >= demolish_fee(get_building_type(cell))
	if elevator_system.is_shaft_type(current_mode) and get_building_type(cell) == current_mode:
		return elevator_system.get_car_at(cell) != null and elevator_system.get_car_at(cell).is_stop_floor(cell.y) # シャフトをクリックするとカゴを呼べる
	return get_build_problem(cell, current_mode) == ""

# カーソル下で強調表示するマス（建設モードなら、建てたときに使うマス全部）
func get_hover_footprint(cell: Vector2i) -> Array[Vector2i]:
	if current_mode == MODE_RESIDENT or current_mode == MODE_ADD_CAR or current_mode == MODE_SET_HOME \
			or current_mode == MODE_SERVICE or current_mode == MODE_VIP_ONLY or current_mode == MODE_RENT or current_mode == MODE_DEMOLISH \
			or elevator_system.is_shaft_type(get_building_type(cell)):
		return [cell]
	return get_footprint(cell, current_mode)

# ---------------------------------------------------
# 住人の管理
# ---------------------------------------------------

# ストレスの回復の速さ（メディカルセンターがあるほど速い。1.0が標準）
func stress_recover_rate() -> float:
	var medical := find_units_of_type("medical").size()
	var garden := find_units_of_type("garden").size()
	return minf(1.0 + MEDICAL_RECOVER_BONUS * medical + GARDEN_RECOVER_BONUS * garden, MEDICAL_RECOVER_MAX)

func spawn_resident(cell: Vector2i):
	var resident = Resident.new()
	resident.setup(self, cell)
	tile_map.add_child(resident)
	residents = residents.filter(is_instance_valid) # 退場した住人を除く
	residents.append(resident)
	return resident

# 1階の左の出入り口のマス：1階メインロビーの左端（ロビーがなければnull）
func get_entrance():
	var ground := get_ground_entrances()
	return ground[0] if not ground.is_empty() else null

# 1階の右の出入り口のマス：1階メインロビーの右端（ロビーがなければnull。1マスだけなら左と同じ）
func get_right_entrance():
	var ground := get_ground_entrances()
	return ground[-1] if not ground.is_empty() else null

# 1階の出入り口（ロビーの左端と右端。ロビーが1マスだけなら1つ）
func get_ground_entrances() -> Array[Vector2i]:
	var left = null
	var right = null
	for cell: Vector2i in building_grid:
		if cell.y == ground_y and is_lobby_type(building_grid[cell].type):
			if left == null or cell.x < left.x:
				left = cell
			if right == null or cell.x > right.x:
				right = cell
	var result: Array[Vector2i] = []
	if left != null:
		result.append(left)
		if right != left:
			result.append(right)
	return result

# 入口の一覧。人はビルの外からここに現れ、ここから帰る（一番近い入口を使う）
#   1階の左右の出入り口・地下鉄駅（左端のマス）・地下駐車場（車で下りてこられるもの。左端のマス）の4種類
func get_entrances() -> Array[Vector2i]:
	var entrances: Array[Vector2i] = get_ground_entrances()
	entrances.append_array(find_units_of_type("subway"))
	entrances.append_array(parking_system.usable_units)
	return entrances

func is_entrance(cell: Vector2i) -> bool:
	return get_entrances().has(cell)

# 指定マスから一番近い（経路が一番短い）入口。たどり着ける入口がなければnull
# 経路は行きも帰りも同じなので、ビルに来るときにも帰るときにも使える
func nearest_entrance(cell: Vector2i):
	var best = null
	var best_length := 0
	for entrance in get_entrances():
		var path := find_path(cell, entrance)
		if not path.is_empty() and (best == null or path.size() < best_length):
			best = entrance
			best_length = path.size()
	return best

# 指定マスにいる住人（乗車中の住人は除く。いなければnull）
func get_resident_at(cell: Vector2i):
	for resident in residents:
		if is_instance_valid(resident) and resident.cell == cell and resident.state != resident.State.RIDING:
			return resident
	return null

func select_resident(resident):
	if is_instance_valid(selected_resident):
		selected_resident.selected = false
	selected_resident = resident
	if resident:
		resident.selected = true

# 住人モードでのクリック処理
# 1回目: 住人を配置 / 2回目: その住人の行き先を指定
func handle_resident_click(cell: Vector2i):
	if is_cell_empty(cell):
		show_message("建物のあるマスをクリックしてください")
		return

	if not is_instance_valid(selected_resident):
		select_resident(spawn_resident(cell))
		show_message("住人を配置しました。行き先のマスをクリックしてください")
		return

	if selected_resident.go_to(cell):
		show_message("住人が %s へ移動を始めました（%dマス）" % [cell, selected_resident.path.size()])
		select_resident(null)
	else:
		show_message("そこへの経路がありません（上の階へ行くには階段が必要です）")

# ---------------------------------------------------
# クリックして建設・撤去するロジック
# ---------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and handle_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if not started:
		return # タイトル画面の間は、マップの操作を受け付けない
	# UIの上以外でマウスが動いたら、カーソル下のマスの強調表示を更新する
	if event is InputEventMouseMotion:
		grid_overlay.hover_screen_pos = event.position
		grid_overlay.hover_enabled = true
		# ボタンを押したままなぞると、続けて建てる（右ボタンなら続けて撤去する）
		if drag_button != 0:
			var drag_cell: Vector2i = tile_map.local_to_map(tile_map.make_input_local(event).position)
			if drag_cell != drag_last_cell:
				drag_last_cell = drag_cell
				click_cell(drag_cell, drag_button)
		return
	if event is InputEventMouseButton and not event.pressed:
		drag_button = 0 # ボタンを離したら、なぞるのは終わり
		return
	if not (event is InputEventMouseButton and event.pressed):
		return

	# イベントに含まれるクリック位置をタイルマップの座標系に変換する
	var local_event = tile_map.make_input_local(event)
	var map_pos: Vector2i = tile_map.local_to_map(local_event.position)
	if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
		drag_button = event.button_index # 押したままなぞれば続けて建てられる
		drag_last_cell = map_pos
		click_cell(map_pos, event.button_index)

# マップのマスをクリック（またはドラッグでなぞった）ときの処理
func click_cell(map_pos: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		demolish_at(map_pos)
		return
	if current_mode == MODE_RESIDENT:
		handle_resident_click(map_pos)
	elif current_mode == MODE_ADD_CAR:
		add_elevator_car(map_pos)
	elif current_mode == MODE_SET_HOME:
		show_message(elevator_system.set_home(map_pos))
	elif current_mode == MODE_SERVICE:
		show_message(elevator_system.cycle_service(map_pos))
	elif current_mode == MODE_VIP_ONLY:
		show_message(elevator_system.toggle_vip_only(map_pos))
	elif current_mode == MODE_RENT:
		show_message(tenant_system.cycle_rent(map_pos))
	elif current_mode == MODE_DEMOLISH:
		demolish_at(map_pos)
	elif elevator_system.is_shaft_type(current_mode) and get_building_type(map_pos) == current_mode:
		call_elevator(map_pos)
	else:
		build_at(map_pos)

# ショートカット。受け付けたら true
#   F1 / H: 操作説明の開閉 / M: 音のオン・オフ / R: 経路の表示 / Esc: 開いているパネルを閉じる
#   ⌘L: メッセージの記録の開閉 / ⌘G: 収支のグラフの開閉
#   ⌘+ / ⌘-: ゲーム画面の拡大・縮小 / ⌘0: 拡大率をもとに戻す
#   ⌘S: セーブ / ⌘O: セーブデータの読み込み
# ヘルプと音を⌘と組み合わせないのは、macOSの⌘H（隠す）・⌘M（しまう）とぶつかるため。
# このゲームは文字を打つところがないので、単体のキーで受けてよい。
func handle_shortcut(event: InputEventKey) -> bool:
	if not (event.meta_pressed or event.ctrl_pressed):
		match event.keycode:
			KEY_F1, KEY_H:
				help_panel.visible = not help_panel.visible
			KEY_M:
				audio_system.toggle_mute()
			KEY_R:
				toggle_routes()
			KEY_ESCAPE:
				return close_panels()
			_:
				return false
		return true
	match event.keycode:
		KEY_G:
			chart_panel.visible = not chart_panel.visible
		KEY_S:
			save_system.save_game()
		KEY_O:
			save_system.load_game()
		KEY_L:
			log_panel.visible = not log_panel.visible
			if log_panel.visible:
				ui.update_log_panel()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			camera.zoom_by(camera.KEY_ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			camera.zoom_by(1.0 / camera.KEY_ZOOM_STEP)
		KEY_0, KEY_KP_0:
			camera.reset_zoom()
		_:
			return false
	return true

# Esc: 開いているパネルを閉じる。1つでも閉じたら true（何も開いていなければ false）
func close_panels() -> bool:
	var closed := false
	for panel in [help_panel, log_panel, chart_panel, stats_panel]:
		if panel.visible:
			panel.visible = false
			closed = true
	return closed

# 経路（人の通り道）の表示を切り替える。見た目だけの機能で、経路探索や移動には触らない
func toggle_routes() -> void:
	show_routes = not show_routes
	ui.update_route_button()
	show_message("経路の表示を%sにしました（Rキーで切り替え）" % ("オン" if show_routes else "オフ"))

# ゲームの速度を変える（ボタンの表示も合わせる）
func set_speed(speed: int) -> void:
	Engine.time_scale = speed
	if speed_button:
		speed_button.text = "%dx" % speed

# カゴ追加モードでシャフトのマスをクリックしたとき、その階にカゴを1台追加する
func add_elevator_car(cell: Vector2i):
	var problem: String = elevator_system.get_add_car_problem(cell)
	if problem != "":
		show_message(problem)
		return
	elevator_system.add_car(cell)
	update_funds_display()
	show_message("エレベーターにカゴを追加しました %s（このシャフトは%d台）" % [cell, elevator_system.get_cars_at(cell).size()])

# シャフトのマスをクリックしたとき、その階にカゴを呼ぶ
func call_elevator(cell: Vector2i):
	if elevator_system.call_car(cell):
		show_message("エレベーターを %s に呼びました" % cell)
	elif get_building_type(cell) == "express_elevator":
		show_message("急行エレベーターは1階とスカイロビーの階にしか停まりません")

# 建物が増減したときに、建物に対応する仕組み（エレベーター・社員・客室・住宅・会場）を更新する
func rebuild_systems():
	tenant_system.remove_lost_records()
	elevator_system.rebuild()
	incident_system.rebuild()
	noise_system.rebuild()
	parking_system.rebuild()
	commute_system.rebuild()
	hotel_system.rebuild()
	housing_system.rebuild()
	event_system.rebuild()

# 建設処理（クリックしたマスを左端として、建物の横幅ぶんのマスに建てる）
func build_at(map_pos: Vector2i):
	if not buildings.is_buildable_cell(map_pos): # 何もないマスか、撤去の跡地にだけ建てられる
		return
	var problem := get_build_problem(map_pos, current_mode)
	if problem != "":
		show_message(problem)
		audio_system.play("error")
		return
	
	funds -= BUILDINGS[current_mode].cost
	place_unit(map_pos, current_mode)
	rebuild_systems()
	update_funds_display()
	audio_system.play("build")
	effects.play_build(get_footprint(map_pos, current_mode))
	show_message("%sを建設しました %s" % [BUILDINGS[current_mode].name, map_pos])
	incident_system.on_built(get_footprint(map_pos, current_mode)) # 地下なら埋蔵金が見つかることがある

# 建物をマップに置く（費用やルールは見ない。建設とセーブの読み込みで使う）
func place_unit(origin: Vector2i, type: String) -> void:
	var data = BUILDINGS[type]
	var height := get_height(type)
	for cell in get_footprint(origin, type):
		# ドット絵の区画: 横は左端からの位置、縦は上から数えた位置（一番下の階が一番下の区画）
		var atlas := Vector2i(cell.x - origin.x, height - 1 - (origin.y - cell.y))
		tile_map.set_cell(cell, data.source_id, atlas)
		building_grid[cell] = {"type": type, "origin": origin}

# 建物と住人をすべて消す（セーブの読み込みで使う）
func clear_world() -> void:
	for cell in building_grid.keys():
		tile_map.erase_cell(cell)
	building_grid.clear()
	for resident in residents:
		if is_instance_valid(resident):
			resident.queue_free()
	residents.clear()
	effects.clear() # 消えた建物の演出が残らないようにする
	rebuild_systems()

# 建物を壊す（爆発・火災）。部屋のあったマスには、黒焦げの焼け跡が残る。
# 焼け跡は上の階を支えたままだが、その上には建てられないので、建て直すには先に撤去する
func destroy_unit(cell: Vector2i) -> void:
	if is_cell_empty(cell):
		return
	effects.play_demolish(get_unit_cells(cell))
	for c in get_unit_cells(cell):
		tile_map.erase_cell(c)
		building_grid.erase(c)
		place_unit(c, Buildings.RUIN_TYPE)
	rebuild_systems()

# その建物を撤去するのにかかる費用（建設費の1割。ただし最低 MIN_DEMOLISH_FEE）
func demolish_fee(type: String) -> int:
	return maxi(int(BUILDINGS[type].cost * DEMOLISH_RATE), MIN_DEMOLISH_FEE)

# 撤去（ブルドーザー）。建物のどのマスをクリックしても、その建物全体を撤去する。撤去費用がかかる
func demolish_at(map_pos: Vector2i):
	if is_cell_empty(map_pos):
		return
	
	var type = get_building_type(map_pos)
	# 上（地下なら下）の階にまだ建物が残っているマスは、建物の代わりに「空きフロア」を残して
	# 撤去する（そうしないと、上の部屋が空中に浮いてしまう）。
	# 跡地そのものを撤去しようとしたときだけは、真上を支えているなら断る
	var problem := get_demolish_problem(map_pos)
	if problem != "" and type == Buildings.FRAME_TYPE:
		show_message(problem)
		audio_system.play("error")
		return
	# 撤去にはお金がかかる（建設費は戻らない）。足りなければ撤去できない
	var fee := demolish_fee(type)
	if funds < fee:
		show_message("撤去費用が足りません（%sの撤去には %sかかります）" % [BUILDINGS[type].name, money_text(fee)])
		audio_system.play("error")
		return
	var leave_frame: bool = type != Buildings.FRAME_TYPE and buildings.has_building_beyond(map_pos)
	var origin: Vector2i = building_grid[map_pos].origin
	
	funds -= fee
	effects.play_demolish(get_unit_cells(map_pos))
	for cell in get_unit_cells(map_pos):
		tile_map.erase_cell(cell)
		building_grid.erase(cell)
		if leave_frame:
			place_unit(cell, Buildings.FRAME_TYPE)
	rebuild_systems()
	update_funds_display()
	audio_system.play("demolish")
	var note := "（上の階が残っているので、空きフロアになります）" if leave_frame else ""
	show_message("%sを撤去しました %s 撤去費用: %s%s" % [BUILDINGS[type].name, origin, money_text(fee), note])

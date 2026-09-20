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
const TenantSystem := preload("res://scripts/systems/tenant_system.gd")

@onready var tile_map = $TileMapLayer
@onready var camera = $Camera2D

# ---------------------------------------------------
# 建物の定義（種類を増やすときはここに追記する）
# 見た目は pixel_art.gd のドット絵（TILES に同じ名前で描く）
# width: 横のマス数（省略時は1）。建設・撤去はこのまとまり（ユニット）ごとに行い、cost はユニット1つ分
# height: 縦の階数（省略時は1）。左下のマスを基準に、上の階へ伸びる。人が歩けるのは一番下の階だけ
# lobby: true ならロビー（1階の入口になる）
# floors: 建てられる階。"ground" = 1階だけ / "basement" = 地下だけ / "any" = どこでも /
#         "sky_lobby" = 15階・30階・45階…だけ（SKY_LOBBY_INTERVAL 階ごと） /
#         "basement1" = 地下1階だけ（1階から車で下りられる深さ） /
#         "deep_basement" = 地下SUBWAY_MIN_DEPTH階より深いところだけ（地下鉄駅） /
#         "rooftop" = 屋上（地上で、上に建物がないマス）だけ / 省略 = 1階以外
#         （1階はロビー専用のフロアなので、テナントや設備は1階に建てられない）
# ---------------------------------------------------
const BUILDINGS := {
	"office": {"name": "オフィス", "cost": 400000, "source_id": 0, "width": 4},
	"stairs": {"name": "階段", "cost": 50000, "source_id": 1, "floors": "any"},
	"elevator": {"name": "エレベーター", "cost": 80000, "source_id": 2, "floors": "any"},
	"hotel": {"name": "シングル", "cost": 150000, "source_id": 3, "width": 2},
	"hotel_twin": {"name": "ツイン", "cost": 200000, "source_id": 10, "width": 3},
	"hotel_suite": {"name": "スイート", "cost": 500000, "source_id": 11, "width": 4},
	"housekeeping": {"name": "ハウスキーパー室", "cost": 200000, "source_id": 4, "width": 2},
	"restaurant": {"name": "飲食店", "cost": 200000, "source_id": 5, "width": 3},
	"shop": {"name": "ショップ", "cost": 250000, "source_id": 24, "width": 3},
	"cinema": {"name": "映画館", "cost": 1500000, "source_id": 25, "width": 8, "height": 2},
	"recycling": {"name": "ゴミ処理場", "cost": 150000, "source_id": 6, "width": 3},
	"security": {"name": "警備室", "cost": 100000, "source_id": 7, "width": 2},
	"medical": {"name": "メディカルセンター", "cost": 200000, "source_id": 8, "width": 3},
	"housing": {"name": "住宅", "cost": 400000, "source_id": 9, "width": 3},
	"wedding": {"name": "結婚式場", "cost": 1000000, "source_id": 12, "width": 6},
	"event_hall": {"name": "イベントホール", "cost": 800000, "source_id": 13, "width": 6},
	"subway": {"name": "地下鉄駅", "cost": 1000000, "source_id": 14, "width": 4, "floors": "deep_basement"},
	"helipad": {"name": "ヘリポート", "cost": 800000, "source_id": 26, "width": 4, "floors": "rooftop"},
	"parking": {"name": "地下駐車場", "cost": 300000, "source_id": 22, "width": 4, "floors": "basement"},
	"ramp": {"name": "スロープ", "cost": 200000, "source_id": 23, "width": 2, "floors": "basement1"},
	"lobby": {"name": "ロビー", "cost": 15000, "source_id": 15, "floors": "ground", "lobby": true},
	"lobby2": {"name": "吹き抜けロビー（2階分）", "cost": 30000, "source_id": 16, "floors": "ground", "height": 2, "lobby": true},
	"lobby3": {"name": "吹き抜けロビー（3階分）", "cost": 45000, "source_id": 17, "floors": "ground", "height": 3, "lobby": true},
	"sky_lobby": {"name": "スカイロビー", "cost": 50000, "source_id": 18, "floors": "sky_lobby"},
	"express_elevator": {"name": "急行エレベーター", "cost": 120000, "source_id": 19, "floors": "any"},
	"escalator": {"name": "エスカレーター", "cost": 100000, "source_id": 20, "width": 2, "floors": "any"},
	"service_elevator": {"name": "サービスエレベーター", "cost": 80000, "source_id": 21, "floors": "any"},
}
const REFUND_RATE := 0.5 # 撤去時の払い戻し率
const MODE_RESIDENT := "resident" # 住人を配置・移動させるモード
const MODE_ADD_CAR := "add_car"   # エレベーターのシャフトにカゴを追加するモード
const MODE_SET_HOME := "set_home" # エレベーターの待機階（呼び出しがないとカゴが戻る階）を決めるモード
const MODE_SERVICE := "service"   # エレベーターの稼働時間帯を切り替えるモード
const MODE_DEMOLISH := "demolish" # 左クリックで撤去するモード（右クリックでも撤去できる）

# 建設メニューの並び（見出しごとにまとめる）。BUILDINGS に建物を足したら、ここにも入れる
const MODE_GROUPS := [
	{"name": "テナント", "modes": ["office", "hotel", "hotel_twin", "hotel_suite", "restaurant", "shop", "cinema", "housing", "wedding", "event_hall"]},
	{"name": "ロビー・移動", "modes": ["lobby", "lobby2", "lobby3", "sky_lobby", "stairs", "escalator", "elevator", "express_elevator", "service_elevator", "add_car", "set_home", "service"]},
	{"name": "設備", "modes": ["housekeeping", "recycling", "security", "medical", "subway", "ramp", "parking", "helipad"]},
	{"name": "その他", "modes": ["demolish", "resident"]},
]
const SKY_LOBBY_INTERVAL := 15 # スカイロビーを建てられる階の間隔（15階・30階・45階…）
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
var speed_button: Button:
	get: return ui.speed_button
var mode_select: OptionButton:
	get: return ui.mode_select
var mode_info_label: Label:
	get: return ui.mode_info_label
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
const MAX_FLOORS_ABOVE := 150 # 建てられる一番上の階（地上150階）
const MAX_FLOORS_BELOW := 50  # 掘れる一番下の階（地下50階）
const MAX_WIDTH := 100        # ビルの横幅（マス数）。0を中心に左右へ半分ずつ
const SUBWAY_MIN_DEPTH := 5   # 地下鉄駅を建てられる深さ（地下5階より下）
const SPEEDS := [1, 4, 16]    # ゲームの速度（押すたびにこの順に切り替わる）
const MEDICAL_RECOVER_BONUS := 0.5 # メディカルセンター1施設で、ストレスの回復が何割速くなるか
const MEDICAL_RECOVER_MAX := 2.5   # 回復の速さの上限（何倍まで）
const MESSAGE_LOG_MAX := 500  # ⌘Lで見られるメッセージの記録の数

var building_grid: Dictionary = {} # マス -> {type, origin}
var residents: Array = []          # 配置済みの住人
var selected_resident = null       # 行き先の指示を待っている住人
var started := false               # ゲームが始まっているか（タイトル画面の間は false）
var drag_button := 0               # 押したままなぞっているマウスのボタン（0なら押していない）
var drag_last_cell := Vector2i.ZERO # なぞっている間に、最後に処理したマス
var message_log: Array[String] = [] # ゲーム開始からのメッセージ（時刻つき）
var last_message := ""             # 一番新しいメッセージ（時刻なし）

# 見た目
var grid_overlay # マス目の表示
var effects      # 建設・撤去・お金の演出
var lighting     # 夜の明かり

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

func _ready() -> void:
	apply_pixel_art_tiles()
	apply_tile_types()
	load_grid_from_tilemap()
	elevator_system = ElevatorSystem.new()
	elevator_system.setup(self)
	add_child(elevator_system)
	elevator_system.rebuild()
	visitor_system = VisitorSystem.new()
	visitor_system.setup(self)
	add_child(visitor_system)
	noise_system = NoiseSystem.new()
	noise_system.setup(self)
	add_child(noise_system)
	vip_system = VipSystem.new()
	vip_system.setup(self)
	add_child(vip_system)
	incident_system = IncidentSystem.new()
	incident_system.setup(self)
	add_child(incident_system)
	weather_system = WeatherSystem.new()
	weather_system.setup(self)
	add_child(weather_system)
	save_system = SaveSystem.new()
	save_system.setup(self)
	add_child(save_system)
	audio_system = AudioSystem.new()
	add_child(audio_system)
	audio_system.setup(self)
	goal_system = GoalSystem.new()
	goal_system.setup(self)
	add_child(goal_system)
	tutorial_system = TutorialSystem.new()
	tutorial_system.setup(self)
	add_child(tutorial_system)
	parking_system = ParkingSystem.new()
	parking_system.setup(self)
	add_child(parking_system)
	clock = GameClock.new()
	add_child(clock)
	clock.set_process(false) # タイトル画面の間は時間を止めておく（木に入れた後で止める）
	commute_system = CommuteSystem.new()
	commute_system.setup(self)
	add_child(commute_system)
	commute_system.rebuild()
	hotel_system = HotelSystem.new()
	hotel_system.setup(self)
	tile_map.add_child(hotel_system)
	hotel_system.rebuild()
	commerce_system = CommerceSystem.new()
	commerce_system.setup(self)
	add_child(commerce_system)
	housing_system = HousingSystem.new()
	housing_system.setup(self)
	add_child(housing_system)
	housing_system.rebuild()
	event_system = EventSystem.new()
	event_system.setup(self)
	add_child(event_system)
	event_system.rebuild()
	rating_system = RatingSystem.new()
	rating_system.setup(self)
	add_child(rating_system)
	economy_system = EconomySystem.new()
	economy_system.setup(self)
	add_child(economy_system)
	lighting = Lighting.new()
	lighting.setup(self)
	tile_map.add_child(lighting)
	tenant_system = TenantSystem.new()
	tenant_system.setup(self)
	tile_map.add_child(tenant_system)
	tile_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # 拡大してもタイルをぼかさない
	focus_camera_on_building()
	grid_overlay = GridOverlay.new()
	grid_overlay.setup(self)
	tile_map.add_child(grid_overlay)
	effects = Effects.new()
	effects.setup(self)
	tile_map.add_child(effects)
	ui = Ui.new()
	ui.setup(self)
	add_child(ui)
	ui.build()
	update_funds_display()

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

# 建物の横幅（マス数）
func get_width(type: String) -> int:
	return BUILDINGS[type].get("width", 1)

# 建物の高さ（階数）
func get_height(type: String) -> int:
	return BUILDINGS[type].get("height", 1)

func is_lobby_type(type: String) -> bool:
	return BUILDINGS.has(type) and BUILDINGS[type].get("lobby", false)

# 左下のマス origin から建物を建てたときに使うマスの一覧（横幅 × 高さ。上の階は y が小さい）
func get_footprint(origin: Vector2i, type: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for k in get_height(type):
		for i in get_width(type):
			cells.append(origin + Vector2i(i, -k))
	return cells

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

# 左端 origin に type の建物を建てられない理由（建てられるなら ""）
func get_build_problem(origin: Vector2i, type: String) -> String:
	for cell in get_footprint(origin, type):
		if not is_cell_empty(cell):
			return "ほかの建物と重なるため建てられません"
	var limit := get_size_limit_problem(origin, type)
	if limit != "":
		return limit
	var floors: String = BUILDINGS[type].get("floors", "")
	if floors == "ground" and origin.y != ground_y:
		return "%sは1階にしか建てられません" % BUILDINGS[type].name
	if floors == "basement" and origin.y <= ground_y:
		return "%sは地下（1階より下）にしか建てられません" % BUILDINGS[type].name
	if floors == "rooftop":
		for cell in get_footprint(origin, type):
			if cell.y >= ground_y or not is_cell_empty(cell + Vector2i.UP):
				return "%sは屋上（上に建物がないところ）にしか建てられません" % BUILDINGS[type].name
	for cell in get_footprint(origin, type):
		if get_building_type(cell + Vector2i.DOWN) == "helipad":
			return "ヘリポートの上には建てられません"
	if floors == "deep_basement" and origin.y < ground_y + SUBWAY_MIN_DEPTH:
		return "%sは地下%d階より深いところにしか建てられません（ここは%s）" % [BUILDINGS[type].name, SUBWAY_MIN_DEPTH, get_floor_name(origin.y)]
	if floors == "basement1" and origin.y != ground_y + 1:
		return "%sは地下1階にしか建てられません（1階から車で下りる道なので）" % BUILDINGS[type].name
	if floors == "sky_lobby" and not is_sky_lobby_floor(origin.y):
		return "%sは%d階・%d階・%d階…にしか建てられません（ここは%s）" % [BUILDINGS[type].name,
			SKY_LOBBY_INTERVAL, SKY_LOBBY_INTERVAL * 2, SKY_LOBBY_INTERVAL * 3, get_floor_name(origin.y)]
	if floors == "" and origin.y == ground_y:
		return "1階はロビー専用です（1階に建てられるのはロビー・階段・エレベーターだけ）"
	var support := get_support_problem(origin, type)
	if support != "":
		return support
	if funds < BUILDINGS[type].cost:
		return "資金不足です！"
	return ""

# 建物の支え: 地上の建物は、一番下の階の全部のマスの真下に建物がないと建てられない（空中に浮かせない）。
# 地下の建物は、一番上の階の全部のマスの真上に建物がないと建てられない（上の階から掘り進める）。
# 1階の建物は地面が支えるので、条件なし。支えられているなら "" を返す
func get_support_problem(origin: Vector2i, type: String) -> String:
	if origin.y == ground_y:
		return ""
	for i in get_width(type):
		if origin.y < ground_y and is_cell_empty(origin + Vector2i(i, 1)):
			return "下の階に建物がないと建てられません（建物の下は全部埋まっている必要があります）"
		if origin.y > ground_y and is_cell_empty(origin + Vector2i(i, -get_height(type))):
			return "地下は、上の階に建物がある場所にしか建てられません"
	return ""

# 撤去すると支えを失う建物があるか。地上の建物は真上、地下の建物は真下に、別の建物があると撤去できない
#（撤去できるなら "" を返す）
func get_demolish_problem(cell: Vector2i) -> String:
	var unit := get_unit_cells(cell)
	for c in unit:
		var neighbor: Vector2i = c + (Vector2i.DOWN if c.y > ground_y else Vector2i.UP)
		if not is_cell_empty(neighbor) and not unit.has(neighbor):
			if c.y > ground_y:
				return "下の階の建物を支えているため撤去できません（下の階から撤去してください）"
			return "上の階の建物を支えているため撤去できません（上の階から撤去してください）"
	return ""

# ビルの大きさの上限（地上150階・地下50階・横100マス）を超えていないか。よければ ""
func get_size_limit_problem(origin: Vector2i, type: String) -> String:
	for cell in get_footprint(origin, type):
		if cell.y < ground_y - (MAX_FLOORS_ABOVE - 1):
			return "ビルは地上%d階までです" % MAX_FLOORS_ABOVE
		if cell.y > ground_y + MAX_FLOORS_BELOW:
			return "地下は%d階までです" % MAX_FLOORS_BELOW
		if cell.x < -MAX_WIDTH / 2 or cell.x >= MAX_WIDTH / 2:
			return "ビルの幅は%dマスまでです（マスのx座標は %d〜%d）" % [MAX_WIDTH, -MAX_WIDTH / 2, MAX_WIDTH / 2 - 1]
	return ""

# 指定した種類の建物の左端のマス（= 建物1つにつき1マス）をすべて返す
func find_units_of_type(type: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in building_grid:
		if building_grid[cell].type == type and building_grid[cell].origin == cell:
			result.append(cell)
	return result

# 指定した種類の建物がある座標をすべて返す（住人AIの目的地探索用）
func find_cells_of_type(type: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in building_grid:
		if building_grid[cell].type == type:
			result.append(cell)
	return result

# ---------------------------------------------------
# 移動ルールと経路探索
# ---------------------------------------------------

# 移動の手間（コスト）。経路探索はこの合計が一番小さい経路を選ぶ。
# 1〜2階の移動なら階段、3階以上ならエレベーターの方が得になるよう調整している。
const WALK_COST := 1.0           # 横に1マス歩く
const STAIRS_COST := 2.0         # 階段で1階分上り下りする
const ESCALATOR_COST := 1.0      # エスカレーターで1階分上り下りする（待ち時間がなく、階段より楽）
const ELEVATOR_WAIT_COST := 4.0  # エレベーターに乗る（待ち時間の見込み）
const ELEVATOR_FLOOR_COST := 0.5 # エレベーターで1階分移動する

# 指定マスから1回で移動できる先とそのコストの一覧（住人の移動ルールはすべてここで決まる）
# - 横移動:       隣のマスに建物があれば歩ける（エレベーターの扉の前も通り抜けられる）
# - 階段:         階段マスは、そのマスと1つ上の階をつなぐ
# - エスカレーター: 横2マス。左のマス（乗り口）と、1つ上の階の右のマスの上（降り口）を斜めにつなぐ。
#                   上りも下りも使える。定員も待ち時間もない
# - エレベーター: シャフトのマスから、同じシャフトの別の階へ乗って移動できる
#                 （サービスエレベーターは裏方＝清掃員だけ乗れる。staff で切り替える）
#                 （急行は1階とスカイロビーの階の間だけ。速いので1階分のコストは標準の1/3）
# 戻り値: [{"to": Vector2i, "cost": float}, ...]
func get_moves(cell: Vector2i, staff := false) -> Array:
	var result: Array = []
	if not is_walkable(cell):
		return result
	for dir in [Vector2i.LEFT, Vector2i.RIGHT]:
		if is_walkable(cell + dir):
			result.append({"to": cell + dir, "cost": WALK_COST})
	if get_building_type(cell) == "stairs" and is_walkable(cell + Vector2i.UP):
		result.append({"to": cell + Vector2i.UP, "cost": STAIRS_COST})
	if get_building_type(cell + Vector2i.DOWN) == "stairs":
		result.append({"to": cell + Vector2i.DOWN, "cost": STAIRS_COST})
	if is_escalator_foot(cell) and is_walkable(cell + ESCALATOR_UP):
		result.append({"to": cell + ESCALATOR_UP, "cost": ESCALATOR_COST})
	if is_escalator_foot(cell - ESCALATOR_UP):
		result.append({"to": cell - ESCALATOR_UP, "cost": ESCALATOR_COST})
	if elevator_system.is_shaft_type(get_building_type(cell)) and (staff or get_building_type(cell) != "service_elevator"):
		var car = elevator_system.get_car_at(cell)
		if car and car.in_service and car.is_stop_floor(cell.y):
			var floor_cost: float = ELEVATOR_FLOOR_COST * car.SPEED / car.speed
			for y in range(car.top_y, car.bottom_y + 1):
				if y != cell.y and car.is_stop_floor(y):
					var cost := ELEVATOR_WAIT_COST + floor_cost * absi(y - cell.y)
					result.append({"to": Vector2i(cell.x, y), "cost": cost})
	return result

# fromからtoへ1回で移動できるか
func can_move(from: Vector2i, to: Vector2i, staff := false) -> bool:
	for move in get_moves(from, staff):
		if move.to == to:
			return true
	return false

# エスカレーターの上り口（左下のマス）の、上の階の降り口までのずれ
const ESCALATOR_UP := Vector2i(1, -1)

# エスカレーターの上り口（左のマス）か
func is_escalator_foot(cell: Vector2i) -> bool:
	return get_building_type(cell) == "escalator" and building_grid[cell].origin == cell

# fromからtoへの移動がエスカレーターに乗る移動か
func is_escalator_ride(from: Vector2i, to: Vector2i) -> bool:
	return (to - from == ESCALATOR_UP and is_escalator_foot(from)) or (from - to == ESCALATOR_UP and is_escalator_foot(to))

# fromからtoへの移動がエレベーターに乗る移動か（同じシャフト内の別の階への移動）
func is_elevator_ride(from: Vector2i, to: Vector2i) -> bool:
	return from.x == to.x and from.y != to.y and elevator_system.is_shaft_type(get_building_type(from)) \
		and get_building_type(from) == get_building_type(to)

# ダイクストラ法でコストが最小の経路を求める
# 戻り値: [from, ..., to] のマス配列。経路がなければ空配列。
func find_path(from: Vector2i, to: Vector2i, staff := false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if is_cell_empty(from) or is_cell_empty(to):
		return result
	
	var cost_so_far := {} # マス -> スタートからの最小コスト
	var came_from := {}   # マス -> 1つ前のマス
	cost_so_far[from] = 0.0
	came_from[from] = from
	var open: Array[Vector2i] = [from] # これから調べるマス
	var done := {}                     # 最小コストが確定したマス
	while not open.is_empty():
		# まだ調べていないマスのうち、コストが一番小さいものを取り出す
		var best := 0
		for i in range(1, open.size()):
			if cost_so_far[open[i]] < cost_so_far[open[best]]:
				best = i
		var current: Vector2i = open[best]
		open.remove_at(best)
		if current == to:
			# ゴールからスタートまで逆にたどって経路を組み立てる
			var c := to
			while c != from:
				result.push_front(c)
				c = came_from[c]
			result.push_front(from)
			return result
		done[current] = true
		for move in get_moves(current, staff):
			var next: Vector2i = move.to
			if done.has(next):
				continue
			var new_cost: float = cost_so_far[current] + move.cost
			if not cost_so_far.has(next) or new_cost < cost_so_far[next]:
				cost_so_far[next] = new_cost
				came_from[next] = current
				if not open.has(next):
					open.append(next)
	return result

# 今のモードでそのマスを左クリックしたときに操作が成立するか（強調表示の色分けに使う）
func can_click_cell(cell: Vector2i) -> bool:
	if current_mode == MODE_RESIDENT:
		return not is_cell_empty(cell)
	if current_mode == MODE_ADD_CAR:
		return elevator_system.get_add_car_problem(cell) == ""
	if current_mode == MODE_SET_HOME or current_mode == MODE_SERVICE:
		return elevator_system.is_shaft_type(get_building_type(cell))
	if current_mode == MODE_DEMOLISH:
		return not is_cell_empty(cell) and get_demolish_problem(cell) == ""
	if elevator_system.is_shaft_type(current_mode) and get_building_type(cell) == current_mode:
		return elevator_system.get_car_at(cell) != null and elevator_system.get_car_at(cell).is_stop_floor(cell.y) # シャフトをクリックするとカゴを呼べる
	return get_build_problem(cell, current_mode) == ""

# カーソル下で強調表示するマス（建設モードなら、建てたときに使うマス全部）
func get_hover_footprint(cell: Vector2i) -> Array[Vector2i]:
	if current_mode == MODE_RESIDENT or current_mode == MODE_ADD_CAR or current_mode == MODE_SET_HOME \
			or current_mode == MODE_SERVICE or current_mode == MODE_DEMOLISH \
			or elevator_system.is_shaft_type(get_building_type(cell)):
		return [cell]
	return get_footprint(cell, current_mode)

# ---------------------------------------------------
# 住人の管理
# ---------------------------------------------------

# ストレスの回復の速さ（メディカルセンターがあるほど速い。1.0が標準）
func stress_recover_rate() -> float:
	var medical := find_units_of_type("medical").size()
	return minf(1.0 + MEDICAL_RECOVER_BONUS * medical, MEDICAL_RECOVER_MAX)

func spawn_resident(cell: Vector2i):
	var resident = Resident.new()
	resident.setup(self, cell)
	tile_map.add_child(resident)
	residents = residents.filter(is_instance_valid) # 退場した住人を除く
	residents.append(resident)
	return resident

# 1階の入口のマス：1階メインロビーの左端（ロビーがなければnull）
func get_entrance():
	var entrance = null
	for cell: Vector2i in building_grid:
		if cell.y == ground_y and is_lobby_type(building_grid[cell].type) and (entrance == null or cell.x < entrance.x):
			entrance = cell
	return entrance

# 入口の一覧：1階の入口と、地下鉄駅（左端のマス）。人はビルの外からここに現れ、ここから帰る
func get_entrances() -> Array[Vector2i]:
	var entrances: Array[Vector2i] = []
	var main_entrance = get_entrance()
	if main_entrance != null:
		entrances.append(main_entrance)
	entrances.append_array(find_units_of_type("subway"))
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
	elif current_mode == MODE_DEMOLISH:
		demolish_at(map_pos)
	elif elevator_system.is_shaft_type(current_mode) and get_building_type(map_pos) == current_mode:
		call_elevator(map_pos)
	else:
		build_at(map_pos)

# ⌘（Ctrl）と組み合わせるショートカット。受け付けたら true
#   ⌘H: 操作説明の開閉 / ⌘L: メッセージの記録の開閉
#   ⌘+ / ⌘-: ゲーム画面の拡大・縮小 / ⌘0: 拡大率をもとに戻す
#   ⌘S: セーブ / ⌘O: セーブデータの読み込み / ⌘G: 収支のグラフの開閉 / ⌘M: 音のオン・オフ
func handle_shortcut(event: InputEventKey) -> bool:
	if not (event.meta_pressed or event.ctrl_pressed):
		return false
	match event.keycode:
		KEY_H:
			help_panel.visible = not help_panel.visible
		KEY_M:
			audio_system.toggle_mute()
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
	if not is_cell_empty(map_pos):
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
	rebuild_systems()

# 建物を壊す（爆発・火災など。払い戻しはなく、支えのルールも見ない）
func destroy_unit(cell: Vector2i) -> void:
	if is_cell_empty(cell):
		return
	effects.play_demolish(get_unit_cells(cell))
	for c in get_unit_cells(cell):
		tile_map.erase_cell(c)
		building_grid.erase(c)
	rebuild_systems()

# 撤去（売却）処理（建物のどのマスをクリックしても、その建物全体を撤去する）
func demolish_at(map_pos: Vector2i):
	if is_cell_empty(map_pos):
		return
	
	var problem := get_demolish_problem(map_pos)
	if problem != "":
		show_message(problem)
		audio_system.play("error")
		return
	var type = get_building_type(map_pos)
	var origin: Vector2i = building_grid[map_pos].origin
	var refund = int(BUILDINGS[type].cost * REFUND_RATE)
	
	funds += refund
	effects.play_demolish(get_unit_cells(map_pos))
	for cell in get_unit_cells(map_pos):
		tile_map.erase_cell(cell)
		building_grid.erase(cell)
	rebuild_systems()
	update_funds_display()
	audio_system.play("demolish")
	show_message("%sを撤去しました %s 払い戻し: %d円" % [BUILDINGS[type].name, origin, refund])

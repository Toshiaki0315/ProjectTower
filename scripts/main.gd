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
#         "basement1" = 地下1階だけ（1階から車で下りられる深さ） / 省略 = 1階以外
#         （1階はロビー専用のフロアなので、テナントや設備は1階に建てられない）
# ---------------------------------------------------
const BUILDINGS := {
	"office": {"name": "オフィス", "cost": 400000, "source_id": 0, "width": 4},
	"stairs": {"name": "階段", "cost": 50000, "source_id": 1, "floors": "any"},
	"elevator": {"name": "エレベーター", "cost": 100000, "source_id": 2, "floors": "any"},
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
	"subway": {"name": "地下鉄駅", "cost": 1000000, "source_id": 14, "width": 4, "floors": "basement"},
	"parking": {"name": "地下駐車場", "cost": 300000, "source_id": 22, "width": 4, "floors": "basement"},
	"ramp": {"name": "スロープ", "cost": 200000, "source_id": 23, "width": 2, "floors": "basement1"},
	"lobby": {"name": "ロビー", "cost": 30000, "source_id": 15, "floors": "ground", "lobby": true},
	"lobby2": {"name": "吹き抜けロビー（2階分）", "cost": 60000, "source_id": 16, "floors": "ground", "height": 2, "lobby": true},
	"lobby3": {"name": "吹き抜けロビー（3階分）", "cost": 90000, "source_id": 17, "floors": "ground", "height": 3, "lobby": true},
	"sky_lobby": {"name": "スカイロビー", "cost": 50000, "source_id": 18, "floors": "sky_lobby"},
	"express_elevator": {"name": "急行エレベーター", "cost": 120000, "source_id": 19, "floors": "any"},
	"escalator": {"name": "エスカレーター", "cost": 100000, "source_id": 20, "width": 2, "floors": "any"},
	"service_elevator": {"name": "サービスエレベーター", "cost": 80000, "source_id": 21, "floors": "any"},
}
const UI_SCALE := 2      # 画面表示（文字・ボタン・余白）の大きさの倍率
const BASE_FONT_SIZE := 16 # 倍率をかける前の文字の大きさ
const REFUND_RATE := 0.5 # 撤去時の払い戻し率
const MODE_RESIDENT := "resident" # 住人を配置・移動させるモード
const MODE_ADD_CAR := "add_car"   # エレベーターのシャフトにカゴを追加するモード
const MODE_SET_HOME := "set_home" # エレベーターの待機階（呼び出しがないとカゴが戻る階）を決めるモード
const MODE_SERVICE := "service"   # エレベーターの稼働時間帯を切り替えるモード

# 建設メニューの並び（見出しごとにまとめる）。BUILDINGS に建物を足したら、ここにも入れる
const MODE_GROUPS := [
	{"name": "テナント", "modes": ["office", "hotel", "hotel_twin", "hotel_suite", "restaurant", "shop", "cinema", "housing", "wedding", "event_hall"]},
	{"name": "ロビー・移動", "modes": ["lobby", "lobby2", "lobby3", "sky_lobby", "stairs", "escalator", "elevator", "express_elevator", "service_elevator", "add_car", "set_home", "service"]},
	{"name": "設備", "modes": ["housekeeping", "recycling", "security", "medical", "subway", "ramp", "parking"]},
	{"name": "その他", "modes": ["resident"]},
]
const SKY_LOBBY_INTERVAL := 15 # スカイロビーを建てられる階の間隔（15階・30階・45階…）
const SCROLL_MARGIN_ROWS := 10 # スクロールできる範囲の、建物の上下に足す余白（行数）

var funds: int = 2000000
var current_mode: String = "lobby" # 更地から始めるので、最初はロビーを選んでおく
var funds_label: Label # 資金表示用のUIラベル
var message_label: Label # 操作結果のメッセージ（下から数行ぶん流れる）
var log_panel: Control   # ゲーム開始からのメッセージの記録（⌘Lで開閉）
var log_label: Label
var log_scroll: ScrollContainer
var message_log: Array[String] = [] # ゲーム開始からのメッセージ（時刻つき）
var last_message := ""              # 一番新しいメッセージ（時刻なし）
var hover_label: Label   # カーソル下のマスの情報（マウスの横に出る吹き出しの中身）
var hover_tooltip: Control # 吹き出し（カーソルの近くに浮かせて表示する）
var help_panel: Control # 操作説明（⌘Hで開閉）
var mode_select: OptionButton # 建設メニュー（リストから建物などを選ぶ）
var mode_info_label: Label # 選んだものの費用・大きさの表示
var v_scroll: VScrollBar # マップの上下スクロールバー
var grid_overlay # マス目の表示
var elevator_system # エレベーターのシャフトとカゴの管理
var parking_system  # 地下駐車場とスロープ（車で来るお客さん）
var visitor_system  # 外から来るお客さん（店の客・車で来た客）の動き
var noise_system    # 騒音（うるさい建物のまわりのマスに広がる）
var vip_system      # VIPの宿泊（★4への昇格イベント）
var incident_system # 事件（爆破予告と警備員）
var clock # ゲーム内の時計
var commute_system # オフィスの社員の出退勤
var economy_system # 毎日の決算（賃料収入と維持費）
var hotel_system # ホテルの客室・宿泊客・清掃員
var commerce_system # 飲食店（社員の昼食）
var rating_system # ビルの評価（★）
var housing_system # 住宅と入居者
var event_system # 結婚式場・イベントホール（休日の来客）
var lighting # 夜の明かり
var tenant_system # テナント（オフィス）の評価
var clock_label: Label # 日付と時刻の表示
var stats_label: Label   # ビルの状況（★・人口・社員・客室）の表示
var speed_button: Button # ゲームの速度（押すたびに切り替わる）

var residents: Array = [] # 配置済みの住人
var selected_resident = null # 行き先の指示を待っている住人

# ---------------------------------------------------
# グリッド情報（建物のマップデータ）
# キー: Vector2i（タイル座標） / 値: {"type": String}
# 住人AIや経路探索はこのデータを参照して「どこに何があるか」を判別する。
# 負の座標も扱えるよう、二次元配列ではなくDictionaryで管理している。
# ---------------------------------------------------
var building_grid: Dictionary = {}

# 1階の高さ（y）。それより下（yが大きい）は地下。ゲームは更地から始まり、ここに地面の線が引かれる
const GROUND_FLOOR_Y := 18
const MAX_FLOORS_ABOVE := 150 # 建てられる一番上の階（地上150階）
const MAX_FLOORS_BELOW := 50  # 掘れる一番下の階（地下50階）
const MAX_WIDTH := 100        # ビルの横幅（マス数）。0を中心に左右へ半分ずつ
const SPEEDS := [1, 4, 16] # ゲームの速度（押すたびにこの順に切り替わる）
const MEDICAL_RECOVER_BONUS := 0.5 # メディカルセンター1施設で、ストレスの回復が何割速くなるか
const MEDICAL_RECOVER_MAX := 2.5   # 回復の速さの上限（何倍まで）
const MESSAGE_LINES := 3      # 下部バーに出しておくメッセージの行数（古いものは上へ流れて消える）
const MESSAGE_LOG_MAX := 500  # ⌘Lで見られるメッセージの記録の数
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
	parking_system = ParkingSystem.new()
	parking_system.setup(self)
	add_child(parking_system)
	clock = GameClock.new()
	add_child(clock)
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
	create_ui()
	update_funds_display()

func _process(_delta: float) -> void:
	update_scrollbar()
	grid_overlay.update_hover()
	update_hover_label()
	clock_label.text = clock.get_time_text()
	stats_label.text = rating_system.get_status_text()
	var angry := 0
	for r in residents:
		if is_instance_valid(r) and r.is_angry():
			angry += 1
	if angry > 0:
		stats_label.text += " / 怒っている人 %d人" % angry
	if incident_system.has_roaches():
		stats_label.text += " / " + incident_system.get_roach_text()
	if incident_system.has_fire():
		stats_label.text += " / " + incident_system.get_fire_text()
	if incident_system.has_bomb():
		stats_label.text += " / " + incident_system.get_bomb_text()
	if vip_system.is_visiting():
		stats_label.text += " / VIPが来館中（ストレス %d）" % int(vip_system.vip.stress)
	var leaving: int = tenant_system.count_about_to_leave()
	if leaving > 0:
		stats_label.text += " / 退去しそうなテナント %d件" % leaving
	if economy_system.pollution > 0:
		stats_label.text += " / 衛生の悪化 レベル%d" % economy_system.pollution
	stats_label.text += " / 社員: 在館 %d / 全 %d人" % [commute_system.count_in_building(), commute_system.workers.size()]
	var unreachable: int = commute_system.count_unreachable()
	if unreachable > 0:
		stats_label.text += "（通勤できない %d人）" % unreachable
	if not tenant_system.offices.is_empty():
		stats_label.text += " / オフィス: 良い%d・普通%d・悪い%d・空室%d" % [
			tenant_system.count_rating(tenant_system.Rating.GOOD),
			tenant_system.count_rating(tenant_system.Rating.NORMAL),
			tenant_system.count_rating(tenant_system.Rating.BAD),
			tenant_system.count_vacant()]
	if not hotel_system.rooms.is_empty():
		stats_label.text += " / 客室: 宿泊 %d・清掃待ち %d・空室 %d" % [
			hotel_system.count_rooms(hotel_system.RoomState.OCCUPIED),
			hotel_system.count_rooms(hotel_system.RoomState.DIRTY),
			hotel_system.count_rooms(hotel_system.RoomState.CLEAN)]

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
# UIの自動生成ロジック
# ---------------------------------------------------
# 画面構成:
#   上部バー    … 1段目: 資金 / 日付と時刻 / 速度
#                  2段目: ビルの状況（★・人口・社員・客室）
#                  3段目: 建設メニュー
#   操作説明    … 上部バーの下に表示（⌘Hで開閉）。メッセージの記録は⌘Lで開閉
#   （マップ）  … クリックはそのままマップに届く
#   下部バー    … 操作結果のメッセージ（新しいものが下に出て、古いものは流れる）
#   吹き出し    … カーソル下のマスの情報（建物や人がいるマスで、マウスの横に出る）
# バーの上のクリックはバーが受け止めるので、下のマスに建設されることはない。
func create_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var layout = VBoxContainer.new()
	# 画面の文字・ボタン・余白をまとめて UI_SCALE 倍にする（テーマで文字の大きさを決め、
	# 余白や幅の指定にも同じ倍率をかける）
	var theme := Theme.new()
	theme.default_font_size = BASE_FONT_SIZE * UI_SCALE
	layout.theme = theme
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 0)
	canvas.add_child(layout)
	
	# --- 上部バー（2段） ---
	#   1段目: 資金 / 日付と時刻 / 速度
	#   2段目: モード切り替えボタン
	var top_rows = VBoxContainer.new()
	top_rows.add_theme_constant_override("separation", 4 * UI_SCALE)
	layout.add_child(make_bar(top_rows))
	var status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8 * UI_SCALE)
	top_rows.add_child(status_row)
	# ビルの状況（★・人口・社員・客室）は上部バーの2段目
	stats_label = Label.new()
	stats_label.clip_text = true
	stats_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_rows.add_child(stats_label)
	var build_row = HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 8 * UI_SCALE)
	top_rows.add_child(build_row)
	
	funds_label = Label.new()
	funds_label.add_theme_font_size_override("font_size", 20 * UI_SCALE)
	funds_label.custom_minimum_size.x = 420 * UI_SCALE # 金額の桁が変わっても時刻の位置がずれないように
	status_row.add_child(funds_label)
	
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 20 * UI_SCALE)
	status_row.add_child(clock_label)
	
	status_row.add_child(make_spacer())
	
	# ゲームの速度（Engine.time_scaleで、時計・住人・エレベーターをまとめて早送りする）。
	# ボタンは1つで、押すたびに 1x → 4x → 16x → 1x と切り替わり、今の速度だけを表示する
	speed_button = Button.new()
	speed_button.custom_minimum_size.x = 60 * UI_SCALE
	speed_button.pressed.connect(func(): set_speed(SPEEDS[(SPEEDS.find(int(Engine.time_scale)) + 1) % SPEEDS.size()]))
	status_row.add_child(speed_button)
	set_speed(1)
	
	# 操作説明（⌘H）とメッセージの記録（⌘L）は、ボタンではなくショートカットで開く
	
	# 建設メニュー: リストから選んで、マップをクリックして建てる（見出しごとにまとめる）
	var build_label = Label.new()
	build_label.text = "建設:"
	build_row.add_child(build_label)
	mode_select = OptionButton.new()
	mode_select.custom_minimum_size.x = 260 * UI_SCALE
	for group in MODE_GROUPS:
		mode_select.add_separator(group.name)
		for mode in group.modes:
			mode_select.add_item(get_mode_label(mode))
			mode_select.set_item_metadata(mode_select.item_count - 1, mode)
	mode_select.item_selected.connect(func(index): select_mode(mode_select.get_item_metadata(index)))
	for type in BUILDINGS:
		assert(MODE_GROUPS.any(func(group): return group.modes.has(type)), "%s が建設メニュー（MODE_GROUPS）にありません" % type)
	build_row.add_child(mode_select)
	mode_info_label = Label.new()
	mode_info_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	build_row.add_child(mode_info_label)
	
	# --- 操作説明（上部バーの下、右寄せ） ---
	var help_row = HBoxContainer.new()
	help_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(help_row)
	help_row.add_child(make_spacer())
	var help_label = Label.new()
	help_label.text = "\n".join([
		"建設: 上の「建設」メニューで選び、マップを左クリック / 右クリック: 撤去（建設費の半額を返金）",
		"更地から始まる。1階はロビー専用（ロビー・階段・エレベーターだけ）。人はロビーの左端（入口）から出入りする",
		"吹き抜けロビー: 2階分・3階分の高さのロビー。上の階には床がないので、人は1階だけを歩く",
		"スカイロビー: 15階・30階・45階…にだけ建てられる乗り換え専用のフロア（何階かはカーソル下の情報に出る）",
		"住人モード: 建物をクリックで住人を配置 → 行き先をクリックで移動",
		"エレベーター: 縦に並べるとシャフトになる。シャフトをクリックでその階にカゴを呼ぶ",
		"カゴ追加: シャフトをクリックすると、その階にカゴを1台追加（1本に4台まで、維持費3千円/日）。カゴの定員は8人",
		"社員: オフィスは横4マスで、1マスに1人（計4人）。8〜9時に入口から出勤し、17〜18時に帰る",
		"建設: クリックしたマスを左端に、建物の横幅ぶんのマスを使う。撤去はどのマスを右クリックしても建物ごと",
		"入口: 1階の左端と地下鉄駅（地下にだけ建てられる）。人は近い方の入口から出入りする",
		"速度: 上部バーの速度ボタンを押すたびに 1x → 4x → 16x → 1x と切り替わる",
		"ショートカット: ⌘H（この説明の開閉） / ⌘L（メッセージの記録） / ⌘+・⌘-（画面の拡大・縮小） / ⌘0（拡大率をもとに戻す）",
		"日付: 1日目は4月1日（月）。1年は365日で、12月24日・25日の夜にはサンタクロースのソリが空を横切る",
		"曜日: 1日目は月曜日。土日は休日でオフィスは休み（賃料は入る）、住宅の入居者は遅めに出かける",
		"結婚式場（横6マス）: 休日の10〜11時に12人が来て13時まで（1人1万円）",
		"イベントホール（横6マス）: 休日の13〜14時に15人が来て17時まで（1人3千円）",
		"ホテル: 17〜21時に客が来て泊まり、翌朝7〜10時に宿泊料を払って帰る。清掃が済むまで次の客は泊まれない",
		"　シングル（横2マス）: 1人・2万円・清掃20分 / ツイン（横3マス）: 2人・3.5万円・清掃30分 / スイート（横4マス）: 2人・8万円・清掃45分",
		"ハウスキーパー室（横2マス）: 清掃員が2人。清掃待ちの部屋を近い順に掃除する",
		"飲食店（横3マス）: 12〜13時に社員が一番近い店へ昼食に来る（30分、1人1千円の売上）",
		"住宅（横3マス・3人家族）: 17〜20時に入居者が来て入居（販売収入70万円、1回だけ）。毎朝7〜9時に出かけ、17〜20時に帰る",
		"ゴミ処理場（横3マス）: 1施設で1日20のゴミを処理。処理しきれないゴミは外部委託で1につき1千円かかる",
		"　処理が足りない日が続くとビルが汚れ（衛生の悪化）、レベル1につきストレス5ぶん全テナントの評価が下がる",
		"メディカルセンター（横3マス）: ビル全体のストレスの回復が速くなる（1施設で1.5倍・最大2.5倍）",
		"埋蔵金: 地下に建てるとマスごとに見つかることがある（深いほど確率も金額も上がる。同じマスは一度きり）",
		"ゴキブリ: 衛生の悪化が続くと大繁殖し、いるテナントの評価がストレス15ぶん悪くなる（悪化が0に戻ると消える）",
		"火災: ★2以上のビルでときどき出火。20分ごとに隣と上へ燃え広がり、60分燃えたテナントは焼け落ちる（警備員が消火する）",
		"爆破予告: ★2以上のビルにときどき届く。警備員が現場で解体できないと、120分後にそのテナントが吹き飛ぶ",
		"VIP: ★4の条件がそろうと16時にVIPが来館。ストレス30以下できれいな空きスイートに着けば合格（不合格なら翌日また来る）",
		"評価（★）: 決算時に条件を満たすと昇格。★2: 人口50・警備室 / ★3: 人口120・メディカルセンター・ゴミ処理場",
		"　★が1つ上がるごとに、賃料と宿泊料に25%の評価ボーナスが付く（人口 = 通勤できる社員 + 客室の定員 + 入居者）",
		"オフィスの評価: 毎日の決算で、社員のその日の最大ストレスの平均から 良い（緑）・普通（黄）・悪い（赤）を付ける",
		"　悪い日が3日続くとテナントが退去して空室（賃料なし）。2日後に新しいテナントが入居する",
		"　退去まであと1日のテナントは、評価のマークが点滅して知らせる（上部バーにも件数が出る）",
		"激怒: ストレスが95以上になると人の顔が赤く点滅する（上部バーに人数が出る）",
		"ホテル・住宅の評価: 客室は泊まった客のストレスで決まり、悪いと客が来にくい。住宅は悪い日が3日続くと家族が退去（販売収入を返金）",
		"収支: 毎日0時に決算。賃料・宿泊料・飲食の売上 − 維持費 − ゴミの外部委託費",
		"スクロール: マウスホイールで上下、Shift+ホイールで左右、右端のスクロールバー",
		"ズーム: Ctrl（⌘）+マウスホイール / トラックパッドのピンチ",
		"カメラ移動: 2本指スクロール / 中ボタンドラッグ / WASD・矢印キー",
	])
	help_label.add_theme_font_size_override("font_size", 13 * UI_SCALE) # 行数が多いので少し小さめ
	var help_scroll = ScrollContainer.new()
	help_scroll.custom_minimum_size = Vector2(1000, 420) # 画面に収まる高さ。はみ出す分はスクロールする
	help_scroll.add_child(help_label)
	help_panel = make_bar(help_scroll)
	help_panel.visible = false
	help_row.add_child(help_panel)
	
	# --- メッセージの記録（⌘Lで開閉。ゲーム開始からのメッセージを全部見られる） ---
	var log_row = HBoxContainer.new()
	log_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(log_row)
	log_label = Label.new()
	log_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	log_label.add_theme_font_size_override("font_size", 13 * UI_SCALE)
	log_scroll = ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(1000, 420)
	log_scroll.add_child(log_label)
	log_panel = make_bar(log_scroll)
	log_panel.visible = false
	log_row.add_child(log_panel)
	log_row.add_child(make_spacer())
	
	# --- マップ部分（クリックはそのまま通す）。右端に上下スクロールバー ---
	var map_row = HBoxContainer.new()
	map_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(map_row)
	map_row.add_child(make_spacer())
	v_scroll = VScrollBar.new()
	v_scroll.custom_minimum_size.x = 14 * UI_SCALE
	v_scroll.value_changed.connect(func(value): camera.position.y = value + v_scroll.page / 2.0)
	map_row.add_child(v_scroll)
	
	# --- 下部バー（2段） ---
	#   1段目: 操作結果のメッセージ（新しいものが下に出て、古いものは流れていく）
	#   2段目: カーソル下のマスの情報
	var bottom_rows = VBoxContainer.new()
	bottom_rows.add_theme_constant_override("separation", 2 * UI_SCALE)
	layout.add_child(make_bar(bottom_rows))
	
	message_label = Label.new()
	message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	# メッセージは行数が多いので、ほかの文字の半分の大きさにする
	message_label.add_theme_font_size_override("font_size", BASE_FONT_SIZE * UI_SCALE / 2)
	message_label.clip_text = true
	message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 新しいメッセージが一番下に出て、古いメッセージは上へ流れていく（MESSAGE_LINES 行ぶん）
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	message_label.custom_minimum_size.y = MESSAGE_LINES * BASE_FONT_SIZE * UI_SCALE / 2 * 1.3
	bottom_rows.add_child(message_label)
	
	# カーソル下のマスの情報は、マウスの横に吹き出し（ツールチップ）で出す
	hover_label = Label.new()
	hover_tooltip = make_bar(hover_label)
	hover_tooltip.theme = theme
	hover_tooltip.visible = false
	hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_tooltip.top_level = true # 画面の好きな位置に出せるようにする
	canvas.add_child(hover_tooltip)
	
	update_mode_select()

# 半透明の背景を持つバーを作る（中身をcontentとして入れる）
func make_bar(content: Control) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.9)
	style.set_content_margin_all(6 * UI_SCALE)
	style.content_margin_left = 12 * UI_SCALE
	style.content_margin_right = 12 * UI_SCALE
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(content)
	return panel

# 余白を埋めるだけの透明なControl（クリックは通す）
func make_spacer() -> Control:
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

# モードを切り替える
func select_mode(mode: String):
	current_mode = mode
	if mode != MODE_RESIDENT:
		select_resident(null)
	update_mode_select()

# 建設メニューに表示する名前
func get_mode_label(mode: String) -> String:
	if mode == MODE_RESIDENT:
		return "住人（テスト）"
	if mode == MODE_ADD_CAR:
		return "カゴ追加"
	if mode == MODE_SET_HOME:
		return "待機階を設定"
	if mode == MODE_SERVICE:
		return "稼働時間帯"
	var width := get_width(mode)
	return BUILDINGS[mode].name + ("（横%dマス）" % width if width > 1 else "")

# 選んだものの費用・大きさの説明
func get_mode_info(mode: String) -> String:
	if mode == MODE_RESIDENT:
		return "建物をクリックで住人を置き、行き先をクリック"
	if mode == MODE_SET_HOME:
		return "無料（シャフトをクリックでその階を待機階に。もう一度クリックで解除）"
	if mode == MODE_SERVICE:
		return "無料（シャフトをクリックで 終日 → 6時〜24時 → 8時〜20時 と切り替え）"
	if mode == MODE_ADD_CAR:
		return "1台 %s円（シャフトをクリック。1本に%d台まで）" % [format_money(elevator_system.CAR_COST), elevator_system.MAX_CARS]
	var info := "建設費 %s円・横%dマス" % [format_money(BUILDINGS[mode].cost), get_width(mode)]
	if get_height(mode) > 1:
		info += "・高さ%d階分" % get_height(mode)
	if mode == "express_elevator":
		info += "（1階とスカイロビーの階だけに停まる）"
	return info

# 建設メニューの選択と説明を、今のモードに合わせる
func update_mode_select():
	for i in mode_select.item_count:
		if mode_select.get_item_metadata(i) == current_mode:
			mode_select.select(i)
	mode_info_label.text = get_mode_info(current_mode)

# 資金の表示を更新する関数
func update_funds_display():
	if not funds_label:
		return
	funds_label.text = "現在の資金: %s円" % format_money(funds)
	if economy_system and not economy_system.last_report.is_empty():
		funds_label.text += "（前日 %s円）" % format_money(economy_system.last_report.total, true)

# 金額を3桁ごとのカンマ区切りにする（signedならプラスにも+を付ける）
func format_money(amount: int, signed := false) -> String:
	var digits := str(absi(amount))
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	if amount < 0:
		return "-" + result
	return ("+" + result) if signed else result

# 上下スクロールバーを、建物の高さとカメラの位置に合わせる
# 範囲は、いちばん上の建物の上から一番下の建物の下まで（上下に SCROLL_MARGIN_ROWS 行の余白）
func update_scrollbar():
	var tile_h: float = tile_map.tile_set.tile_size.y
	var top_row := ground_y
	var bottom_row := ground_y
	for cell: Vector2i in building_grid:
		top_row = mini(top_row, cell.y)
		bottom_row = maxi(bottom_row, cell.y)
	var page: float = get_viewport_rect().size.y / camera.zoom.y # 画面に映っている高さ
	var view_top: float = camera.position.y - page / 2.0
	# 範囲を変えると値が範囲内に押し戻されて value_changed が出るので、合わせている間は通知を止める
	# （通知でカメラが動くと、毎フレーム少しずつカメラがずれていってしまう）
	v_scroll.set_block_signals(true)
	v_scroll.min_value = minf((top_row - SCROLL_MARGIN_ROWS) * tile_h, view_top)
	v_scroll.max_value = maxf((bottom_row + 1 + SCROLL_MARGIN_ROWS) * tile_h, view_top + page)
	v_scroll.page = page
	v_scroll.value = view_top
	v_scroll.set_block_signals(false)

# カーソル下のマスの座標と建物を、マウスの横の吹き出しに表示する
func update_hover_label():
	if not hover_label:
		return
	if not grid_overlay.hover_visible:
		hover_label.text = ""
		hover_tooltip.visible = false
		return
	var cell: Vector2i = grid_overlay.hover_cell
	var type = get_building_type(cell)
	var text = "%s マス %s: %s" % [get_floor_name(cell.y), cell, BUILDINGS[type].name if type != "" else "空き"]
	if incident_system.has_roach_at(cell):
		text += "（ゴキブリ発生中）"
	if type == "office" and tenant_system.get_rating_text(cell) != "":
		text += "（%s）" % tenant_system.get_rating_text(cell)
	if hotel_system.is_room_type(type):
		var room_rating: String = tenant_system.get_room_rating_text(cell)
		text += "（%s%s・%s）" % [hotel_system.get_room_state_text(cell), "・" + room_rating if room_rating != "" else "",
			noise_system.get_noise_text(cell)]
	elif type == "restaurant":
		text += "（客 %d人）" % (commerce_system.count_eating_at(cell) + visitor_system.count_at_shop(cell))
	elif type == "shop":
		text += "（客 %d人）" % visitor_system.count_at_shop(cell)
	elif type == "cinema":
		text += "（%s）" % visitor_system.get_cinema_text(cell)
	elif event_system.is_hall_type(type):
		text += "（来客 %d人）" % event_system.count_at_hall(cell)
	elif elevator_system.is_shaft_type(type):
		var cars: Array = elevator_system.get_cars_at(cell)
		if type == "express_elevator" and not is_express_stop_floor(cell.y):
			text += "（この階には停まりません）"
		elif not cars.is_empty():
			if elevator_system.get_home(cell) == cell.y:
				text += "（待機階）"
			var service: Dictionary = elevator_system.get_service(cell)
			if service.name != "終日":
				text += "（稼働 %s%s）" % [service.name, "" if cars[0].in_service else "・今は停止中"]
			var loads: Array[String] = []
			for car in cars:
				loads.append("%d/%d" % [car.passengers.size(), car.capacity])
			text += "（カゴ%d台: %s人）" % [cars.size(), "・".join(loads)]
	elif type == "housing":
		var home_rating: String = tenant_system.get_home_rating_text(cell)
		text += "（%s%s・%s）" % [housing_system.get_home_state_text(cell), "・" + home_rating if home_rating != "" else "",
			noise_system.get_noise_text(cell)]
	elif type == "parking":
		text += "（%s）" % parking_system.get_parking_text(cell)
	elif type == "medical":
		text += "（ビル全体のストレスの回復 %.1f倍）" % stress_recover_rate()
	elif type == "recycling":
		text += "（ビル全体の処理能力 %d/日）" % economy_system.recycling_capacity()
	var resident = get_resident_at(cell)
	if resident:
		text += " / 住人のストレス: %d" % int(resident.stress)
	hover_label.text = text
	show_tooltip(cell)

# 吹き出しを、マウスの右下に出す（画面からはみ出すときは左や上に寄せる）。
# 空きマスのときは出さない（建物や人がいるマスだけ）
func show_tooltip(cell: Vector2i) -> void:
	hover_tooltip.visible = not is_cell_empty(cell) or get_resident_at(cell) != null
	if not hover_tooltip.visible:
		return
	var offset := Vector2(12, 12) * UI_SCALE
	var size := hover_tooltip.get_combined_minimum_size()
	var screen: Vector2 = get_viewport_rect().size
	var pos: Vector2 = grid_overlay.hover_screen_pos + offset
	if pos.x + size.x > screen.x:
		pos.x = grid_overlay.hover_screen_pos.x - size.x - offset.x
	if pos.y + size.y > screen.y:
		pos.y = grid_overlay.hover_screen_pos.y - size.y - offset.y
	hover_tooltip.position = pos.clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))

# 画面とログにメッセージを出す
func show_message(text: String):
	last_message = text
	if text == "": # 表示を消すだけ（記録には残さない）
		if message_label:
			message_label.text = ""
		return
	message_log.append("%d日目 %02d:%02d  %s" % [clock.day, clock.minute_of_day() / 60, clock.minute_of_day() % 60, text] if clock else text)
	if message_log.size() > MESSAGE_LOG_MAX:
		message_log.remove_at(0)
	if message_label:
		# 下部バーには新しい方から MESSAGE_LINES 行ぶんだけ出す（古いものは上へ流れて消える）
		message_label.text = "\n".join(message_log.slice(maxi(message_log.size() - MESSAGE_LINES, 0)))
	if log_label and log_panel.visible:
		update_log_panel()
	print(text)

# ⌘Lで開くメッセージの記録を、最新のメッセージまでスクロールして表示する
func update_log_panel() -> void:
	log_label.text = "\n".join(message_log)
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

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
	if elevator_system.is_shaft_type(current_mode) and get_building_type(cell) == current_mode:
		return elevator_system.get_car_at(cell) != null and elevator_system.get_car_at(cell).is_stop_floor(cell.y) # シャフトをクリックするとカゴを呼べる
	return get_build_problem(cell, current_mode) == ""

# カーソル下で強調表示するマス（建設モードなら、建てたときに使うマス全部）
func get_hover_footprint(cell: Vector2i) -> Array[Vector2i]:
	if current_mode == MODE_RESIDENT or current_mode == MODE_ADD_CAR or current_mode == MODE_SET_HOME or current_mode == MODE_SERVICE \
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
	# UIの上以外でマウスが動いたら、カーソル下のマスの強調表示を更新する
	if event is InputEventMouseMotion:
		grid_overlay.hover_screen_pos = event.position
		grid_overlay.hover_enabled = true
		return
	if not (event is InputEventMouseButton and event.pressed):
		return

	# イベントに含まれるクリック位置をタイルマップの座標系に変換する
	var local_event = tile_map.make_input_local(event)
	var map_pos: Vector2i = tile_map.local_to_map(local_event.position)
	if event.button_index == MOUSE_BUTTON_LEFT:
		if current_mode == MODE_RESIDENT:
			handle_resident_click(map_pos)
		elif current_mode == MODE_ADD_CAR:
			add_elevator_car(map_pos)
		elif current_mode == MODE_SET_HOME:
			show_message(elevator_system.set_home(map_pos))
		elif current_mode == MODE_SERVICE:
			show_message(elevator_system.cycle_service(map_pos))
		elif elevator_system.is_shaft_type(current_mode) and get_building_type(map_pos) == current_mode:
			call_elevator(map_pos)
		else:
			build_at(map_pos)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		demolish_at(map_pos)

# ⌘（Ctrl）と組み合わせるショートカット。受け付けたら true
#   ⌘H: 操作説明の開閉 / ⌘L: メッセージの記録の開閉
#   ⌘+ / ⌘-: ゲーム画面の拡大・縮小 / ⌘0: 拡大率をもとに戻す
func handle_shortcut(event: InputEventKey) -> bool:
	if not (event.meta_pressed or event.ctrl_pressed):
		return false
	match event.keycode:
		KEY_H:
			help_panel.visible = not help_panel.visible
		KEY_L:
			log_panel.visible = not log_panel.visible
			if log_panel.visible:
				update_log_panel()
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
		return
	
	var data = BUILDINGS[current_mode]
	funds -= data.cost
	var height := get_height(current_mode)
	for cell in get_footprint(map_pos, current_mode):
		# ドット絵の区画: 横は左端からの位置、縦は上から数えた位置（一番下の階が一番下の区画）
		var atlas := Vector2i(cell.x - map_pos.x, height - 1 - (map_pos.y - cell.y))
		tile_map.set_cell(cell, data.source_id, atlas)
		building_grid[cell] = {"type": current_mode, "origin": map_pos}
	rebuild_systems()
	update_funds_display()
	show_message("%sを建設しました %s" % [data.name, map_pos])
	incident_system.on_built(get_footprint(map_pos, current_mode)) # 地下なら埋蔵金が見つかることがある

# 撤去（売却）処理（建物のどのマスをクリックしても、その建物全体を撤去する）
# 建物を壊す（爆発など。払い戻しはなく、支えのルールも見ない）
func destroy_unit(cell: Vector2i) -> void:
	if is_cell_empty(cell):
		return
	for c in get_unit_cells(cell):
		tile_map.erase_cell(c)
		building_grid.erase(c)
	rebuild_systems()

func demolish_at(map_pos: Vector2i):
	if is_cell_empty(map_pos):
		return
	
	var problem := get_demolish_problem(map_pos)
	if problem != "":
		show_message(problem)
		return
	var type = get_building_type(map_pos)
	var origin: Vector2i = building_grid[map_pos].origin
	var refund = int(BUILDINGS[type].cost * REFUND_RATE)
	
	funds += refund
	for cell in get_unit_cells(map_pos):
		tile_map.erase_cell(cell)
		building_grid.erase(cell)
	rebuild_systems()
	update_funds_display()
	show_message("%sを撤去しました %s 払い戻し: %d円" % [BUILDINGS[type].name, origin, refund])

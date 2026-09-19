extends Node2D

const Resident := preload("res://resident.gd")
const GridOverlay := preload("res://grid_overlay.gd")
const ElevatorSystem := preload("res://elevator_system.gd")

@onready var tile_map = $TileMapLayer
@onready var camera = $Camera2D

# ---------------------------------------------------
# 建物の定義（種類を増やすときはここに追記する）
# "color" があるものは、TileSetに画像がなくてもコードでタイルを生成する
# ---------------------------------------------------
const BUILDINGS := {
	"office": {"name": "オフィス", "cost": 100000, "source_id": 0},
	"stairs": {"name": "階段", "cost": 50000, "source_id": 1},
	"elevator": {"name": "エレベーター", "cost": 100000, "source_id": 2, "color": Color(0.33, 0.35, 0.4)},
}
const REFUND_RATE := 0.5 # 撤去時の払い戻し率
const MODE_RESIDENT := "resident" # 住人を配置・移動させるモード

var funds: int = 1000000
var current_mode: String = "office"
var funds_label: Label # 資金表示用のUIラベル
var message_label: Label # 操作結果のメッセージ表示用
var hover_label: Label # カーソル下のマスの情報表示用
var help_panel: Control # 操作説明（ボタンで表示/非表示）
var mode_buttons: Dictionary = {} # モード名 -> Button
var grid_overlay # マス目の表示
var elevator_system # エレベーターのシャフトとカゴの管理

var residents: Array = [] # 配置済みの住人
var selected_resident = null # 行き先の指示を待っている住人

# ---------------------------------------------------
# グリッド情報（建物のマップデータ）
# キー: Vector2i（タイル座標） / 値: {"type": String}
# 住人AIや経路探索はこのデータを参照して「どこに何があるか」を判別する。
# 負の座標も扱えるよう、二次元配列ではなくDictionaryで管理している。
# ---------------------------------------------------
var building_grid: Dictionary = {}

func _ready() -> void:
	create_generated_tile_sources()
	apply_tile_types()
	load_grid_from_tilemap()
	elevator_system = ElevatorSystem.new()
	elevator_system.setup(self)
	add_child(elevator_system)
	elevator_system.rebuild()
	tile_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # 拡大してもタイルをぼかさない
	focus_camera_on_building()
	grid_overlay = GridOverlay.new()
	grid_overlay.setup(self)
	tile_map.add_child(grid_overlay)
	create_ui()
	update_funds_display()

func _process(_delta: float) -> void:
	grid_overlay.update_hover()
	update_hover_label()

func _notification(what: int) -> void:
	# マウスがウィンドウの外に出たらマスの強調表示を消す
	if what == NOTIFICATION_WM_MOUSE_EXIT and grid_overlay:
		grid_overlay.hover_enabled = false

# 建物全体が画面中央に来るようにカメラを合わせる
func focus_camera_on_building():
	var used: Rect2i = tile_map.get_used_rect()
	if used.size == Vector2i.ZERO:
		return
	var center_local = (tile_map.map_to_local(used.position) + tile_map.map_to_local(used.end - Vector2i.ONE)) / 2.0
	camera.focus_on(tile_map.to_global(center_local))

# ---------------------------------------------------
# UIの自動生成ロジック
# ---------------------------------------------------
# 画面構成:
#   上部バー    … 資金 / モード切り替えボタン / 操作説明ボタン
#   操作説明    … 上部バーの下に表示（ボタンで開閉）
#   （マップ）  … クリックはそのままマップに届く
#   下部バー    … 操作結果のメッセージ / カーソル下のマスの情報
# バーの上のクリックはバーが受け止めるので、下のマスに建設されることはない。
func create_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var layout = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 0)
	canvas.add_child(layout)
	
	# --- 上部バー ---
	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	layout.add_child(make_bar(top_row))
	
	funds_label = Label.new()
	funds_label.add_theme_font_size_override("font_size", 20)
	funds_label.custom_minimum_size.x = 260 # 金額の桁が変わってもボタンの位置がずれないように
	top_row.add_child(funds_label)
	
	# 同じグループのボタンは1つだけ押下状態になる（ラジオボタン的な挙動）
	var group = ButtonGroup.new()
	for mode in BUILDINGS.keys() + [MODE_RESIDENT]:
		var btn = Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.pressed.connect(func(): select_mode(mode))
		top_row.add_child(btn)
		mode_buttons[mode] = btn
	
	top_row.add_child(make_spacer())
	
	var help_button = Button.new()
	help_button.text = "操作説明"
	help_button.toggle_mode = true
	help_button.toggled.connect(func(on): help_panel.visible = on)
	top_row.add_child(help_button)
	
	# --- 操作説明（上部バーの下、右寄せ） ---
	var help_row = HBoxContainer.new()
	help_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(help_row)
	help_row.add_child(make_spacer())
	var help_label = Label.new()
	help_label.text = "\n".join([
		"左クリック: 建設 / 右クリック: 撤去（建設費の半額を返金）",
		"住人モード: 建物をクリックで住人を配置 → 行き先をクリックで移動",
		"エレベーター: 縦に並べるとシャフトになる。シャフトをクリックでその階にカゴを呼ぶ",
		"ズーム: マウスホイール / トラックパッドのピンチ",
		"カメラ移動: 2本指スクロール / 中ボタンドラッグ / WASD・矢印キー",
	])
	help_panel = make_bar(help_label)
	help_panel.visible = false
	help_row.add_child(help_panel)
	
	# --- マップ部分（何も置かず、クリックを通す） ---
	var map_space = make_spacer()
	map_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(map_space)
	
	# --- 下部バー ---
	var bottom_row = HBoxContainer.new()
	layout.add_child(make_bar(bottom_row))
	
	message_label = Label.new()
	message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(message_label)
	
	hover_label = Label.new()
	bottom_row.add_child(hover_label)
	
	update_mode_buttons()

# 半透明の背景を持つバーを作る（中身をcontentとして入れる）
func make_bar(content: Control) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.9)
	style.set_content_margin_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
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
	update_mode_buttons()

# ボタンに表示するモード名
func get_mode_label(mode: String) -> String:
	if mode == MODE_RESIDENT:
		return "住人 (テスト)"
	var data = BUILDINGS[mode]
	return "%s (%d万円)" % [data.name, data.cost / 10000]

# 選択中のボタンを強調表示する
func update_mode_buttons():
	for mode in mode_buttons:
		var btn: Button = mode_buttons[mode]
		var label = get_mode_label(mode)
		if mode == current_mode:
			btn.text = "▶ " + label + " [選択中]"
			btn.button_pressed = true
			btn.modulate = Color(1.0, 0.9, 0.3) # 黄色っぽく強調
		else:
			btn.text = label
			btn.modulate = Color(1, 1, 1)

# 資金の表示を更新する関数
func update_funds_display():
	if funds_label:
		funds_label.text = "現在の資金: " + str(funds) + "円"

# 下部バーにカーソル下のマスの座標と建物を表示する
func update_hover_label():
	if not hover_label:
		return
	if not grid_overlay.hover_visible:
		hover_label.text = ""
		return
	var cell: Vector2i = grid_overlay.hover_cell
	var type = get_building_type(cell)
	hover_label.text = "マス %s: %s" % [cell, BUILDINGS[type].name if type != "" else "空き"]

# 画面とログにメッセージを出す
func show_message(text: String):
	if message_label:
		message_label.text = text
	print(text)

# ---------------------------------------------------
# グリッド情報の管理
# ---------------------------------------------------

# BUILDINGSで "color" を指定した建物のうち、TileSetにまだないものはタイルを生成して追加する
# （エレベーターなど。見た目: 指定色の塗りつぶし＋左右のレール）
func create_generated_tile_sources():
	var tile_set: TileSet = tile_map.tile_set
	var size: Vector2i = tile_set.tile_size
	for type in BUILDINGS:
		var data = BUILDINGS[type]
		if not data.has("color") or tile_set.has_source(data.source_id):
			continue
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(data.color)
		var rail_color: Color = data.color.darkened(0.4)
		for y in size.y:
			image.set_pixel(2, y, rail_color)
			image.set_pixel(size.x - 3, y, rail_color)
		var source := TileSetAtlasSource.new()
		source.texture = ImageTexture.create_from_image(image)
		source.texture_region_size = size
		source.create_tile(Vector2i.ZERO)
		tile_set.add_source(source, data.source_id)

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
func load_grid_from_tilemap():
	building_grid.clear()
	for cell in tile_map.get_used_cells():
		var type = get_type_from_tile(cell)
		if BUILDINGS.has(type):
			building_grid[cell] = {"type": type}

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
const ELEVATOR_WAIT_COST := 4.0  # エレベーターに乗る（待ち時間の見込み）
const ELEVATOR_FLOOR_COST := 0.5 # エレベーターで1階分移動する

# 指定マスから1回で移動できる先とそのコストの一覧（住人の移動ルールはすべてここで決まる）
# - 横移動:       隣のマスに建物があれば歩ける（エレベーターの扉の前も通り抜けられる）
# - 階段:         階段マスは、そのマスと1つ上の階をつなぐ
# - エレベーター: シャフトのマスから、同じシャフトの別の階へ乗って移動できる
# 戻り値: [{"to": Vector2i, "cost": float}, ...]
func get_moves(cell: Vector2i) -> Array:
	var result: Array = []
	if is_cell_empty(cell):
		return result
	for dir in [Vector2i.LEFT, Vector2i.RIGHT]:
		if not is_cell_empty(cell + dir):
			result.append({"to": cell + dir, "cost": WALK_COST})
	if get_building_type(cell) == "stairs" and not is_cell_empty(cell + Vector2i.UP):
		result.append({"to": cell + Vector2i.UP, "cost": STAIRS_COST})
	if get_building_type(cell + Vector2i.DOWN) == "stairs":
		result.append({"to": cell + Vector2i.DOWN, "cost": STAIRS_COST})
	if get_building_type(cell) == "elevator":
		var car = elevator_system.get_car_at(cell)
		if car:
			for y in range(car.top_y, car.bottom_y + 1):
				if y != cell.y:
					var cost := ELEVATOR_WAIT_COST + ELEVATOR_FLOOR_COST * absi(y - cell.y)
					result.append({"to": Vector2i(cell.x, y), "cost": cost})
	return result

# fromからtoへ1回で移動できるか
func can_move(from: Vector2i, to: Vector2i) -> bool:
	for move in get_moves(from):
		if move.to == to:
			return true
	return false

# fromからtoへの移動がエレベーターに乗る移動か（同じシャフト内の別の階への移動）
func is_elevator_ride(from: Vector2i, to: Vector2i) -> bool:
	return from.x == to.x and from.y != to.y \
		and get_building_type(from) == "elevator" and get_building_type(to) == "elevator"

# ダイクストラ法でコストが最小の経路を求める
# 戻り値: [from, ..., to] のマス配列。経路がなければ空配列。
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
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
		for move in get_moves(current):
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
	if current_mode == "elevator" and get_building_type(cell) == "elevator":
		return true # シャフトをクリックするとカゴを呼べる
	return is_cell_empty(cell) and funds >= BUILDINGS[current_mode].cost

# ---------------------------------------------------
# 住人の管理
# ---------------------------------------------------

func spawn_resident(cell: Vector2i):
	var resident = Resident.new()
	resident.setup(self, cell)
	tile_map.add_child(resident)
	residents = residents.filter(is_instance_valid) # 退場した住人を除く
	residents.append(resident)
	return resident

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
		elif current_mode == "elevator" and get_building_type(map_pos) == "elevator":
			call_elevator(map_pos)
		else:
			build_at(map_pos)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		demolish_at(map_pos)

# シャフトのマスをクリックしたとき、その階にカゴを呼ぶ
func call_elevator(cell: Vector2i):
	if elevator_system.call_car(cell):
		show_message("エレベーターを %s に呼びました" % cell)

# 建設処理
func build_at(map_pos: Vector2i):
	if not is_cell_empty(map_pos):
		return

	var data = BUILDINGS[current_mode]
	if funds < data.cost:
		show_message("資金不足です！")
		return

	funds -= data.cost
	tile_map.set_cell(map_pos, data.source_id, Vector2i(0, 0))
	building_grid[map_pos] = {"type": current_mode}
	elevator_system.rebuild()
	update_funds_display()
	show_message("%sを建設しました %s" % [data.name, map_pos])

# 撤去（売却）処理
func demolish_at(map_pos: Vector2i):
	if is_cell_empty(map_pos):
		return

	var type = get_building_type(map_pos)
	var refund = int(BUILDINGS[type].cost * REFUND_RATE)

	funds += refund
	tile_map.erase_cell(map_pos)
	building_grid.erase(map_pos)
	elevator_system.rebuild()
	update_funds_display()
	show_message("%sを撤去しました %s 払い戻し: %d円" % [BUILDINGS[type].name, map_pos, refund])

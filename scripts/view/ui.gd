extends Node

const ChartView := preload("res://scripts/view/chart_view.gd")
const Buildings := preload("res://scripts/systems/buildings.gd")
const ElevatorCar := preload("res://scripts/actors/elevator_car.gd")

# ---------------------------------------------------
# 画面（UI）の組み立てと更新。main.gd から使う。
#   画面の文字・ボタン・余白は UI_SCALE 倍にしてある（見やすさのため）。
#   毎フレームの更新は update() で行う（資金・時刻・ビルの状況・案内・吹き出し・スクロールバー）。
# ---------------------------------------------------

const UI_SCALE := 2      # 画面表示（文字・ボタン・余白）の大きさの倍率
const PANEL_WIDTH := 1400 # メッセージの記録などのパネルの横幅（画面幅1600に収まる大きさ）
const HELP_PANEL_WIDTH := 1000 # 操作説明パネルの横幅（文字フォントに合わせて読みやすい幅にする）
const BASE_FONT_SIZE := 16 # 倍率をかける前の文字の大きさ
const MESSAGE_LINES := 3 # 下部バーに出しておくメッセージの行数

# 上部バーの色
const BAR_COLOR := Color(0.09, 0.1, 0.15, 0.96)     # バーの地の色
const BAR_ACCENT := Color(0.9, 0.7, 0.3)             # バーの下の縁取り（金色）
const CHIP_COLOR := Color(1, 1, 1, 0.06)             # 資金・日付を囲む札の色
const BUTTON_COLOR := Color(0.17, 0.19, 0.27)        # ボタンの色
const BUTTON_HOVER_COLOR := Color(0.23, 0.26, 0.37)  # カーソルを合わせたときのボタンの色
const BUTTON_PRESSED_COLOR := Color(0.12, 0.13, 0.19)
const FUNDS_COLOR := Color(1.0, 0.9, 0.55)           # 資金の文字（金色）
const GAIN_COLOR := Color(0.45, 0.9, 0.5)            # 前日の収支（黒字）
const LOSS_COLOR := Color(1.0, 0.45, 0.45)           # 前日の収支（赤字）・資金がマイナスのとき
const STAR_COLOR := Color(1.0, 0.82, 0.3)            # ★の文字
const WARNING_COLOR := Color(1.0, 0.6, 0.25)         # 気をつけることがあるときの★のボタンの縁
const ICON_DOT := 4                                  # アイコンの1ドットの大きさ（画面上のpx）
# 上部バーのアイコン（10×10ドット。文字1つが1ドットの色。"." は透明）
const ICON_COLORS := {
	"K": Color("#1b1b24"), "y": Color("#e0a526"), "Y": Color("#ffd966"), "W": Color("#f4f1ea"),
	"R": Color("#d94a4a"), "k": Color("#4a4a58"), "G": Color("#aab2c0"), "b": Color("#8a5a30"),
	"g": Color("#6fd08a"), "P": Color("#9fd8ff"),
}
const ICONS := {
	"coin": ["...KKKK...", ".KKyyyyKK.", ".KyYYYYyK.", "KyYyKKyYyK", "KyYKyyyYyK",
		"KyYKyyyYyK", "KyYyKKyYyK", ".KyYYYYyK.", ".KKyyyyKK.", "...KKKK..."],
	"calendar": ["..K....K..", "KKKKKKKKKK", "KRRRRRRRRK", "KRRRRRRRRK", "KWWWWWWWWK",
		"KWkWkWkWWK", "KWWWWWWWWK", "KWkWkWkWWK", "KWWWWWWWWK", "KKKKKKKKKK"],
	"hammer": [".KKKKKKK..", "KGGGGGGGK.", "KGWGGGGGK.", "KGGGGGGGK.", ".KKKbbKK..",
		"...KbbK...", "...KbbK...", "...KbbK...", "...KbbK...", "....KK...."],
	"route": ["..KK......", ".KggK.....", ".KggK..KK.", "..KK..KggK", "......KggK",
		"..KK...KK.", ".KggK.....", ".KggK..KK.", "..KK..KggK", "......KggK"],
	"pause": ["..........", ".KKK.KKK..", ".KWK.KWK..", ".KWK.KWK..", ".KWK.KWK..",
		".KWK.KWK..", ".KWK.KWK..", ".KWK.KWK..", ".KKK.KKK..", ".........."],
	"play": ["..K.......", "..KK......", "..KgK.....", "..KggK....", "..KgggK...",
		"..KgggK...", "..KggK....", "..KgK.....", "..KK......", "..K......."],
	"speed1": ["..K.......", "..KK......", "..KPK.....", "..KPPK....", "..KPPPK...",
		"..KPPPK...", "..KPPK....", "..KPK.....", "..KK......", "..K......."],
	"speed2": ["K....K....", "KK...KK...", "KPK..KPK..", "KPPK.KPPK.", "KPPPKKPPPK",
		"KPPPKKPPPK", "KPPK.KPPK.", "KPK..KPK..", "KK...KK...", "K....K...."],
	"speed3": ["K..K..K...", "KK.KK.KK..", "KPKKPKKPK.", "KPPKPPKPPK", "KPPKPPKPPK",
		"KPPKPPKPPK", "KPPKPPKPPK", "KPKKPKKPK.", "KK.KK.KK..", "K..K..K..."],
}

var world: Node2D # main.gd

# 画面の部品
var funds_label: Label     # 資金
var funds_change_label: Label # 前日の収支（黒字は緑・赤字は赤）
var clock_label: Label     # 日付・時刻・天気
var stats_button: Button   # ★の表示（押すとくわしい状況が開く）
var stats_panel: Control   # ビルの状況（人口・社員・目標・オフィス・客室）
var stats_label: Label     # その中身
var speed_button: Button   # ゲームの速度（押すたびに切り替わる）
var pause_button: Button   # 一時停止・再開
var route_button: Button   # 経路（人の通り道）の表示の切り替え
var menu_bar: MenuBar      # 画面上部のメニュー（macOSでは画面最上部のメニューバーに出る）
var mode_select: OptionButton # 建設メニュー
var message_label: Label   # 操作結果のメッセージ（下から数行ぶん流れる）
var hover_label: Label     # カーソル下のマスの情報（吹き出しの中身）
var hover_tooltip: Control # 吹き出し
var help_panel: Control    # 操作説明（F1・H）
var log_panel: Control     # メッセージの記録（⌘L）
var log_label: Label
var log_scroll: ScrollContainer
var chart_panel: Control   # 収支のグラフ（⌘G）
var overlay_panel: Control # 色分け表示の凡例（Vキー）
var overlay_label: RichTextLabel
var tutorial_panel: Control # はじめての案内
var tutorial_label: Label
var title_panel: Control   # タイトル画面
var goal_panel: Control    # 目標を達成したときの画面
var ransom_panel: Control  # 爆破予告の身代金を払うか決める画面
var save_panel: Control    # セーブ・読み込みの枠を選ぶ画面（⌘S・⌘O）
var save_title: Label
var save_rows: VBoxContainer
var save_mode := "save"    # "save"（保存する枠を選ぶ）/ "load"（読み込む枠を選ぶ）
var ransom_text: Label
var ransom_pay_button: Button
var ransom_refuse_button: Button
var goal_title: Label
var goal_text: Label
var v_scroll: VScrollBar   # 右端の上下スクロールバー

func setup(p_world: Node2D) -> void:
	world = p_world

# 毎フレームの更新（main.gd の _process から呼ぶ）
func update() -> void:
	if v_scroll == null:
		return # まだ画面を組み立てていない
	update_scrollbar()
	update_hover_label()
	clock_label.text = "%s  %s" % [world.clock.get_time_text(), world.weather_system.get_weather_text()]
	if world.paused:
		clock_label.text += "  ⏸ 停止中"
	var warning_list := warnings()
	# ★の数を、塗った星と白抜きの星で見せる（例: ★3 なら ★★★☆）
	var stars: int = world.rating_system.stars
	stats_button.text = "★".repeat(stars) + "☆".repeat(maxi(world.rating_system.MAX_STARS - stars, 0))
	if not warning_list.is_empty():
		stats_button.text += " ⚠%d" % warning_list.size() # 気をつけることがあるときは★の横に出す
	set_warning_outline(stats_button, not warning_list.is_empty())
	update_stats_panel(warning_list)
	tutorial_label.text = world.tutorial_system.current_text()
	tutorial_panel.visible = tutorial_label.text != ""

# 下部バーのメッセージ（新しいものが下に出て、古いものは上へ流れる）
func show_messages(log: Array) -> void:
	if message_label:
		message_label.text = "\n".join(log.slice(maxi(log.size() - MESSAGE_LINES, 0)))
	if log_label and log_panel.visible:
		update_log_panel()

func clear_message() -> void:
	if message_label:
		message_label.text = ""

# ---------------------------------------------------
# UIの自動生成ロジック
# ---------------------------------------------------
# 画面構成:
#   上部バー    … 1段目: 資金 / 日付と時刻 / 速度
#                  2段目: ビルの状況（★・人口・社員・客室）
#                  3段目: 建設メニュー
#   操作説明    … 上部バーの下に表示（F1・Hで開閉）。メッセージの記録は⌘Lで開閉
#   （マップ）  … クリックはそのままマップに届く
#   下部バー    … 操作結果のメッセージ（新しいものが下に出て、古いものは流れる）
#   吹き出し    … カーソル下のマスの情報（建物や人がいるマスで、マウスの横に出る）
# バーの上のクリックはバーが受け止めるので、下のマスに建設されることはない。
func build() -> void:
	build_bars()
	build_title()
	world.update_funds_display()

# 上下のバー・操作説明・記録・グラフ・吹き出しを組み立てる
func build_bars() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var layout = VBoxContainer.new()
	# 画面の文字・ボタン・余白をまとめて UI_SCALE 倍にする（テーマで文字の大きさを決め、
	# 余白や幅の指定にも同じ倍率をかける）
	var theme := Theme.new()
	theme.default_font_size = BASE_FONT_SIZE * UI_SCALE
	theme.set_stylebox("panel", "TooltipPanel", tooltip_style())
	theme.set_font_size("font_size", "TooltipLabel", 12 * UI_SCALE)
	layout.theme = theme
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 0)
	canvas.add_child(layout)
	
	# --- メニューバー（macOSでは画面最上部のシステムのメニューバーに出る） ---
	menu_bar = build_menu_bar()
	layout.add_child(menu_bar)
	
	# --- 上部バー（2段） ---
	#   1段目: 資金 / 日付と時刻
	#   2段目: ★（押すとくわしい状況）/ 速度 / 建設メニュー / 経路
	var top_rows = VBoxContainer.new()
	top_rows.add_theme_constant_override("separation", 4 * UI_SCALE)
	var top_bar := make_bar(top_rows)
	top_bar.add_theme_stylebox_override("panel", top_bar_style())
	top_bar.theme = button_theme() # 上部バーのボタン・建設メニューは、角の丸い濃い色のボタンにする
	layout.add_child(top_bar)
	var status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8 * UI_SCALE)
	top_rows.add_child(status_row)
	# 上部バーの2段目は★だけにして、くわしい状況は★を押したときに出す
	var stats_row = HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 8 * UI_SCALE)
	top_rows.add_child(stats_row)
	stats_button = Button.new()
	stats_button.custom_minimum_size.x = 130 * UI_SCALE
	stats_button.tooltip_text = "ビルの評価（押すと、くわしい状況が開く）"
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		stats_button.add_theme_color_override(state, STAR_COLOR)
	stats_button.pressed.connect(func(): toggle_stats_panel())
	stats_row.add_child(stats_button)
	# ゲームの速度（押すたびに 1x → 4x → 16x → 1x と切り替わり、今の速度だけを表示する）
	speed_button = Button.new()
	speed_button.custom_minimum_size.x = 76 * UI_SCALE
	speed_button.expand_icon = false
	speed_button.pressed.connect(func(): world.set_speed(world.next_speed()))
	# 一時停止のボタン（スペースキーでも止める・再開する）。速さのボタンの左に置く
	pause_button = Button.new()
	pause_button.custom_minimum_size.x = 48 * UI_SCALE
	pause_button.tooltip_text = "一時停止・再開（スペースキー）"
	pause_button.pressed.connect(func(): world.toggle_pause())
	stats_row.add_child(pause_button)
	stats_row.add_child(speed_button)
	world.set_speed(1)
	
	# 資金の札: 金貨のアイコン・資金（金色）・前日の収支（黒字は緑、赤字は赤）
	var funds_box := HBoxContainer.new()
	funds_box.add_theme_constant_override("separation", 6 * UI_SCALE)
	funds_box.add_child(make_icon("coin"))
	funds_label = Label.new()
	funds_label.add_theme_font_size_override("font_size", 20 * UI_SCALE)
	funds_label.add_theme_color_override("font_color", FUNDS_COLOR)
	funds_box.add_child(funds_label)
	funds_change_label = Label.new()
	funds_change_label.add_theme_font_size_override("font_size", 15 * UI_SCALE)
	funds_box.add_child(funds_change_label)
	var funds_chip := make_chip(funds_box)
	funds_chip.custom_minimum_size.x = 340 * UI_SCALE # 金額の桁が変わっても時刻の位置がずれないように
	status_row.add_child(funds_chip)
	
	# 日付・時刻・天気の札
	var clock_box := HBoxContainer.new()
	clock_box.add_theme_constant_override("separation", 6 * UI_SCALE)
	clock_box.add_child(make_icon("calendar"))
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 20 * UI_SCALE)
	clock_box.add_child(clock_label)
	status_row.add_child(make_chip(clock_box))
	
	status_row.add_child(make_spacer())
	
	# 操作説明（F1・H）とメッセージの記録（⌘L）は、ボタンではなくショートカットで開く
	
	# 建設メニュー: リストから選んで、マップをクリックして建てる（見出しごとにまとめる）
	stats_row.add_child(make_icon("hammer"))
	var build_label = Label.new()
	build_label.text = "建設:"
	stats_row.add_child(build_label)
	mode_select = OptionButton.new()
	mode_select.custom_minimum_size.x = 270 * UI_SCALE
	for group in world.MODE_GROUPS:
		mode_select.add_separator(group.name)
		for mode in menu_modes(group):
			mode_select.add_item(get_mode_label(mode))
			mode_select.set_item_metadata(mode_select.item_count - 1, mode)
	mode_select.item_selected.connect(func(index): world.select_mode(mode_select.get_item_metadata(index)))
	for type in world.BUILDINGS:
		if type == Buildings.RUIN_TYPE:
			continue # 焼け跡は火災・爆破で残るもので、メニューからは建てない
		assert(world.MODE_GROUPS.any(func(group): return group.modes.has(type)), "%s が建設メニュー（world.MODE_GROUPS）にありません" % type)
	stats_row.add_child(mode_select)
	
	# 経路（人の通り道）の表示。人が増えると線だらけになるので、既定はオフ
	route_button = Button.new()
	route_button.custom_minimum_size.x = 100 * UI_SCALE
	route_button.icon = icon_texture("route")
	route_button.pressed.connect(func(): world.toggle_routes())
	stats_row.add_child(route_button)
	update_route_button()
	# 上部バーのボタンは、押してもキーの入力を奪わない（スペースキーの一時停止などがボタンに取られないように）
	for control in [stats_button, pause_button, speed_button, mode_select, route_button]:
		control.focus_mode = Control.FOCUS_NONE
	stats_row.add_child(make_spacer())
	
	# --- はじめての案内（上部バーの下。文字フォントに合わせたコンパクトなパネル） ---
	var tutorial_row = HBoxContainer.new()
	tutorial_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(tutorial_row)
	var tutorial_box = HBoxContainer.new()
	tutorial_box.add_theme_constant_override("separation", 12 * UI_SCALE)
	tutorial_label = Label.new()
	tutorial_label.add_theme_color_override("font_color", Color(0.65, 0.95, 1.0))
	tutorial_label.add_theme_font_size_override("font_size", 13 * UI_SCALE)
	tutorial_box.add_child(tutorial_label)
	var skip_button = Button.new()
	skip_button.text = "案内を閉じる"
	skip_button.add_theme_font_size_override("font_size", 12 * UI_SCALE)
	skip_button.pressed.connect(func(): world.tutorial_system.skip())
	tutorial_box.add_child(skip_button)
	tutorial_panel = make_bar(tutorial_box)
	tutorial_panel.visible = false
	tutorial_row.add_child(tutorial_panel)
	tutorial_row.add_child(make_spacer())
	
	# --- 色分け表示の凡例（上部バーの下、左寄せ。色分けを出している間だけ） ---
	var overlay_row = HBoxContainer.new()
	overlay_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(overlay_row)
	overlay_label = RichTextLabel.new()
	overlay_label.bbcode_enabled = true
	overlay_label.fit_content = true
	overlay_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	overlay_label.scroll_active = false
	overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_label.add_theme_font_size_override("normal_font_size", 13 * UI_SCALE)
	overlay_panel = make_bar(overlay_label)
	overlay_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_panel.visible = false
	overlay_row.add_child(overlay_panel)
	overlay_row.add_child(make_spacer())

	# --- 操作説明（上部バーの下、右寄せ） ---
	var help_row = HBoxContainer.new()
	help_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(help_row)
	help_row.add_child(make_spacer())
	var help_label = RichTextLabel.new()
	help_label.bbcode_enabled = true
	help_label.fit_content = true
	help_label.scroll_active = false # スクロールは外側の ScrollContainer に任せる
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.custom_minimum_size = Vector2(HELP_PANEL_WIDTH, 0)
	help_label.add_theme_font_size_override("normal_font_size", 13 * UI_SCALE)
	help_label.add_theme_font_size_override("bold_font_size", 13 * UI_SCALE)
	help_label.add_theme_constant_override("line_separation", 4 * UI_SCALE) # 行の間を少しあけて読みやすくする
	help_label.text = help_text()
	var help_scroll = ScrollContainer.new()
	help_scroll.custom_minimum_size = Vector2(HELP_PANEL_WIDTH, 560) # 画面に収まる高さ。はみ出す分は上下にスクロールする
	help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	help_scroll.add_child(help_label)
	help_panel = make_bar(help_scroll)
	make_opaque(help_panel) # 後ろのビルが透けて文字が読みにくくならないように
	help_panel.visible = false
	help_panel.visibility_changed.connect(update_scroll_lock)
	help_row.add_child(help_panel)
	
	# --- ビルの状況（2段目の★を押すと開閉する） ---
	var stats_panel_row = HBoxContainer.new()
	stats_panel_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(stats_panel_row)
	stats_label = Label.new()
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	stats_panel = make_bar(stats_label)
	stats_panel.visible = false
	stats_panel_row.add_child(stats_panel)
	stats_panel_row.add_child(make_spacer())
	
	# --- メッセージの記録（⌘Lで開閉。ゲーム開始からのメッセージを全部見られる） ---
	var log_row = HBoxContainer.new()
	log_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(log_row)
	log_label = Label.new()
	log_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	log_label.add_theme_font_size_override("font_size", 13 * UI_SCALE)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	log_scroll = ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(PANEL_WIDTH, 420)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.add_child(log_label)
	log_panel = make_bar(log_scroll)
	make_opaque(log_panel)
	log_panel.visible = false
	log_panel.visibility_changed.connect(update_scroll_lock)
	log_row.add_child(log_panel)
	log_row.add_child(make_spacer())
	
	# --- 収支のグラフ（⌘Gで開閉） ---
	var chart_row = HBoxContainer.new()
	chart_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(chart_row)
	var chart_view = ChartView.new()
	chart_view.world = world
	chart_view.custom_minimum_size = Vector2(620 * UI_SCALE, 150 * UI_SCALE)
	chart_panel = make_bar(chart_view)
	chart_panel.visible = false
	chart_row.add_child(chart_panel)
	chart_row.add_child(make_spacer())
	
	# --- マップ部分（クリックはそのまま通す）。右端に上下スクロールバー ---
	var map_row = HBoxContainer.new()
	map_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(map_row)
	map_row.add_child(make_spacer())
	v_scroll = VScrollBar.new()
	v_scroll.custom_minimum_size.x = 14 * UI_SCALE
	v_scroll.value_changed.connect(func(value): world.camera.position.y = value + v_scroll.page / 2.0)
	map_row.add_child(v_scroll)
	
	# --- 下部バー（2段） ---
	#   1段目: 操作結果のメッセージ（新しいものが下に出て、古いものは流れていく）
	#   2段目: カーソル下のマスの情報
	var bottom_rows = VBoxContainer.new()
	bottom_rows.add_theme_constant_override("separation", 2 * UI_SCALE)
	layout.add_child(make_bar(bottom_rows, false))
	
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
	hover_label.add_theme_font_size_override("font_size", 13 * UI_SCALE)
	hover_tooltip = make_tooltip_bar(hover_label)
	hover_tooltip.visible = false
	hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_tooltip.top_level = true # 画面の好きな位置に出せるようにする
	canvas.add_child(hover_tooltip)
	
	update_mode_select()

# ---------------------------------------------------
# 操作説明（F1・H）の中身。見出しごとに分け、項目名は太字、押すキーは色を付けて見つけやすくする
# ---------------------------------------------------
const HELP_HEADING_COLOR := "#ffd966" # 見出し（金色）
const HELP_KEY_COLOR := "#9fd8ff"     # 押すキー・ボタン（水色）
const HELP_SECTIONS := [
	["はじめに", [
		["ゲームの目的", "更地にロビーを建てて、オフィスや店を入れ、エレベーターを工夫してビルの評価（★）を上げる。最後は★5の「タワー完成」をめざす"],
		["1階", "ロビー専用（ロビー・階段・エレベーターだけ建てられる）。まずロビーを建てないと、誰もビルに来ない"],
		["入口", "1階のフロアの左端と右端・地下鉄駅・地下駐車場の4種類。人は一番近い入口から出入りする"],
		["お金", "単位は Cr（クレジット）。毎日0時に決算して、収入から維持費を引いた分が資金に入る"],
	]],
	["操作", [
		["建てる", "上の「建設」メニューで選び、マップを[key]左クリック[/key]。建てる大きさはカーソルの枠でわかる。[key]ドラッグ[/key]で続けて建てられる"],
		["撤去", "[key]右クリック[/key]（またはメニューの「撤去」で左クリック）。建物のどのマスでも建物ごと撤去。撤去費用がかかる（建設費の1割・最低2,000Cr）"],
		["取り消し", "[key]⌘Z[/key] で直前の建設・撤去を1つずつ戻す（払ったお金も戻る。その日の決算までの操作だけ）"],
		["一時停止", "[key]スペース[/key] または上部バーの ⏸ ボタン。止めている間も建設・撤去・カメラの移動はできる"],
		["速さ", "上部バーの速さのボタンで 1x → 4x → 16x と切り替わる"],
		["カメラ", "[key]マウスホイール[/key]で上下、[key]Shift＋ホイール[/key]で左右、[key]2本指スクロール[/key]・[key]中ボタンドラッグ[/key]・[key]WASD[/key]・[key]矢印キー[/key]でも動く"],
		["ズーム", "[key]⌘＋ホイール[/key]・[key]ピンチ[/key]・[key]⌘+[/key] / [key]⌘-[/key]（[key]⌘0[/key] でもとの大きさ）"],
	]],
	["画面とショートカット", [
		["ビルの状況", "上部バーの★を押すと、人口・次の★の条件・目標・テナントの様子が出る。気をつけることがあると★の横に ⚠ と件数"],
		["色分け表示", "[key]V[/key] で ストレス → 騒音 → エレベーター待ち → 消す と切り替わる。どこが混んでいるか・うるさいかがひと目でわかる"],
		["経路", "[key]R[/key] または上部バーの「経路」ボタンで、人が通る道すじを線で出す"],
		["セーブ", "[key]⌘S[/key] で3つの枠から選んで保存、[key]⌘O[/key] で読み込み。毎日0時の決算のあとには自動でオートセーブ"],
		["そのほか", "[key]⌘L[/key] メッセージの記録 / [key]⌘G[/key] 収支のグラフ / [key]M[/key] 音のオン・オフ / [key]F1[/key]・[key]H[/key] この説明 / [key]Esc[/key] 開いているパネルを閉じる"],
	]],
	["建物のルール", [
		["建てる場所", "クリックしたマスを左端に、建物の横幅ぶんを使う。下の階に建物がないと建てられない（地下は上の階から掘り進める）"],
		["建て替え", "建物の上に直接ほかの建物は建てられない。先に撤去する（空きフロアの上には、そのまま建てられる）"],
		["空きフロア", "骨組みだけのフロア（10,000Cr）。すき間を埋められ、人は通り抜けられる。上の階が残っているマスを撤去したときにも残る"],
		["焼け跡", "火災や爆発で壊れた部屋。上の階は支えたままだが、建て直すには先に撤去する"],
		["特別な階", "スカイロビーは15階・30階・45階…だけ、地下鉄駅は地下5階より深いところだけ、展望台・ヘリポート・屋上庭園は屋上だけ"],
	]],
	["エレベーターと移動", [
		["エレベーター", "縦に並べるとシャフトになる。カゴの定員は8人。シャフトをクリックするとその階にカゴを呼ぶ"],
		["カゴ追加", "シャフトをクリックして、その階にカゴを1台足す（1本に4台まで・維持費3,000Cr/日）"],
		["種類", "急行（1階とスカイロビーだけに停まる）・大型（横2マス・定員16人・速さ1.5倍）・サービス（清掃員と警備員だけ）"],
		["設定", "「待機階を設定」「稼働時間帯」「VIP専用」を選んでシャフトをクリック（どれも無料）"],
		["階段・エスカレーター", "近い階の移動に。エスカレーターは待ち時間がなく、階段より楽"],
	]],
	["テナントと人", [
		["オフィス", "平日8〜9時に社員が出勤し、17〜18時に帰る（1マスに1人）。「家賃」で 普通 → 高い → 安い と切り替えられる。高い階ほど賃料が高い（5階ごとに1割・最大2倍。地下は0.8倍）"],
		["ホテル", "17〜21時に客が来て泊まり、翌朝7〜10時に宿泊料を払って帰る。ハウスキーパー室の清掃員が掃除するまで次の客は泊まれない"],
		["店と映画館", "飲食店は社員の昼食と外の客、ショップ・ファストフード・展望台は外の客、映画館は上映時刻に客が一斉に来る"],
		["住宅", "入居すると販売収入が入る（1回だけ）。騒音にとても敏感で、評価が悪い日が続くと退去して返金になる"],
		["ストレス", "エレベーターを待つとたまり、顔が ピンク → 赤 → 赤く点滅（激怒）と変わる。テナントの評価が悪い日が3日続くと退去する"],
		["騒音", "飲食店・映画館・ロビーなどのまわりに広がり、住宅と客室の評価を下げる"],
	]],
	["お金と評価", [
		["収入と支出", "賃料・宿泊料・売上・入場料 − 維持費 − ゴミの外部委託費。★が1つ上がるごとに賃料と宿泊料が25%増える"],
		["★の条件", "★2: 人口50・警備室 / ★3: 人口120・メディカルセンター・ゴミ処理場 / ★4: 人口250・地下鉄駅・VIPの宿泊 / ★5: 人口500・展望台・結婚式場"],
		["人口", "通勤できる社員 ＋ 客室の定員 ＋ 住宅の入居者"],
		["ゴミと衛生", "ゴミ処理場が足りないとビルが汚れ、全テナントの評価が下がる。続くとゴキブリが出る"],
	]],
	["事件とイベント", [
		["火災", "★2以上でときどき出火し、上下左右のテナントへ燃え広がる。警備員とヘリポートの消防ヘリが消す"],
		["爆破予告", "★3以上で資金の多いビルに届く。身代金を払うか、警備員に探させる（見つからないと、まわりの階ごと吹き飛ぶ）"],
		["VIP", "★4の条件がそろうと来館し、スイートに一泊。ストレス30以下で帰れば合格"],
		["頼みごと", "ときどきテナントが困りごとを頼んでくる（部屋の上に「!」）。3日以内にかなえるとお礼、かなえないと評価が下がる"],
		["季節のにぎわい", "お正月・ゴールデンウィーク・お盆休み・クリスマスは、店・展望台・映画館のお客さんが1.5〜2倍に増える"],
		["そのほか", "地下を掘ると埋蔵金が見つかることがある。天気（6月は梅雨）や曜日（土日は休日）でお客さんの数が変わる"],
	]],
]

# 見出しごとに、左の列に項目名・右の列に説明を並べた表にする（説明が折り返しても、項目名の列にはみ出さない）
func help_text() -> String:
	var parts: Array[String] = []
	for section in HELP_SECTIONS:
		parts.append("[font_size=%d][color=%s][b]■ %s[/b][/color][/font_size]" % [15 * UI_SCALE, HELP_HEADING_COLOR, section[0]])
		var table := "[table=2]"
		for item in section[1]:
			var body: String = item[1].replace("[key]", "[color=%s]" % HELP_KEY_COLOR).replace("[/key]", "[/color]")
			table += "[cell padding=%d,%d,%d,%d][b]%s[/b][/cell]" % [12 * UI_SCALE, 2 * UI_SCALE, 12 * UI_SCALE, 2 * UI_SCALE, item[0]]
			table += "[cell expand=1 padding=0,%d,0,%d]%s[/cell]" % [2 * UI_SCALE, 2 * UI_SCALE, body]
		parts.append(table + "[/table]")
	return "\n".join(parts)

# 吹き出し（Tips）の見た目: 角の丸い濃い色の板（建設メニューなどにカーソルを合わせたときの説明にも使う）
func tooltip_style() -> StyleBoxFlat:
	var style := rounded_style(Color(0.1, 0.1, 0.13, 0.94), 6)
	style.set_content_margin_all(5 * UI_SCALE)
	style.content_margin_left = 10 * UI_SCALE
	style.content_margin_right = 10 * UI_SCALE
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(UI_SCALE)
	return style

# 吹き出し（Tips）用の文字フォントに合わせた背景矩形を作る
func make_tooltip_bar(content: Control) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", tooltip_style())
	panel.add_child(content)
	return panel

# 半透明の背景を持つバーを作る（中身をcontentとして入れる）
# 操作説明・メッセージの記録を開いている間は、スクロールで後ろの画面を動かさない
#（スクロールで動くのは開いている欄だけ。一番下まで行った後の2本指スクロールが後ろに届かないように）
func update_scroll_lock() -> void:
	world.camera.scroll_locked = help_panel.visible or log_panel.visible

# 上部バーの地: 濃い紺に、下の縁だけ金色の線を引いて影を落とす
func top_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BAR_COLOR
	style.border_width_bottom = 2 * UI_SCALE
	style.border_color = BAR_ACCENT
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 3 * UI_SCALE
	style.set_content_margin_all(5 * UI_SCALE)
	style.content_margin_left = 12 * UI_SCALE
	style.content_margin_right = 12 * UI_SCALE
	return style

# 上部バーのボタンと建設メニューの見た目（角の丸い濃い色。カーソルを合わせると明るくなる）
func button_theme() -> Theme:
	var theme := Theme.new()
	var states := {"normal": BUTTON_COLOR, "hover": BUTTON_HOVER_COLOR, "pressed": BUTTON_PRESSED_COLOR,
		"focus": Color(0, 0, 0, 0), "disabled": BUTTON_PRESSED_COLOR}
	for type in ["Button", "OptionButton"]:
		for state in states:
			var style := rounded_style(states[state], 5)
			if state == "focus":
				style.draw_center = false
			else:
				style.border_width_bottom = 2 * UI_SCALE # 下の縁を少し暗くして、押せるボタンに見せる
				style.border_color = states[state].darkened(0.35)
			style.content_margin_left = 10 * UI_SCALE
			style.content_margin_right = 10 * UI_SCALE
			theme.set_stylebox(state, type, style)
		theme.set_constant("h_separation", type, 6 * UI_SCALE)
	# 上部バーのボタンにカーソルを合わせたときの説明（Tips）も、角の丸い板にする（このテーマが外側のテーマより優先されるため）
	theme.set_stylebox("panel", "TooltipPanel", tooltip_style())
	theme.set_font_size("font_size", "TooltipLabel", 12 * UI_SCALE)
	return theme

func rounded_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius * UI_SCALE
	style.corner_radius_top_right = radius * UI_SCALE
	style.corner_radius_bottom_left = radius * UI_SCALE
	style.corner_radius_bottom_right = radius * UI_SCALE
	style.set_content_margin_all(3 * UI_SCALE)
	return style

# 資金・日付を囲む、うっすら明るい角丸の札
func make_chip(content: Control) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := rounded_style(CHIP_COLOR, 6)
	style.content_margin_left = 10 * UI_SCALE
	style.content_margin_right = 12 * UI_SCALE
	chip.add_theme_stylebox_override("panel", style)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE # 札の上のクリックはバーが受け止める
	chip.add_child(content)
	return chip

# 気をつけることがあるときは、★のボタンをオレンジの縁で囲む
func set_warning_outline(button: Button, on: bool) -> void:
	if not on:
		for state in ["normal", "hover", "pressed"]:
			button.remove_theme_stylebox_override(state)
		return
	for state in ["normal", "hover", "pressed"]:
		var style := rounded_style(BUTTON_HOVER_COLOR if state == "hover" else BUTTON_COLOR, 5)
		style.set_border_width_all(2 * UI_SCALE)
		style.border_color = WARNING_COLOR
		button.add_theme_stylebox_override(state, style)

# ドット絵のアイコン（ICONS の絵を ICON_DOT 倍に拡大した画像）
var icon_cache := {}
func icon_texture(name: String) -> ImageTexture:
	if icon_cache.has(name):
		return icon_cache[name]
	var rows: Array = ICONS[name]
	var image := Image.create(rows[0].length() * ICON_DOT, rows.size() * ICON_DOT, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			var ch: String = rows[y][x]
			if ch != ".":
				image.fill_rect(Rect2i(x * ICON_DOT, y * ICON_DOT, ICON_DOT, ICON_DOT), ICON_COLORS[ch])
	icon_cache[name] = ImageTexture.create_from_image(image)
	return icon_cache[name]

func make_icon(name: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = icon_texture(name)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

# 色分け表示の凡例（色の見方）。色分けを消しているときは隠す
func update_overlay_legend() -> void:
	overlay_panel.visible = world.overlay != ""
	var overlay = world.grid_overlay
	var swatch := func(color: Color, text: String) -> String:
		return "[color=#%s]■[/color] %s" % [Color(color, 1.0).to_html(false), text]
	match world.overlay:
		"stress":
			overlay_label.text = "色分け: ストレス（テナントの評価）  %s  %s  %s  %s  （Vで次へ）" % [
				swatch.call(overlay.HEAT_GOOD, "良い"), swatch.call(overlay.HEAT_NORMAL, "普通"),
				swatch.call(overlay.HEAT_BAD, "悪い"), swatch.call(overlay.HEAT_VACANT, "空室")]
		"noise":
			overlay_label.text = "色分け: 騒音  %s  %s  （Vで次へ）" % [
				swatch.call(overlay.NOISE_LOW, "少しうるさい"), swatch.call(overlay.NOISE_HIGH, "とてもうるさい")]
		"wait":
			overlay_label.text = "色分け: エレベーター待ち（数字は待っている人数）  %s  %s  %s  （Vで消す）" % [
				swatch.call(Color(1.0, 0.85, 0.2), "%d人まで" % (overlay.WAIT_BUSY - 1)),
				swatch.call(Color(1.0, 0.55, 0.15), "%d人から" % overlay.WAIT_BUSY), swatch.call(Color(1.0, 0.2, 0.2), "%d人から" % overlay.WAIT_JAM)]

# 一時停止のボタン: 動いている間は「⏸」のアイコン、止めている間は「▶」のアイコンとオレンジの枠
func update_pause_button() -> void:
	if not pause_button:
		return
	pause_button.icon = icon_texture("play" if world.paused else "pause")
	set_warning_outline(pause_button, world.paused)

# 速さのボタンのアイコン（1x は▶1つ、4x は2つ、16x は3つ）
func update_speed_icon(speed: int) -> void:
	if speed_button:
		speed_button.icon = icon_texture("speed%d" % clampi(world.SPEEDS.find(speed) + 1, 1, 3))

# 文字をたくさん読むパネルは、背景をほぼ不透明にする
func make_opaque(panel: PanelContainer) -> void:
	var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = Color(0.08, 0.09, 0.12)
	style.border_color = Color(1, 1, 1, 0.1)
	style.set_border_width_all(UI_SCALE)
	panel.add_theme_stylebox_override("panel", style)

# rounded: 角を丸めるか（画面の端から端までの下部バーは丸めない）
func make_bar(content: Control, rounded := true) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = rounded_style(Color(0.1, 0.1, 0.13, 0.9), 8 if rounded else 0)
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

var _menu_target_width: float = -1.0

func _get_menu_target_width() -> float:
	if _menu_target_width > 0.0:
		return _menu_target_width
	var font: Font = ThemeDB.fallback_font
	var font_size: int = BASE_FONT_SIZE * UI_SCALE
	var max_w: float = 0.0
	for group in world.MODE_GROUPS: # メニューに並ぶ項目のうち、名前と金額が一番長いもの
		for mode in menu_modes(group):
			var nw: float = font.get_string_size(mode_name(mode), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var cw: float = font.get_string_size(mode_price_text(mode), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			max_w = maxf(max_w, nw + cw)
	var space_w: float = font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_menu_target_width = max_w + space_w * 4
	return _menu_target_width

# 建設メニューのその見出しに並べる項目（「住人（テスト）」はテストのときだけ出す）
func menu_modes(group: Dictionary) -> Array:
	return group.modes.filter(func(mode): return mode != world.MODE_RESIDENT or world.test_tools)

func get_mode_label(mode: String) -> String:
	return priced_label(mode_name(mode), mode_price_text(mode))

# メニューに出す名前
func mode_name(mode: String) -> String:
	match mode:
		world.MODE_RESIDENT: return "住人（テスト）"
		world.MODE_ADD_CAR: return "カゴ追加"
		world.MODE_SET_HOME: return "待機階を設定"
		world.MODE_SERVICE: return "稼働時間帯"
		world.MODE_VIP_ONLY: return "VIP専用"
		world.MODE_RENT: return "家賃"
		world.MODE_DEMOLISH: return "撤去"
	return world.BUILDINGS[mode].name

# メニューの右側に出す金額（建設費。設定を変えるだけのものは「無料」）
func mode_price_text(mode: String) -> String:
	match mode:
		world.MODE_ADD_CAR:
			return world.money_text(world.elevator_system.CAR_COST)
		world.MODE_DEMOLISH:
			return world.money_text(world.MIN_DEMOLISH_FEE) + "〜" # 建物ごとに違う（建設費の1割・最低額あり）
		world.MODE_RESIDENT, world.MODE_SET_HOME, world.MODE_SERVICE, world.MODE_VIP_ONLY, world.MODE_RENT:
			return "無料"
	return world.money_text(world.BUILDINGS[mode].cost)

# 名前を左、金額を右にそろえた1行（間を空白で埋めて、金額の右端をそろえる）
func priced_label(name: String, price_text: String) -> String:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = BASE_FONT_SIZE * UI_SCALE
	var name_w: float = font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var cost_w: float = font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var space_w: float = font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var gap: float = _get_menu_target_width() - name_w - cost_w
	var num_spaces: int = maxi(int(round(gap / space_w)), 2)
	return "%s%s%s" % [name, " ".repeat(num_spaces), price_text]

# 選んだもののくわしい説明（建設メニューにカーソルを合わせると出る）
func get_mode_info(mode: String) -> String:
	if mode == world.MODE_RESIDENT:
		return "無料（テスト用。建物をクリックで住人を置き、行き先をクリック）"
	if mode == world.MODE_SET_HOME:
		return "無料（シャフトをクリックでその階を待機階に。もう一度クリックで解除）"
	if mode == world.MODE_SERVICE:
		return "無料（シャフトをクリックで 終日 → 6時〜24時 → 8時〜20時 と切り替え）"
	if mode == world.MODE_VIP_ONLY:
		return "無料（シャフトをクリックで、VIPの来館中はVIPだけが乗れるエレベーターにする。もう一度クリックで解除）"
	if mode == world.MODE_RENT:
		return "無料（オフィスをクリックで 普通 → 高い → 安い と切り替え。高いと賃料は増えるが不満も増え、空室に次のテナントが決まりにくい）"
	if mode == world.MODE_DEMOLISH:
		return "クリックした建物を撤去（撤去費用は建設費の1割・最低%s。建設費は戻らない。ドラッグで続けて撤去）" % world.money_text(world.MIN_DEMOLISH_FEE)
	if mode == world.MODE_ADD_CAR:
		return "1台 %s（シャフトをクリック。1本に%d台まで）" % [world.money_text(world.elevator_system.CAR_COST), world.elevator_system.MAX_CARS]
	var info := "建設費 %s・横%dマス" % [world.money_text(world.BUILDINGS[mode].cost), world.get_width(mode)]
	if world.get_height(mode) > 1:
		info += "・高さ%d階分" % world.get_height(mode)
	if mode == "express_elevator":
		info += "（1階とスカイロビーの階だけに停まる）"
	elif mode == Buildings.FRAME_TYPE:
		info += "（骨組みだけのフロア。上の階を支え、人は通り抜けられる）"
	elif mode == "large_elevator":
		info += "（全部の階に停まる。定員%d人・速さ1.5倍）" % ElevatorCar.LARGE_CAPACITY
	return info

# メニューバーの中身。action は選んだときに do_menu_action() で実行する処理の名前。
# check を付けた項目は、開くたびに今の状態にチェックを合わせる
const MENUS := [
	{"name": "ファイル", "items": [
		{"text": "セーブ（⌘S。3つの枠から選ぶ）", "action": "save"},
		{"text": "セーブデータの読み込み（⌘O。オートセーブからも読み込める）", "action": "load"},
	]},
	{"name": "表示", "items": [
		{"text": "ビルの状況（★を押しても開く）", "action": "stats", "check": true},
		{"text": "経路（人の通り道）（R）", "action": "routes", "check": true},
		{"text": "色分け: ストレス（V）", "action": "overlay_stress", "check": true},
		{"text": "色分け: 騒音（V）", "action": "overlay_noise", "check": true},
		{"text": "色分け: エレベーター待ち（V）", "action": "overlay_wait", "check": true},
		{"text": "メッセージの記録（⌘L）", "action": "log", "check": true},
		{"text": "収支のグラフ（⌘G）", "action": "chart", "check": true},
		{"text": "拡大（⌘+）", "action": "zoom_in"},
		{"text": "縮小（⌘-）", "action": "zoom_out"},
		{"text": "もとの大きさ（⌘0）", "action": "zoom_reset"},
	]},
	{"name": "ゲーム", "items": [
		{"text": "取り消し（⌘Z）", "action": "undo"},
		{"text": "一時停止（スペース）", "action": "pause", "check": true},
		{"text": "速さを切り替える", "action": "speed"},
		{"text": "音を出す（M）", "action": "mute", "check": true},
	]},
	{"name": "ヘルプ", "items": [
		{"text": "操作説明（F1）", "action": "help", "check": true},
	]},
]

# メニューバーを組み立てる
func build_menu_bar() -> MenuBar:
	var bar := MenuBar.new()
	bar.prefer_global_menu = true # macOSでは画面最上部のメニューバーに出す
	for menu in MENUS:
		var popup := PopupMenu.new()
		popup.name = menu.name
		for item in menu.items:
			popup.add_item(item.text)
		popup.id_pressed.connect(func(index): do_menu_action(menu.items[index].action))
		popup.about_to_popup.connect(func(): update_menu_checks(popup, menu.items))
		bar.add_child(popup)
	return bar

# メニューを開いたときに、今の状態をチェックマークで示す
func update_menu_checks(popup: PopupMenu, items: Array) -> void:
	for i in items.size():
		if items[i].get("check", false):
			popup.set_item_as_checkable(i, true)
			popup.set_item_checked(i, is_menu_on(items[i].action))

# その項目が今オンか（チェックマークを付けるか）
func is_menu_on(action: String) -> bool:
	match action:
		"stats": return stats_panel.visible
		"routes": return world.show_routes
		"log": return log_panel.visible
		"chart": return chart_panel.visible
		"help": return help_panel.visible
		"mute": return not world.audio_system.muted
		"pause": return world.paused
	if action.begins_with("overlay_"):
		return world.overlay == action.trim_prefix("overlay_")
	return false

# メニューを選んだときの処理。ショートカットと同じことをする
func do_menu_action(action: String) -> void:
	match action:
		"save":
			if world.started:
				show_save_panel("save")
		"load": show_save_panel("load")
		"stats": toggle_stats_panel()
		"routes": world.toggle_routes()
		"log":
			log_panel.visible = not log_panel.visible
			if log_panel.visible:
				update_log_panel()
		"chart": chart_panel.visible = not chart_panel.visible
		"zoom_in": world.camera.zoom_by(world.camera.KEY_ZOOM_STEP)
		"zoom_out": world.camera.zoom_by(1.0 / world.camera.KEY_ZOOM_STEP)
		"zoom_reset": world.camera.reset_zoom()
		"speed": world.set_speed(world.next_speed())
		"pause": world.toggle_pause()
		"overlay_stress", "overlay_noise", "overlay_wait":
			var mode := action.trim_prefix("overlay_")
			world.set_overlay("" if world.overlay == mode else mode) # 出しているものをもう一度選ぶと消す
		"undo":
			if world.started:
				world.undo()
		"mute": world.audio_system.toggle_mute()
		"help": help_panel.visible = not help_panel.visible

# ビルの状況（★を押すと開くパネル）の中身
func update_stats_panel(warning_list: Array[String]) -> void:
	var lines: Array[String] = [world.rating_system.get_status_text(), world.goal_system.get_goal_text()]
	lines.append("社員: 在館 %d / 全 %d人" % [world.commute_system.count_in_building(), world.commute_system.workers.size()])
	var tenants = world.tenant_system
	if tenants.count_rating(tenants.Rating.GOOD) + tenants.count_rating(tenants.Rating.NORMAL) \
			+ tenants.count_rating(tenants.Rating.BAD) + tenants.count_vacant() > 0:
		lines.append("オフィス: 良い%d・普通%d・悪い%d・空室%d" % [
			tenants.count_rating(tenants.Rating.GOOD), tenants.count_rating(tenants.Rating.NORMAL),
			tenants.count_rating(tenants.Rating.BAD), tenants.count_vacant()])
	var hotel = world.hotel_system
	if hotel.rooms.size() > 0:
		lines.append("客室: 宿泊 %d・清掃待ち %d・空室 %d" % [
			hotel.count_rooms(hotel.RoomState.OCCUPIED), hotel.count_rooms(hotel.RoomState.DIRTY),
			hotel.count_rooms(hotel.RoomState.CLEAN)])
	if world.vip_system.is_visiting():
		lines.append(world.vip_system.get_status_text())
	var request_text: String = world.request_system.get_status_text()
	if request_text != "":
		lines.append(request_text)
	var season_text: String = world.visitor_system.get_season_text()
	if season_text != "":
		lines.append(season_text)
	for w in warning_list:
		lines.append("⚠ " + w)
	stats_label.text = "\n".join(lines)

# ★を押したときに、くわしい状況を開け閉めする
func toggle_stats_panel() -> void:
	stats_panel.visible = not stats_panel.visible

# 今、気をつけることの一覧（★の横に件数を出して知らせる）
func warnings() -> Array[String]:
	var list: Array[String] = []
	var angry := 0
	for r in world.residents:
		if is_instance_valid(r) and r.is_angry():
			angry += 1
	if angry > 0:
		list.append("怒っている人 %d人" % angry)
	var leaving: int = world.tenant_system.count_about_to_leave()
	if leaving > 0:
		list.append("退去しそうなテナント %d件" % leaving)
	if world.commute_system.count_unreachable() > 0:
		list.append("通勤できない社員 %d人" % world.commute_system.count_unreachable())
	if world.economy_system.pollution > 0:
		list.append("衛生の悪化 レベル%d" % world.economy_system.pollution)
	if world.incident_system.has_roaches():
		list.append(world.incident_system.get_roach_text())
	if world.incident_system.has_fire():
		list.append(world.incident_system.get_fire_text())
	if world.incident_system.has_bomb():
		list.append(world.incident_system.get_bomb_text())
	if world.request_system.request != null:
		list.append("頼みごと あと%d日" % world.request_system.days_left())
	return list

# 経路の表示ボタンの見た目を、今の設定に合わせる
func update_route_button() -> void:
	if route_button:
		route_button.text = "経路 オン" if world.show_routes else "経路 オフ"

# 建設メニューの選択と説明を、今のモードに合わせる
func update_mode_select():
	for i in mode_select.item_count:
		if mode_select.get_item_metadata(i) == world.current_mode:
			mode_select.select(i)
	mode_select.tooltip_text = get_mode_info(world.current_mode) # くわしい説明はカーソルを合わせたときに出す

# 資金の表示を更新する関数
func update_funds_display():
	if not funds_label:
		return
	funds_label.text = "資金: %s" % world.money_text(world.funds) # 金貨のアイコンがあるので「資金」だけにして、上部バーを詰める
	funds_label.add_theme_color_override("font_color", FUNDS_COLOR if world.funds >= 0 else LOSS_COLOR)
	funds_change_label.text = ""
	if world.economy_system and not world.economy_system.last_report.is_empty():
		var total: int = world.economy_system.last_report.total
		funds_change_label.text = "（前日 %s）" % world.money_text(total, true)
		funds_change_label.add_theme_color_override("font_color", GAIN_COLOR if total >= 0 else LOSS_COLOR)

func update_scrollbar():
	var tile_h: float = world.tile_map.tile_set.tile_size.y
	var top_row: int = world.ground_y
	var bottom_row: int = world.ground_y
	for cell: Vector2i in world.building_grid:
		top_row = mini(top_row, cell.y)
		bottom_row = maxi(bottom_row, cell.y)
	var page: float = world.get_viewport_rect().size.y / world.camera.zoom.y # 画面に映っている高さ
	var view_top: float = world.camera.position.y - page / 2.0
	# 範囲を変えると値が範囲内に押し戻されて value_changed が出るので、合わせている間は通知を止める
	# （通知でカメラが動くと、毎フレーム少しずつカメラがずれていってしまう）
	v_scroll.set_block_signals(true)
	v_scroll.min_value = minf((top_row - world.SCROLL_MARGIN_ROWS) * tile_h, view_top)
	v_scroll.max_value = maxf((bottom_row + 1 + world.SCROLL_MARGIN_ROWS) * tile_h, view_top + page)
	v_scroll.page = page
	v_scroll.value = view_top
	v_scroll.set_block_signals(false)

# カーソル下のマスの座標と建物を、マウスの横の吹き出しに表示する
func update_hover_label():
	if not hover_label:
		return
	if not world.grid_overlay.hover_visible:
		hover_label.text = ""
		hover_tooltip.visible = false
		return
	var cell: Vector2i = world.grid_overlay.hover_cell
	var type = world.get_building_type(cell)
	var text = "%s: %s" % [world.get_floor_name(cell.y), world.BUILDINGS[type].name if type != "" else "空き"]
	if world.incident_system.has_roach_at(cell):
		if world.hotel_system.is_room_type(type):
			text += "（ゴキブリ発生中・掃除すると消える）"
		elif world.visitor_system.SHOP_TYPES.has(type):
			text += "（ゴキブリ発生中・客が減っている）"
		else:
			text += "（ゴキブリ発生中）"
	if type in world.OFFICE_TYPES:
		var rating: String = world.tenant_system.get_rating_text(cell)
		text += "（%s%s）" % [world.tenant_system.get_rent_text(cell), "・" + rating if rating != "" else ""]
	if world.hotel_system.is_room_type(type):
		var room_rating: String = world.tenant_system.get_room_rating_text(cell)
		text += "（%s%s・%s）" % [world.hotel_system.get_room_state_text(cell), "・" + room_rating if room_rating != "" else "",
			world.noise_system.get_noise_text(cell)]
	elif type == "restaurant" or type == "fastfood":
		text += "（客 %d人）" % (world.commerce_system.count_eating_at(cell) + world.visitor_system.count_at_shop(cell))
	elif type == "shop":
		text += "（客 %d人）" % world.visitor_system.count_at_shop(cell)
	elif type == "observatory":
		text += "（観光客 %d人・入場料 %s）" % [world.visitor_system.count_at_shop(cell), world.money_text(world.visitor_system.SHOP_TYPES.observatory.price)]
	elif type == "cinema":
		text += "（%s）" % world.visitor_system.get_cinema_text(cell)
	elif world.event_system.is_hall_type(type):
		text += "（来客 %d人）" % world.event_system.count_at_hall(cell)
	elif world.elevator_system.is_shaft_type(type):
		var cars: Array = world.elevator_system.get_cars_at(cell)
		if type == "express_elevator" and not world.is_express_stop_floor(cell.y):
			text += "（この階には停まりません）"
		elif not cars.is_empty():
			if world.elevator_system.get_home(cell) == cell.y:
				text += "（待機階）"
			if world.elevator_system.is_vip_only(cell):
				text += "（VIP専用%s）" % ("・VIPを案内中" if world.vip_system.is_arriving() else "")
			var service: Dictionary = world.elevator_system.get_service(cell)
			if service.name != "終日":
				text += "（稼働 %s%s）" % [service.name, "" if cars[0].in_service else "・今は停止中"]
			var loads: Array[String] = []
			for car in cars:
				loads.append("%d/%d" % [car.passengers.size(), car.capacity])
			text += "（カゴ%d台: %s人）" % [cars.size(), "・".join(loads)]
	elif type == "housing":
		var home_rating: String = world.tenant_system.get_home_rating_text(cell)
		text += "（%s%s・%s）" % [world.housing_system.get_home_state_text(cell), "・" + home_rating if home_rating != "" else "",
			world.noise_system.get_noise_text(cell)]
	elif type == Buildings.RUIN_TYPE:
		text += "（撤去してから建て直せる。撤去費用 %s）" % world.money_text(world.demolish_fee(type))
	elif type == "parking":
		text += "（%s）" % world.parking_system.get_parking_text(cell)
	elif type == "ramp":
		text += "（%s）" % ("車が下りてこられます" if world.parking_system.is_ramp_connected(cell)
			else "上の階のスロープが足りないので、車が下りてこられません")
	elif type == "garden":
		text += "（ストレスの回復 %.1f倍・騒音をやわらげる）" % world.stress_recover_rate()
	elif type == "medical":
		text += "（ビル全体のストレスの回復 %.1f倍）" % world.stress_recover_rate()
	elif type == "recycling":
		text += "（ビル全体の処理能力 %d/日）" % world.economy_system.recycling_capacity()
	var request_text: String = world.request_system.get_cell_text(cell)
	if request_text != "":
		text += "（%s）" % request_text # このテナントが頼みごとをしている
	var resident = world.get_resident_at(cell)
	if resident:
		text += " / 住人のストレス: %d" % int(resident.stress)
	hover_label.text = text
	show_tooltip(cell)

# 吹き出しを、マウスの右下に出す（画面からはみ出すときは左や上に寄せる）。
# 空きマスのときは出さない（建物や人がいるマスだけ）
func show_tooltip(cell: Vector2i) -> void:
	hover_tooltip.visible = not world.is_cell_empty(cell) or world.get_resident_at(cell) != null
	if not hover_tooltip.visible:
		return
	hover_tooltip.reset_size()
	var offset := Vector2(12, 12) * UI_SCALE
	var size := hover_tooltip.get_combined_minimum_size()
	var screen: Vector2 = world.get_viewport_rect().size
	var pos: Vector2 = world.grid_overlay.hover_screen_pos + offset
	if pos.x + size.x > screen.x:
		pos.x = world.grid_overlay.hover_screen_pos.x - size.x - offset.x
	if pos.y + size.y > screen.y:
		pos.y = world.grid_overlay.hover_screen_pos.y - size.y - offset.y
	hover_tooltip.position = pos.clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))

func update_log_panel() -> void:
	log_label.text = "\n".join(world.message_log)
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

# ---------------------------------------------------
# タイトル画面: 「はじめから」で更地から、「続きから」でセーブデータから始める。
# 始まるまでは時計を止めて、マップの操作も受け付けない。
# ---------------------------------------------------
func build_title() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 2 # ほかのUIより手前に出す
	add_child(canvas)
	var back = ColorRect.new()
	back.color = Color(0.06, 0.07, 0.12, 0.92)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(back)
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # 画面いっぱいに広げて、中身を真ん中にそろえる
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12 * UI_SCALE)
	var theme := Theme.new()
	theme.default_font_size = BASE_FONT_SIZE * UI_SCALE
	box.theme = theme
	back.add_child(box)
	
	var title = Label.new()
	title.text = "ProjectTower"
	title.add_theme_font_size_override("font_size", 48 * UI_SCALE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle = Label.new()
	subtitle.text = "更地から始めて、テナントを入れ、エレベーターを工夫して、ビルの評価（★）を上げよう"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	
	var new_button = Button.new()
	new_button.text = "はじめから"
	new_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	new_button.custom_minimum_size.x = 320 * UI_SCALE
	new_button.pressed.connect(func(): world.start_game())
	box.add_child(new_button)
	var continue_button = Button.new()
	continue_button.text = "続きから（セーブデータを読み込む）"
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.custom_minimum_size.x = 320 * UI_SCALE
	continue_button.disabled = not world.save_system.has_save()
	continue_button.pressed.connect(func(): show_save_panel("load")) # 読み込む枠を選ぶ
	box.add_child(continue_button)
	var hint = Label.new()
	hint.text = "遊び方は F1（操作説明）。⌘S で保存、⌘O で読み込み（毎日0時に自動でも保存）、M で音のオン・オフ"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	title_panel = back
	build_goal_panel(canvas, theme)
	build_ransom_panel(canvas, theme)
	build_save_panel(canvas, theme) # タイトル画面の「続きから」でも使うので、タイトル画面より手前に作る

# セーブ・読み込みの枠を選ぶ画面を作る（中身は開くたびに作り直す）
func build_save_panel(canvas: CanvasLayer, theme: Theme) -> void:
	var back = ColorRect.new()
	back.color = Color(0.06, 0.07, 0.12, 0.9)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.visible = false
	canvas.add_child(back)
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10 * UI_SCALE)
	box.theme = theme
	back.add_child(box)
	save_title = Label.new()
	save_title.add_theme_font_size_override("font_size", 28 * UI_SCALE)
	save_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(save_title)
	save_rows = VBoxContainer.new()
	save_rows.add_theme_constant_override("separation", 8 * UI_SCALE)
	save_rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(save_rows)
	var close = Button.new()
	close.text = "閉じる（Esc）"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size.x = 240 * UI_SCALE
	close.pressed.connect(func(): save_panel.visible = false)
	box.add_child(close)
	save_panel = back

# 枠を選ぶ画面を開く。mode: "save" は保存する枠（1〜3）、"load" は読み込む枠（オートセーブと1〜3）
func show_save_panel(mode: String) -> void:
	save_mode = mode
	var saves = world.save_system
	save_title.text = "どの枠にセーブしますか？" if mode == "save" else "どのセーブデータを読み込みますか？"
	for row in save_rows.get_children():
		row.queue_free()
	var first: int = 1 if mode == "save" else saves.AUTOSAVE_SLOT
	for slot in range(first, saves.SLOT_COUNT + 1):
		var info: Dictionary = saves.slot_info(slot)
		var button = Button.new()
		button.custom_minimum_size.x = 720 * UI_SCALE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s: %s" % [saves.slot_name(slot), slot_summary(info)]
		if slot == saves.AUTOSAVE_SLOT:
			button.text += "（毎日0時の決算のあとに自動で保存）"
		button.disabled = mode == "load" and info.is_empty() # 空の枠は読み込めない
		button.pressed.connect(func(): choose_save_slot(slot))
		save_rows.add_child(button)
	save_panel.visible = true

# 枠のボタンに出す要約（空なら「空き」）
func slot_summary(info: Dictionary) -> String:
	if info.is_empty():
		return "（空き）"
	var text := "%s・★%d・資金 %s" % [info.date, info.stars, world.money_text(info.funds)]
	if info.saved_at != "":
		text += "（保存 %s）" % info.saved_at.substr(0, 16).replace("T", " ")
	return text

# 枠を選んだとき: 保存する、または読み込む（タイトル画面からなら、ゲームを始めてから読み込む）
func choose_save_slot(slot: int) -> void:
	save_panel.visible = false
	if save_mode == "save":
		world.save_system.save_slot(slot)
		return
	if not world.started:
		world.start_game()
	world.save_system.load_slot(slot)

# 爆破予告の身代金を払うか決める画面を作る（中身はそのつど差し替える）
func build_ransom_panel(canvas: CanvasLayer, theme: Theme) -> void:
	var back = ColorRect.new()
	back.color = Color(0.18, 0.03, 0.04, 0.9) # 赤黒い背景で、ただごとでないことを伝える
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.visible = false
	canvas.add_child(back)
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12 * UI_SCALE)
	box.theme = theme
	back.add_child(box)
	var title = Label.new()
	title.text = "爆破予告！"
	title.add_theme_font_size_override("font_size", 32 * UI_SCALE)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	ransom_text = Label.new()
	ransom_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ransom_text)
	ransom_pay_button = Button.new()
	ransom_pay_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ransom_pay_button.custom_minimum_size.x = 420 * UI_SCALE
	ransom_pay_button.pressed.connect(func(): world.incident_system.pay_ransom())
	box.add_child(ransom_pay_button)
	ransom_refuse_button = Button.new()
	ransom_refuse_button.text = "支払わない（警備員に爆弾を探させる）"
	ransom_refuse_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ransom_refuse_button.custom_minimum_size.x = 420 * UI_SCALE
	ransom_refuse_button.pressed.connect(func(): world.incident_system.refuse_ransom())
	box.add_child(ransom_refuse_button)
	ransom_panel = back

# 身代金の画面を出す。払えるだけの資金がないときは「支払う」を押せない
func show_ransom_panel(ransom: int, can_pay: bool) -> void:
	ransom_text.text = "テロリストから電話です。\n「ビルのどこかに爆弾を仕掛けた。身代金 %s を払え」\n\n支払わない場合、警備員が手分けして探します。%d分以内に見つけて解体できなければ爆発します。" \
		% [world.money_text(ransom), int(world.incident_system.BOMB_LIMIT)]
	ransom_pay_button.text = "支払う（%s）" % world.money_text(ransom) if can_pay else "支払う（資金が足りません）"
	ransom_pay_button.disabled = not can_pay
	ransom_panel.visible = true

func hide_ransom_panel() -> void:
	if ransom_panel:
		ransom_panel.visible = false

# 目標を達成したときの画面を作る（中身はそのつど差し替える）
func build_goal_panel(canvas: CanvasLayer, theme: Theme) -> void:
	var back = ColorRect.new()
	back.color = Color(0.06, 0.07, 0.12, 0.88)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.visible = false
	canvas.add_child(back)
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12 * UI_SCALE)
	box.theme = theme
	back.add_child(box)
	goal_title = Label.new()
	goal_title.add_theme_font_size_override("font_size", 32 * UI_SCALE)
	goal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(goal_title)
	goal_text = Label.new()
	goal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(goal_text)
	var close_button = Button.new()
	close_button.text = "つづける"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.custom_minimum_size.x = 240 * UI_SCALE
	close_button.pressed.connect(func(): goal_panel.visible = false)
	box.add_child(close_button)
	goal_panel = back

# 目標の達成などを画面で知らせる（時間は止めずに、ボタンで閉じる）
func show_goal_panel(title: String, text: String) -> void:
	goal_title.text = title
	goal_text.text = text
	goal_panel.visible = true
	world.show_message("%s %s" % [title, text.replace("\n", " ")])

# タイトル画面を閉じる
func hide_title() -> void:
	if title_panel:
		title_panel.visible = false


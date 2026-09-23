extends Control

# ---------------------------------------------------
# 収支のグラフ（⌘Gで開く）：最近の決算の合計を、日ごとの棒グラフで表す。
#   0の線より上（緑）が黒字、下（赤）が赤字。棒の高さは、その期間の一番大きい額に合わせる。
#   下に、いちばん新しい決算の内わけ（賃料・宿泊料・飲食…）を出す。
# ---------------------------------------------------

const PLUS_COLOR := Color(0.35, 0.85, 0.45)
const MINUS_COLOR := Color(0.95, 0.4, 0.35)
const LINE_COLOR := Color(1, 1, 1, 0.35)
const TEXT_COLOR := Color(0.9, 0.92, 0.95)
const BAR_GAP := 2.0 # 棒と棒のすきま（px）

var world: Node2D # main.gd

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var history: Array = world.economy_system.history
	if history.is_empty():
		draw_string(font, Vector2(8, font_size + 8), "まだ決算がありません（0時になると1日目の決算が出ます）", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)
		return
	# グラフの範囲（下に内わけの行を出すぶんの余白を残す）
	var chart := Rect2(Vector2(8, 8), Vector2(size.x - 16, size.y - font_size * 4.0))
	var peak := 1.0
	for report in history:
		peak = maxf(peak, absf(report.total))
	peak *= 1.2 # 棒の上に少し余白を残す
	var zero_y: float = chart.position.y + chart.size.y / 2.0
	var bar_width: float = chart.size.x / history.size()
	for i in history.size():
		var report: Dictionary = history[i]
		# 目盛りの文字と重ならないよう、棒の高さは半分の高さから文字1行ぶんを引いた範囲に収める
		var height: float = (absf(report.total) / peak) * (chart.size.y / 2.0 - font_size * 1.2)
		var x: float = chart.position.x + bar_width * i
		var color := PLUS_COLOR if report.total >= 0 else MINUS_COLOR
		var top: float = zero_y - height if report.total >= 0 else zero_y
		draw_rect(Rect2(x + BAR_GAP / 2.0, top, maxf(bar_width - BAR_GAP, 1.0), height), color)
	# 0の線と目盛り（棒の上に描く。目盛りは右端に寄せて、棒と重ならないようにする）
	draw_line(Vector2(chart.position.x, zero_y), Vector2(chart.end.x, zero_y), LINE_COLOR, 1.0)
	var top_label := "+%s" % world.money_text(int(peak / 1.2))
	draw_string(font, Vector2(chart.position.x, chart.position.y + font_size), top_label,
		HORIZONTAL_ALIGNMENT_RIGHT, chart.size.x, font_size, TEXT_COLOR)
	draw_string(font, Vector2(chart.position.x, zero_y - 2), "0" + world.CURRENCY, HORIZONTAL_ALIGNMENT_RIGHT, chart.size.x, font_size, TEXT_COLOR)
	var first: Dictionary = history[0]
	var last: Dictionary = history[history.size() - 1]
	draw_string(font, Vector2(chart.position.x, chart.end.y + font_size), "%s 〜 %s（%d日分）"
		% [world.clock.date_text(first.day), world.clock.date_text(last.day), history.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)
	draw_string(font, Vector2(chart.position.x, chart.end.y + font_size * 2.2), summary(last),
		HORIZONTAL_ALIGNMENT_LEFT, chart.size.x, font_size * 0.8, TEXT_COLOR)

# いちばん新しい決算の内わけ
func summary(report: Dictionary) -> String:
	var items: Array[String] = []
	for item in [["賃料", "rent"], ["宿泊", "hotel"], ["飲食", "food"], ["ショップ", "shop"], ["映画館", "cinema"], ["展望台", "observatory"],
			["住宅", "housing"], ["イベント", "event"], ["ボーナス", "bonus"]]:
		if report.get(item[1], 0) > 0:
			items.append("%s +%s" % [item[0], world.format_money(report[item[1]])])
	for item in [["維持費", "maintenance"], ["ゴミ", "garbage_cost"], ["返金", "refund"]]:
		if report.get(item[1], 0) > 0:
			items.append("%s -%s" % [item[0], world.format_money(report[item[1]])])
	items.append("合計 %s" % world.money_text(report.total, true))
	return "%s（%d日目）: %s" % [world.clock.date_text(report.day), report.day, " / ".join(items)]

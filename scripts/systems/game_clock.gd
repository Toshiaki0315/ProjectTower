extends Node

# ---------------------------------------------------
# ゲーム内の時計：日にち・曜日・時刻を進める。1日目は月曜日で、土日が休日。
# ゲーム内の1分 = 現実の 1 / MINUTES_PER_SECOND 秒（Engine.time_scaleで早送りできる）
# ---------------------------------------------------

const MINUTES_PER_SECOND := 2.0 # 現実の1秒で進むゲーム内の分数（1時間 = 30秒）
const MINUTES_PER_DAY := 24 * 60
const START_MINUTE := 7 * 60 + 30 # 1日目の7:30から始める
# 1フレームで進める上限（ゲーム内の分）。処理が一瞬止まって長いフレームになっても、
# 時計が何時間・何日も飛ばないようにする（その分、時計がゆっくり進む）
const MAX_MINUTES_PER_FRAME := 2.0
const WEEKDAY_NAMES := ["月", "火", "水", "木", "金", "土", "日"]

# 空の色の移り変わり: [時刻（分）, 色]。間の時刻は前後の色を少しずつ混ぜる
const SKY_COLORS := [
	[0 * 60, Color("#0b1026")],       # 深夜
	[4 * 60 + 30, Color("#0b1026")],  # 深夜
	[5 * 60 + 30, Color("#5b4a8a")],  # 早朝（紫）
	[6 * 60 + 30, Color("#f0a07a")],  # 朝焼け
	[8 * 60, Color("#8cc8ec")],       # 朝（水色）
	[12 * 60, Color("#5aaef0")],      # 昼（青）
	[16 * 60, Color("#7fbde6")],      # 午後
	[17 * 60 + 30, Color("#f08a4b")], # 夕方（オレンジ）
	[18 * 60 + 30, Color("#7a4a8c")], # 夕暮れ（紫）
	[19 * 60 + 30, Color("#1f2a4d")], # 夜（紺）
	[22 * 60, Color("#0b1026")],      # 深夜
	[24 * 60, Color("#0b1026")],
]

var day := 1
var minute := float(START_MINUTE) # その日の0:00からの経過分
var last_advance := 0.0 # 直前のフレームで進んだゲーム内の分（清掃・食事などの残り時間を減らすのに使う）

func _process(delta: float) -> void:
	last_advance = minf(delta * MINUTES_PER_SECOND, MAX_MINUTES_PER_FRAME)
	minute += last_advance
	while minute >= MINUTES_PER_DAY:
		minute -= MINUTES_PER_DAY
		day += 1

# 時刻を指定する（テストや将来の時間操作用）
func set_time(p_day: int, hour: int, min: int) -> void:
	day = p_day
	minute = hour * 60 + min
	last_advance = 0.0

# その日の経過分（整数）
func minute_of_day() -> int:
	return int(minute)

# 今の時刻の空の色
func sky_color() -> Color:
	for i in SKY_COLORS.size() - 1:
		var from = SKY_COLORS[i]
		var to = SKY_COLORS[i + 1]
		if minute >= from[0] and minute <= to[0]:
			var t: float = (minute - from[0]) / float(to[0] - from[0])
			return from[1].lerp(to[1], t)
	return SKY_COLORS[0][1]

# 太陽・月が空に出ている時刻（分）
const SUNRISE := 5 * 60 + 30
const SUNSET := 18 * 60 + 30

# 太陽の進み具合（0: 昇ったところ 〜 1: 沈むところ）。空に出ていなければ -1
func sun_progress() -> float:
	if minute < SUNRISE or minute > SUNSET:
		return -1.0
	return (minute - SUNRISE) / float(SUNSET - SUNRISE)

# 月の進み具合（0: 昇ったところ 〜 1: 沈むところ）。空に出ていなければ -1
func moon_progress() -> float:
	var night_length := MINUTES_PER_DAY - (SUNSET - SUNRISE)
	var since_moonrise := fposmod(minute - SUNSET, MINUTES_PER_DAY)
	if since_moonrise > night_length:
		return -1.0
	return since_moonrise / night_length

# 夜の暗さ（0: 明るい昼 〜 1: 真っ暗な夜）。星の見え方に使う
func darkness() -> float:
	return clampf(1.0 - sky_color().get_luminance() * 2.5, 0.0, 1.0)

# 曜日（0: 月 〜 6: 日）
func weekday(d: int = day) -> int:
	return (d - 1) % 7

# 休日（土日）か
func is_holiday(d: int = day) -> bool:
	return weekday(d) >= 5

func get_time_text() -> String:
	var text := "%d日目（%s）" % [day, WEEKDAY_NAMES[weekday()]]
	if is_holiday():
		text += "休日"
	return text + " %02d:%02d" % [minute_of_day() / 60, minute_of_day() % 60]

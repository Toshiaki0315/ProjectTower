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

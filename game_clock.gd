extends Node

# ---------------------------------------------------
# ゲーム内の時計：日にちと時刻を進める。
# ゲーム内の1分 = 現実の 1 / MINUTES_PER_SECOND 秒（Engine.time_scaleで早送りできる）
# ---------------------------------------------------

const MINUTES_PER_SECOND := 2.0 # 現実の1秒で進むゲーム内の分数（1時間 = 30秒）
const MINUTES_PER_DAY := 24 * 60
const START_MINUTE := 7 * 60 + 30 # 1日目の7:30から始める

var day := 1
var minute := float(START_MINUTE) # その日の0:00からの経過分

func _process(delta: float) -> void:
	minute += delta * MINUTES_PER_SECOND
	while minute >= MINUTES_PER_DAY:
		minute -= MINUTES_PER_DAY
		day += 1

# 時刻を指定する（テストや将来の時間操作用）
func set_time(p_day: int, hour: int, min: int) -> void:
	day = p_day
	minute = hour * 60 + min

# その日の経過分（整数）
func minute_of_day() -> int:
	return int(minute)

func get_time_text() -> String:
	return "%d日目 %02d:%02d" % [day, minute_of_day() / 60, minute_of_day() % 60]

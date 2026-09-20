extends Node

# ---------------------------------------------------
# 天気：日ごとに 晴れ・くもり・雨 が決まる（日付から作る乱数なので、同じ日なら毎回同じ天気）。
#   6月は梅雨で雨が多い（RAIN_CHANCE_RAINY_SEASON）。
# 影響:
#   雨の日は、入口から来る店のお客さんが RAINY_VISITOR_RATE に減る（外を歩きたくない）。
#   車で来るお客さん（地下駐車場）は、濡れないので減らない。
#   見た目: 空の色が暗くなり、雨が降る（くもりは少しだけ暗い）。
# ---------------------------------------------------

enum Weather { SUNNY, CLOUDY, RAINY }

const WEATHER_NAMES := {Weather.SUNNY: "晴れ", Weather.CLOUDY: "くもり", Weather.RAINY: "雨"}
const WEATHER_ICONS := {Weather.SUNNY: "☀", Weather.CLOUDY: "☁", Weather.RAINY: "☂"}
const CLOUDY_CHANCE := 0.25          # くもりになる確率
const RAIN_CHANCE := 0.15            # 雨になる確率
const RAIN_CHANCE_RAINY_SEASON := 0.45 # 梅雨（6月）の雨の確率
const RAINY_SEASON_MONTH := 6
const RAINY_VISITOR_RATE := 0.5      # 雨の日に、店へ来る外からのお客さんが何割になるか
const CLOUDY_TINT := Color(0.85, 0.87, 0.9)  # くもりの日に空の色にかける色
const RAINY_TINT := Color(0.62, 0.66, 0.72)  # 雨の日に空の色にかける色

var world: Node2D # main.gd

func setup(p_world: Node2D) -> void:
	world = p_world

# その日の天気（日付から決まる）
func weather_for(day: int) -> Weather:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "weather"])
	var roll := rng.randf()
	var rain: float = RAIN_CHANCE_RAINY_SEASON if world.clock.date(day)[0] == RAINY_SEASON_MONTH else RAIN_CHANCE
	if roll < rain:
		return Weather.RAINY
	if roll < rain + CLOUDY_CHANCE:
		return Weather.CLOUDY
	return Weather.SUNNY

func today() -> Weather:
	return weather_for(world.clock.day)

func is_rainy() -> bool:
	return today() == Weather.RAINY

# 店へ来る外からのお客さんの人数にかける割合
func visitor_rate() -> float:
	return RAINY_VISITOR_RATE if is_rainy() else 1.0

# 空の色にかける色（天気で暗くする）
func sky_tint() -> Color:
	match today():
		Weather.RAINY:
			return RAINY_TINT
		Weather.CLOUDY:
			return CLOUDY_TINT
		_:
			return Color.WHITE

func get_weather_text() -> String:
	return "%s %s" % [WEATHER_ICONS[today()], WEATHER_NAMES[today()]]

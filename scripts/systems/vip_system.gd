extends Node

# ---------------------------------------------------
# VIPの宿泊（★4への昇格イベント）:
#   人口や建物の条件（rating_system.REQUIREMENTS）を満たすと、その日の ANNOUNCE_MINUTE に
#   来館の予告が届き、ARRIVE_MINUTE にVIPが来館する。VIPは入口から、きれいな空きスイートへ向かう。
#   スイートに着いたらチェックインして一泊し、翌朝のチェックアウトのときに合否を決める。
#     合格の条件: 来館してからチェックアウトまでの一番高いストレスが STRESS_LIMIT 以下
#                 （＝スイートまでエレベーターなどで待たせない）
#     合格 … ★4に昇格できるようになる。
#     不合格 … 次の日にまた予告が来る。
#   着いたときにスイートがきれいでなかったり、LEAVE_MINUTE までに着けなかったりすると、
#   その日は泊まらずに帰る（次の日にまた来る）。
# ---------------------------------------------------

const VIP_COLOR := Color(1.0, 0.85, 0.2) # VIPの服の色（金色）
const STRESS_LIMIT := 30.0 # 来館からチェックアウトまでに、これを超えるストレスがあると不合格
const ANNOUNCE_MINUTE := 9 * 60 # 来館の予告が届く時刻
const ARRIVE_MINUTE := 16 * 60  # VIPが来る時刻（普通の宿泊客のチェックイン17時より前）
const LEAVE_MINUTE := 22 * 60   # この時刻までにスイートに着けなければ、その日は帰る

enum State { NONE, ANNOUNCED, ARRIVING, STAYING }

var world: Node2D # main.gd

var passed := false      # VIPを満足させたか（★4の条件の1つ）
var state := State.NONE
var visit_day := 0       # 最後に予告・来館した日
var vip = null           # 来館中のVIP（住人）
var room_origin := Vector2i.ZERO # 向かっている・泊まっているスイート（左端のマス）

func setup(p_world: Node2D) -> void:
	world = p_world

# 今、VIPが来館中か（向かっている間と、泊まっている間）
func is_visiting() -> bool:
	return is_instance_valid(vip) and (state == State.ARRIVING or state == State.STAYING)

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	match state:
		State.NONE:
			if not passed and visit_day != day and now >= ANNOUNCE_MINUTE and now < ARRIVE_MINUTE \
					and world.rating_system.waiting_for_vip():
				announce(day)
		State.ANNOUNCED:
			if now >= ARRIVE_MINUTE:
				invite()
		State.ARRIVING:
			process_arriving(now)
		State.STAYING:
			process_staying()

# 来館の予告（その日の16時に来る）
func announce(day: int) -> void:
	visit_day = day
	state = State.ANNOUNCED
	world.audio_system.play("chime")
	world.show_message("本日%d時にVIPが来館します！ スイートをきれいにして、エレベーターで待たせないようにしましょう"
		% (ARRIVE_MINUTE / 60))

# VIPを呼ぶ（きれいな空きスイートを探して、入口から向かわせる）
func invite() -> void:
	state = State.NONE
	var suite = find_clean_suite()
	if suite == null:
		world.show_message("VIPが来ようとしましたが、泊まれるスイート（きれいな空室）がありません（明日もう一度来ます）")
		return
	room_origin = suite
	var entrance = world.nearest_entrance(room_origin)
	if entrance == null:
		world.show_message("VIPが来ようとしましたが、スイートまでの道がありません（明日もう一度来ます）")
		return
	vip = world.spawn_resident(entrance)
	vip.base_color = VIP_COLOR
	if not vip.go_to(room_origin):
		world.show_message("VIPがスイートまでたどり着けないため、帰ってしまいました（明日もう一度来ます）")
		vip.queue_free()
		vip = null
		return
	state = State.ARRIVING
	world.show_message("VIPが来館しました！ スイートへ向かっています。明朝のチェックアウトで評価が決まります")

# きれいな空きスイート（左端のマス）を探す。なければnull
func find_clean_suite():
	var hotel = world.hotel_system
	for origin in world.find_units_of_type("hotel_suite"):
		if hotel.rooms.has(origin) and hotel.rooms[origin].state == hotel.RoomState.CLEAN:
			return origin
	return null

# スイートへ向かっている間
func process_arriving(now: int) -> void:
	if not is_instance_valid(vip):
		state = State.NONE
		return
	if now >= LEAVE_MINUTE:
		leave("VIPは待ちくたびれて帰ってしまいました（明日もう一度来ます）")
		return
	if vip.is_moving():
		return
	if vip.cell != room_origin:
		leave("VIPがスイートまでたどり着けず、帰ってしまいました（明日もう一度来ます）")
		return
	var hotel = world.hotel_system
	if not hotel.rooms.has(room_origin) or hotel.rooms[room_origin].state != hotel.RoomState.CLEAN:
		leave("VIPが着いたとき、スイートが使えませんでした（明日もう一度来ます）")
		return
	check_in()

# スイートにチェックインする（ここから先は普通の宿泊客と同じく、翌朝チェックアウトする）
func check_in() -> void:
	var room: Dictionary = world.hotel_system.rooms[room_origin]
	room.state = world.hotel_system.RoomState.OCCUPIED
	room.guests = [vip]
	room.checkin_day = world.clock.day
	room.stay_peak = vip.stress # 来館してからの一番高いストレス（ここまでの道のりのぶんも入れる）
	state = State.STAYING
	world.show_message("VIPがスイートにチェックインしました。明朝のチェックアウトで評価が決まります")

# 泊まっている間: チェックアウトしたら（部屋からいなくなったら）合否を決める
func process_staying() -> void:
	var room: Dictionary = world.hotel_system.rooms.get(room_origin, {})
	if not room.is_empty() and is_instance_valid(vip) and room.guests.has(vip):
		return # まだ泊まっている
	state = State.NONE
	var peak: float = room.get("stay_peak", 0.0)
	vip = null # チェックアウトしたVIPは、普通の宿泊客と同じように入口から帰る
	if peak <= STRESS_LIMIT:
		passed = true
		world.audio_system.play("money")
		world.show_message("VIPがチェックアウトしました。大満足です！ 条件がそろえば、次の決算で★4に昇格します")
	else:
		world.show_message("VIPがチェックアウトしました。待たされて不満でした（ストレス%d）。★4の昇格はおあずけです（明日もう一度来ます）" % int(peak))

# ビルの状況に出す文（来館中・宿泊中）
func get_status_text() -> String:
	if state == State.STAYING:
		var peak: float = world.hotel_system.rooms.get(room_origin, {}).get("stay_peak", 0.0)
		return "VIPが宿泊中（ここまでの一番高いストレス %d・%d以下なら合格）" % [int(peak), int(STRESS_LIMIT)]
	return "VIPが来館中（ストレス %d）" % int(vip.stress)

# 来館・宿泊の途中をなかったことにする（セーブデータを読み込むとき。VIPの住人も消えるため）
func reset_visit() -> void:
	vip = null
	state = State.NONE

# その日は泊まらずに帰る（次の日にまた来る）
func leave(message: String) -> void:
	if is_instance_valid(vip):
		vip.queue_free()
	vip = null
	state = State.NONE
	world.show_message(message)

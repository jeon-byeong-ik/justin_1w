# Main.gd — 도마뱀 발사!  (M0 + M1 저장 + M3 2인 턴제 대결)
#
# 모드:
#   SOLO   — 혼자: 발사로 에너지 누적 → 진화, 최고기록 저장(user://save.json)
#   VERSUS — 둘이: 턴제(P1→P2) 한 라운드, 비거리 비교, 3판 2선승, 리매치
#
# 입력:
#   타이틀: [1]/좌측탭=혼자, [2]/우측탭=둘이대결
#   솔로  : 탭/Space/클릭 = 모든 동작
#   대결  : P1 = A 또는 화면 왼쪽 / P2 = L 또는 화면 오른쪽 (자기 차례에만 반응)
#   공통  : Esc = 타이틀로
extends Node2D

enum State { TITLE, READY, CHARGE, AIM, FLIGHT, RESULT, MATCH }
enum Mode { SOLO, VERSUS }

# --- 튜닝 값 (game-design.md §9) ---
const CHARGE_TIME := 3.0
const POWER_PER_TAP := 0.06
const POWER_DECAY := 0.10
const POWER_MAX := 1.2
const ANGLE_SWEEP_SPEED := 110.0
const FLIGHT_TIME := 1.4
const METER_TO_PX := 4.0
const WIN_ROUNDS := 2          # 3판 2선승

# --- 화면 좌표 ---
const GROUND_Y := 560.0
const LAUNCH_X := 170.0
const MID_X := 640.0

# --- 게임 상태 ---
var state: int = State.TITLE
var mode: int = Mode.SOLO

# 발사 진행 변수
var power := 0.0
var charge_timer := 0.0
var angle := 0.0
var angle_dir := 1.0
var sweet := 0.0
var flight_t := 0.0
var last_distance := 0.0
var last_perfect := false
var last_energy := 0

# 솔로 진척(저장 대상)
var total_energy := 0
var best_distance := 0.0
var evo_stage := 0

# 대결 상태
var current_player := 1        # 1 또는 2
var versus_dist := [0.0, 0.0]  # [P1, P2] 이번 라운드 비거리
var scores := [0, 0]           # [P1, P2] 라운드 승수
var round_num := 1
var match_over := false

# --- UI 노드 ---
var title_label: Label
var center_label: Label
var hint_label: Label
var hud_label: Label

# --- 진화 단계별 스프라이트 ---
var stage_textures: Array = [null, null, null]
const STAGE_IMAGE_EXTS := [".png", ".webp", ".jpg", ".jpeg"]

func _load_stage_textures() -> void:
	for i in range(stage_textures.size()):
		for ext in STAGE_IMAGE_EXTS:
			var path := "res://assets/stage%d%s" % [i, ext]
			if ResourceLoader.exists(path):
				stage_textures[i] = load(path)
				break

func _ready() -> void:
	_load_stage_textures()
	title_label = _make_label(24, Color.WHITE, Vector2(0, 14), 1280, HORIZONTAL_ALIGNMENT_CENTER)
	hud_label = _make_label(22, Color(0.9, 0.95, 1.0), Vector2(24, 52), 1232, HORIZONTAL_ALIGNMENT_LEFT)
	center_label = _make_label(50, Color.WHITE, Vector2(0, 210), 1280, HORIZONTAL_ALIGNMENT_CENTER)
	hint_label = _make_label(26, Color(1, 1, 1, 0.9), Vector2(0, 614), 1280, HORIZONTAL_ALIGNMENT_CENTER)

	var d := SaveData.load_data()
	total_energy = int(d.total_energy)
	best_distance = float(d.best_distance)
	evo_stage = Evolution.stage_for_energy(total_energy)
	_enter_title()

func _make_label(font_size: int, color: Color, pos: Vector2, width: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.position = pos
	l.size = Vector2(width, 60)
	l.horizontal_alignment = align
	add_child(l)
	return l

# ==================== 입력 ====================
func _unhandled_input(event: InputEvent) -> void:
	var kc := -1
	if event is InputEventKey and event.pressed and not event.echo:
		kc = event.keycode
	var mb := event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var touch := event is InputEventScreenTouch and event.pressed
	if kc == -1 and not mb and not touch:
		return
	var px := 0.0
	if mb or touch:
		px = event.position.x

	if kc == KEY_ESCAPE:
		_enter_title()
		return

	match state:
		State.TITLE:
			_title_input(kc, mb, touch, px)
		State.RESULT:
			if _is_confirm(kc, mb, touch):
				_advance_result()
		State.MATCH:
			if _is_confirm(kc, mb, touch):
				_advance_match()
		_:
			var pid := _acting_player(kc, mb, touch, px)
			if pid == 0:
				return
			if mode == Mode.VERSUS and pid != current_player:
				return
			_gameplay_tap()

func _is_confirm(kc: int, mb: bool, touch: bool) -> bool:
	return mb or touch or kc in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_A, KEY_L]

func _acting_player(kc: int, mb: bool, touch: bool, px: float) -> int:
	if mode == Mode.SOLO:
		return 1
	if kc == KEY_A:
		return 1
	if kc == KEY_L:
		return 2
	if kc in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		return current_player
	if mb or touch:
		return 1 if px < MID_X else 2
	return 0

func _title_input(kc: int, mb: bool, touch: bool, px: float) -> void:
	var pick_solo := kc in [KEY_1, KEY_KP_1, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] or ((mb or touch) and px < MID_X)
	var pick_versus := kc in [KEY_2, KEY_KP_2] or ((mb or touch) and px >= MID_X)
	if pick_solo:
		mode = Mode.SOLO
		_enter_ready()
	elif pick_versus:
		mode = Mode.VERSUS
		_start_versus()

func _gameplay_tap() -> void:
	match state:
		State.READY:
			_enter_charge()
		State.CHARGE:
			power = min(power + POWER_PER_TAP, POWER_MAX)
		State.AIM:
			_lock_angle_and_fly()

# ==================== 상태 전이 ====================
func _enter_title() -> void:
	state = State.TITLE
	evo_stage = Evolution.stage_for_energy(total_energy)
	center_label.text = "🦎 도마뱀 발사!"
	hint_label.text = "[1] 혼자하기      [2] 둘이 대결        (화면 좌/우 탭으로도 선택)"
	_refresh_hud()

func _enter_ready() -> void:
	state = State.READY
	power = 0.0
	charge_timer = 0.0
	angle = 0.0
	sweet = 0.0
	if mode == Mode.SOLO:
		center_label.text = ""
		hint_label.text = "[탭/스페이스] 발사 시작!"
	else:
		var key_name := "A" if current_player == 1 else "L"
		var side := "왼쪽" if current_player == 1 else "오른쪽"
		center_label.text = "P%d 준비!" % current_player
		hint_label.text = "P%d 차례 — [%s] 연타 또는 화면 %s 탭으로 시작" % [current_player, key_name, side]
	_refresh_hud()

func _enter_charge() -> void:
	state = State.CHARGE
	power = 0.0
	charge_timer = CHARGE_TIME
	center_label.text = ""
	hint_label.text = "연타해서 파워를 채워라! (시간 끝나면 각도 단계)"

func _enter_aim() -> void:
	state = State.AIM
	angle = 0.0
	angle_dir = 1.0
	hint_label.text = "확정 입력! 45° 초록 스위트스팟이 퍼펙트"

func _lock_angle_and_fly() -> void:
	var stats := Evolution.stats(evo_stage)
	var window: float = 20.0 * float(stats.sweet_w)
	sweet = clamp(1.0 - abs(angle - LaunchFormula.ANGLE_IDEAL) / window, 0.0, 1.0)
	var result := LaunchFormula.compute(power, angle, sweet, stats)
	last_distance = result.distance
	last_perfect = result.perfect
	last_energy = LaunchFormula.energy_gain(last_distance, last_perfect)
	state = State.FLIGHT
	flight_t = 0.0
	center_label.text = ""
	hint_label.text = ""

func _enter_result() -> void:
	state = State.RESULT
	var perfect_txt := "  ✨PERFECT" if last_perfect else ""
	if mode == Mode.SOLO:
		total_energy += last_energy
		if last_distance > best_distance:
			best_distance = last_distance
		var ns := Evolution.stage_for_energy(total_energy)
		var evolved := ns > evo_stage
		evo_stage = ns
		SaveData.save_data(total_energy, best_distance)
		center_label.text = "%.1f m%s" % [last_distance, perfect_txt]
		if evolved:
			hint_label.text = "🌟 진화! → %s   [탭]으로 계속" % Evolution.stats(evo_stage).name
		else:
			hint_label.text = "+%d 에너지   [탭]으로 다시하기" % last_energy
	else:
		versus_dist[current_player - 1] = last_distance
		center_label.text = "P%d : %.1f m%s" % [current_player, last_distance, perfect_txt]
		if current_player == 1:
			hint_label.text = "[L / 오른쪽 탭] → P2 차례로"
		else:
			hint_label.text = "[탭] 라운드 결과 보기"
	_refresh_hud()

func _advance_result() -> void:
	if mode == Mode.SOLO:
		_enter_ready()
	elif current_player == 1:
		current_player = 2
		_enter_ready()
	else:
		_resolve_round()

# ---- 대결 라운드/매치 ----
func _start_versus() -> void:
	scores = [0, 0]
	round_num = 1
	current_player = 1
	versus_dist = [0.0, 0.0]
	match_over = false
	_enter_ready()

func _resolve_round() -> void:
	var d1: float = versus_dist[0]
	var d2: float = versus_dist[1]
	var winner := 0
	if d1 > d2:
		winner = 1
		scores[0] += 1
	elif d2 > d1:
		winner = 2
		scores[1] += 1
	state = State.MATCH
	match_over = scores[0] >= WIN_ROUNDS or scores[1] >= WIN_ROUNDS
	var head := "무승부!" if winner == 0 else "P%d 라운드 승!" % winner
	center_label.text = "%s\nP1 %.1fm   vs   P2 %.1fm" % [head, d1, d2]
	if match_over:
		var champ := 1 if scores[0] > scores[1] else 2
		hint_label.text = "🏆 최종 승자 P%d!  (%d:%d)   [탭] 리매치 · [Esc] 타이틀" % [champ, scores[0], scores[1]]
	else:
		hint_label.text = "스코어 P1 %d : %d P2   [탭] 다음 라운드" % [scores[0], scores[1]]
	_refresh_hud()

func _advance_match() -> void:
	if match_over:
		_start_versus()
	else:
		round_num += 1
		current_player = 1
		versus_dist = [0.0, 0.0]
		_enter_ready()

# ==================== 업데이트 ====================
func _process(delta: float) -> void:
	match state:
		State.CHARGE:
			power = max(power - POWER_DECAY * delta, 0.0)
			charge_timer -= delta
			if charge_timer <= 0.0:
				charge_timer = 0.0
				_enter_aim()
		State.AIM:
			angle += angle_dir * ANGLE_SWEEP_SPEED * delta
			if angle >= 90.0:
				angle = 90.0
				angle_dir = -1.0
			elif angle <= 0.0:
				angle = 0.0
				angle_dir = 1.0
		State.FLIGHT:
			flight_t += delta / FLIGHT_TIME
			if flight_t >= 1.0:
				flight_t = 1.0
				_enter_result()
	queue_redraw()

func _evo_dots() -> String:
	var dots := ""
	for i in range(Evolution.STAGES.size()):
		dots += "●" if i <= evo_stage else "○"
	return dots

func _refresh_hud() -> void:
	title_label.text = "🦎 도마뱀 발사!  —  제작: justin"
	if mode == Mode.VERSUS and state != State.TITLE:
		hud_label.text = "VERSUS · R%d (3판 2선승)    P1 %d : %d P2    ▶ 현재 P%d" % [
			round_num, scores[0], scores[1], current_player]
	else:
		var nxt := Evolution.energy_to_next(total_energy)
		var nxt_txt := "다음 진화까지 %d" % nxt if nxt > 0 else "최종 진화 달성"
		hud_label.text = "진화 %s %s    💠 %d (%s)    🏅 최고 %.1fm" % [
			_evo_dots(), Evolution.stats(evo_stage).name, total_energy, nxt_txt, best_distance]

# ==================== 렌더링 ====================
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.52, 0.78, 0.92))
	draw_rect(Rect2(0, GROUND_Y, 1280, 720 - GROUND_Y), Color(0.40, 0.62, 0.32))

	if state == State.TITLE:
		_draw_lizard(Vector2(MID_X, 400), Evolution.stats(evo_stage).color)
		return

	draw_rect(Rect2(LAUNCH_X - 40, GROUND_Y - 14, 90, 14), Color(0.35, 0.25, 0.18))

	# 대결: 현재 플레이어 표식
	if mode == Mode.VERSUS and state in [State.READY, State.CHARGE, State.AIM, State.FLIGHT]:
		var pcol := Color(0.95, 0.4, 0.4) if current_player == 1 else Color(0.4, 0.6, 0.95)
		draw_circle(Vector2(LAUNCH_X + 5, GROUND_Y - 90), 10.0, pcol)

	var liz_pos := Vector2(LAUNCH_X, GROUND_Y - 26)
	if state == State.FLIGHT:
		liz_pos = _flight_pos(flight_t)
	_draw_lizard(liz_pos, Evolution.stats(evo_stage).color)

	match state:
		State.CHARGE:
			_draw_power_bar()
			_draw_timer_bar()
		State.AIM:
			_draw_power_bar()
			_draw_angle_indicator()

func _flight_pos(t: float) -> Vector2:
	var reach: float = min(last_distance * METER_TO_PX, 980.0)
	var x := LAUNCH_X + reach * t
	var arc := 220.0 + sin(deg_to_rad(angle)) * 160.0
	var y := (GROUND_Y - 26) - arc * sin(PI * t)
	return Vector2(x, y)

func _draw_lizard(pos: Vector2, body: Color) -> void:
	var tex: Texture2D = stage_textures[evo_stage]
	if tex != null:
		var target := 110.0
		var scale := target / float(max(tex.get_width(), tex.get_height()))
		var w := tex.get_width() * scale
		var h := tex.get_height() * scale
		draw_texture_rect(tex, Rect2(pos.x - w / 2.0, pos.y - h / 2.0, w, h), false)
		return
	draw_circle(pos, 20.0, body)
	draw_circle(pos + Vector2(12, -8), 6.0, Color.WHITE)
	draw_circle(pos + Vector2(14, -8), 3.0, Color.BLACK)
	draw_circle(pos + Vector2(-18, 6), 8.0, body.darkened(0.15))

func _draw_power_bar() -> void:
	var x := 200.0
	var y := 660.0
	var w := 880.0
	var h := 26.0
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.35))
	var fill: float = clamp(power, 0.0, POWER_MAX) / POWER_MAX
	var col := Color(0.95, 0.75, 0.2)
	if power > 1.0:
		col = Color(0.95, 0.35, 0.25)
	draw_rect(Rect2(x, y, w * fill, h), col)
	var mark := x + w * (1.0 / POWER_MAX)
	draw_line(Vector2(mark, y - 4), Vector2(mark, y + h + 4), Color.WHITE, 2.0)

func _draw_timer_bar() -> void:
	var x := 200.0
	var y := 694.0
	var w := 880.0
	draw_rect(Rect2(x, y, w, 8), Color(0, 0, 0, 0.25))
	var frac: float = clamp(charge_timer / CHARGE_TIME, 0.0, 1.0)
	draw_rect(Rect2(x, y, w * frac, 8), Color(1, 1, 1, 0.85))

func _draw_angle_indicator() -> void:
	var origin := Vector2(LAUNCH_X, GROUND_Y - 26)
	var stats := Evolution.stats(evo_stage)
	var window: float = 20.0 * float(stats.sweet_w)
	var lo := LaunchFormula.ANGLE_IDEAL - window
	var hi := LaunchFormula.ANGLE_IDEAL + window
	_draw_angle_ray(origin, lo, Color(0.3, 0.9, 0.4, 0.5), 160.0)
	_draw_angle_ray(origin, hi, Color(0.3, 0.9, 0.4, 0.5), 160.0)
	_draw_angle_ray(origin, LaunchFormula.ANGLE_IDEAL, Color(0.3, 0.9, 0.4, 0.8), 175.0)
	_draw_angle_ray(origin, angle, Color(0.95, 0.25, 0.2), 200.0)

func _draw_angle_ray(origin: Vector2, deg: float, color: Color, length: float) -> void:
	var dir := Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)))
	draw_line(origin, origin + dir * length, color, 4.0)

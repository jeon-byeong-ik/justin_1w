# SaveData.gd — 로컬 저장/불러오기 (M1, 확장)
#
# user://save.json 에 진척을 JSON으로 저장한다. 필드가 늘어도 .get 기본값으로 하위호환.
#   wallet          : 사용 가능한 에너지(상점 지출 대상)
#   lifetime_energy : 누적 획득 에너지(진화 기준, 절대 감소하지 않음 — 원칙 4)
#   best_distance   : 최고 단발 비거리
#   total_distance  : 누적 비거리(지역 해금 기준)
#   drag_bonus      : 상점 영구 강화(공기저항 감소 누적)
#   pmul_bonus      : 상점 영구 강화(파워 배수 증가 누적)
class_name SaveData
extends RefCounted

const PATH := "user://save.json"

static func defaults() -> Dictionary:
	return {
		"wallet": 0,
		"lifetime_energy": 0,
		"best_distance": 0.0,
		"total_distance": 0.0,
		"drag_bonus": 0.0,
		"pmul_bonus": 0.0,
		"leaderboard": [],   # 무한 챌린지 기록(상위 10)
	}

static func load_data() -> Dictionary:
	var d := defaults()
	if not FileAccess.file_exists(PATH):
		return d
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return d
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in d.keys():
			if parsed.has(k):
				d[k] = parsed[k]
	return d

static func save_data(d: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d))
	f.close()

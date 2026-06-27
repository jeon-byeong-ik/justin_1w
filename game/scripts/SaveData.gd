# SaveData.gd — 로컬 저장/불러오기 (M1)
#
# user:// 경로에 JSON으로 진척(누적 에너지·최고 기록)을 저장한다.
# 솔로 모드의 진화·기록만 저장 대상(대결은 일회성 듀얼).
class_name SaveData
extends RefCounted

const PATH := "user://save.json"

static func load_data() -> Dictionary:
	var d := { "total_energy": 0, "best_distance": 0.0 }
	if not FileAccess.file_exists(PATH):
		return d
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return d
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		d["total_energy"] = int(parsed.get("total_energy", 0))
		d["best_distance"] = float(parsed.get("best_distance", 0.0))
	return d

static func save_data(total_energy: int, best_distance: float) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"total_energy": total_energy,
		"best_distance": best_distance,
	}))
	f.close()

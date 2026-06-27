# Region.gd — 스토리 지역 테이블 (M4)
#
# game-design.md §2.3 의 4개 지역. 누적 비거리로 해금되며, 지역마다 하늘색과 바람 범위가 다르다.
class_name Region
extends RefCounted

const LIST := [
	{
		"name": "🌳 풀숲 들판", "threshold": 0.0,
		"wind_min": 0.0, "wind_max": 0.0,
		"sky": Color(0.52, 0.78, 0.92), "ground": Color(0.40, 0.62, 0.32),
	},
	{
		"name": "🏜️ 메마른 협곡", "threshold": 500.0,
		"wind_min": -5.0, "wind_max": 5.0,
		"sky": Color(0.85, 0.70, 0.45), "ground": Color(0.62, 0.48, 0.28),
	},
	{
		"name": "☁️ 구름 바다", "threshold": 2000.0,
		"wind_min": -3.0, "wind_max": 7.0,
		"sky": Color(0.70, 0.80, 0.95), "ground": Color(0.78, 0.82, 0.90),
	},
	{
		"name": "🌌 성층권 너머", "threshold": 8000.0,
		"wind_min": -8.0, "wind_max": 8.0,
		"sky": Color(0.10, 0.08, 0.22), "ground": Color(0.18, 0.16, 0.30),
	},
]

# 누적 비거리로 현재(최고 해금) 지역 인덱스
static func index_for(total_distance: float) -> int:
	var idx := 0
	for i in range(LIST.size()):
		if total_distance >= float(LIST[i].threshold):
			idx = i
	return idx

static func get_region(idx: int) -> Dictionary:
	return LIST[clamp(idx, 0, LIST.size() - 1)]

# 다음 지역 해금까지 남은 누적 비거리 (마지막이면 0)
static func dist_to_next(total_distance: float) -> float:
	var idx := index_for(total_distance)
	if idx >= LIST.size() - 1:
		return 0.0
	return float(LIST[idx + 1].threshold) - total_distance

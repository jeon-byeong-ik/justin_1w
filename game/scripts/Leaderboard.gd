# Leaderboard.gd — 로컬 리더보드 (M4, 순수 로직)
#
# 무한 챌린지의 단발 비거리 기록을 상위 N개로 관리한다. 저장은 SaveData(JSON 배열).
# 엔트리: { "dist": float, "perfect": bool, "stage": int, "date": String }
class_name Leaderboard
extends RefCounted

const MAX_ENTRIES := 10

# 기록 추가 후 내림차순 정렬, 상위 MAX_ENTRIES 만 유지한 새 배열 반환
static func add(list: Array, entry: Dictionary) -> Array:
	var l := list.duplicate()
	l.append(entry)
	l.sort_custom(func(a, b): return float(a.dist) > float(b.dist))
	if l.size() > MAX_ENTRIES:
		l = l.slice(0, MAX_ENTRIES)
	return l

# 이 비거리가 차지할 순위(1-based). 기존 기록 중 더 먼 것 개수 + 1.
static func rank_of(list: Array, dist: float) -> int:
	var r := 1
	for e in list:
		if float(e.dist) > dist:
			r += 1
	return r

# 최고 기록(없으면 0)
static func best(list: Array) -> float:
	var b := 0.0
	for e in list:
		b = max(b, float(e.dist))
	return b

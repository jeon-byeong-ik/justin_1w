# AudioManager.gd — 절차적 효과음 (M2, 에셋 파일 없이 코드로 생성)
#
# 사운드 파일을 동봉하지 않고, 사인파를 즉석 합성해 AudioStreamWAV 로 만든다(저작권/용량 부담 0).
# Main 에서 add_child 로 붙이고 audio.play("tap") 형태로 호출.
class_name AudioManager
extends Node

const SR := 22050

var _streams := {}
var _pool: Array = []
var _idx := 0

func _ready() -> void:
	for i in range(6):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_streams["tap"] = _build(520.0, 520.0, 0.05, 0.25)      # 연타: 짧은 틱
	_streams["launch"] = _build(180.0, 720.0, 0.28, 0.40)   # 발사: 상승 슈웅
	_streams["perfect"] = _build(1320.0, 1320.0, 0.18, 0.40)# 퍼펙트: 청량한 팅
	_streams["land"] = _build(140.0, 90.0, 0.14, 0.40)      # 착지: 툭
	_streams["evolve"] = _build(330.0, 1200.0, 0.75, 0.45)  # 진화: 웅장한 상승
	_streams["win"] = _build(880.0, 1100.0, 0.35, 0.40)     # 승리: 팡파레

func play(name: String) -> void:
	if not _streams.has(name):
		return
	var p: AudioStreamPlayer = _pool[_idx]
	_idx = (_idx + 1) % _pool.size()
	p.stream = _streams[name]
	p.play()

# f0→f1 로 주파수가 변하는 16비트 모노 톤(선형 감쇠 엔벨로프)
func _build(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	var n := int(dur * SR)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in range(n):
		var k := float(i) / float(n)
		var freq: float = lerp(f0, f1, k)
		phase += TAU * freq / float(SR)
		var env := 1.0 - k
		var v := sin(phase) * env * vol
		var sample := int(clamp(v, -1.0, 1.0) * 32767.0)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	s.data = data
	return s

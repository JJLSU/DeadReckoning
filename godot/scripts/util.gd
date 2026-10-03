class_name U
## Shared math, noise and RNG helpers (ported 1:1 from the HTML version so worlds match).

const M32 := 0xFFFFFFFF

static func u32(v: int) -> int:
	return v & M32

## Math.imul low 32 bits, overflow-safe in 64-bit ints.
static func imul(a: int, b: int) -> int:
	a &= M32
	b &= M32
	var lo := (a & 0xFFFF) * b
	var hi := (((a >> 16) * b) & 0xFFFF) << 16
	return (lo + hi) & M32

static func hash3(ix: int, iy: int, s: int) -> float:
	var h := (imul(ix, 374761393) + imul(iy, 668265263) + imul(s, 1442695041)) & M32
	h = imul(h ^ (h >> 13), 1274126177)
	h ^= h >> 16
	return float(h) / 4294967296.0

static func vnoise(x: float, y: float, s: int) -> float:
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := hash3(ix, iy, s)
	var b := hash3(ix + 1, iy, s)
	var c := hash3(ix, iy + 1, s)
	var d := hash3(ix + 1, iy + 1, s)
	return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy

static func fbm(x: float, y: float, s: int, o: int) -> float:
	var v := 0.0
	var amp := 0.5
	var f := 1.0
	var n := 0.0
	for i in o:
		v += vnoise(x * f, y * f, s + i * 31) * amp
		n += amp
		amp *= 0.5
		f *= 2.03
	return v / n

static func ang_diff(a: float, b: float) -> float:
	var d := fmod(a - b, TAU)
	if d > PI: d -= TAU
	if d < -PI: d += TAU
	return d

static func km(u: float) -> int:
	return int(round(u / 100.0))

static func rnd() -> float:
	return randf()

static func shade(c: Color, k: float) -> Color:
	return Color(minf(1.0, floor(c.r * 255.0 * k) / 255.0), minf(1.0, floor(c.g * 255.0 * k) / 255.0), minf(1.0, floor(c.b * 255.0 * k) / 255.0), c.a)

static func rgb(r: float, g: float, b: float, a: float = 1.0) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)

static func hx(s: String) -> Color:
	return Color.html(s)

static func shuffle(a: Array, r: Callable) -> Array:
	var i := a.size() - 1
	while i > 0:
		var j := int(r.call() * (i + 1))
		var t = a[i]
		a[i] = a[j]
		a[j] = t
		i -= 1
	return a

static func pad2(n: int) -> String:
	return ("0" + str(n)) if n < 10 else str(n)

static func rid() -> String:
	return str(randi()) + str(randi() % 100000)


## Seeded RNG identical to the JS mulberry32.
class Mulberry:
	var a: int
	func _init(seed_v: int) -> void:
		a = seed_v & 0xFFFFFFFF
	func next() -> float:
		a = (a + 0x6D2B79F5) & 0xFFFFFFFF
		var t := U.imul(a ^ (a >> 15), 1 | a)
		t = ((t + U.imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
		t &= 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
	func ri(lo: int, hi: int) -> int:
		return lo + int(next() * (hi - lo + 1))

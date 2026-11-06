class_name VHNoise
extends RefCounted
## Bit-exact ports of the reference's noise.ts: mulberry32 and seeded simplex noise (Gustavson), so
## generated trees and rocks come out the same as in the three.js build.

const M := 0xFFFFFFFF
const GRAD3 := [1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1, 0, 1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, -1, 0, 1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1]

var _a := 0
var perm := PackedInt32Array()
var pm := PackedInt32Array()

## mulberry32 stream: call next() for [0, 1).
static func rng(seed: int) -> VHNoise:
	var r := VHNoise.new()
	r._a = seed & M
	return r

func next() -> float:
	_a = (_a + 0x6D2B79F5) & M
	var t := ((_a ^ (_a >> 15)) * (1 | _a)) & M
	t = ((t + (((t ^ (t >> 7)) * (61 | t)) & M)) & M) ^ t
	return float((t ^ (t >> 14)) & M) / 4294967296.0

func range_f(a: float, b: float) -> float:
	return a + (b - a) * next()

static func simplex(seed: int) -> VHNoise:
	var n := VHNoise.new()
	var r := rng(seed)
	var p := PackedInt32Array(range(256))
	for i in range(255, 0, -1):
		var j := int(floor(r.next() * (i + 1)))
		var t := p[i]
		p[i] = p[j]
		p[j] = t
	n.perm.resize(512)
	n.pm.resize(512)
	for i in 512:
		n.perm[i] = p[i & 255]
		n.pm[i] = n.perm[i] % 12
	return n

func noise2(xin: float, yin: float) -> float:
	const F2 := 0.36602540378
	const G2 := 0.21132486540
	var s := (xin + yin) * F2
	var i := floori(xin + s)
	var j := floori(yin + s)
	var t := (i + j) * G2
	var x0 := xin - (i - t)
	var y0 := yin - (j - t)
	var i1 := 1 if x0 > y0 else 0
	var j1 := 0 if x0 > y0 else 1
	var x1 := x0 - i1 + G2
	var y1 := y0 - j1 + G2
	var x2 := x0 - 1.0 + 2.0 * G2
	var y2 := y0 - 1.0 + 2.0 * G2
	var ii := i & 255
	var jj := j & 255
	var n0 := 0.0
	var n1 := 0.0
	var n2 := 0.0
	var t0 := 0.5 - x0 * x0 - y0 * y0
	if t0 >= 0.0:
		var g := pm[ii + perm[jj]] * 3
		t0 *= t0
		n0 = t0 * t0 * (GRAD3[g] * x0 + GRAD3[g + 1] * y0)
	var t1 := 0.5 - x1 * x1 - y1 * y1
	if t1 >= 0.0:
		var g := pm[ii + i1 + perm[jj + j1]] * 3
		t1 *= t1
		n1 = t1 * t1 * (GRAD3[g] * x1 + GRAD3[g + 1] * y1)
	var t2 := 0.5 - x2 * x2 - y2 * y2
	if t2 >= 0.0:
		var g := pm[ii + 1 + perm[jj + 1]] * 3
		t2 *= t2
		n2 = t2 * t2 * (GRAD3[g] * x2 + GRAD3[g + 1] * y2)
	return 70.0 * (n0 + n1 + n2)

func noise3(xin: float, yin: float, zin: float) -> float:
	const F3 := 1.0 / 3.0
	const G3 := 1.0 / 6.0
	var s := (xin + yin + zin) * F3
	var i := floori(xin + s)
	var j := floori(yin + s)
	var k := floori(zin + s)
	var t := (i + j + k) * G3
	var x0 := xin - (i - t)
	var y0 := yin - (j - t)
	var z0 := zin - (k - t)
	var i1: int; var j1: int; var k1: int; var i2: int; var j2: int; var k2: int
	if x0 >= y0:
		if y0 >= z0: i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0
		elif x0 >= z0: i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1
		else: i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1
	else:
		if y0 < z0: i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1
		elif x0 < z0: i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1
		else: i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0
	var x1 := x0 - i1 + G3
	var y1 := y0 - j1 + G3
	var z1 := z0 - k1 + G3
	var x2 := x0 - i2 + 2.0 * G3
	var y2 := y0 - j2 + 2.0 * G3
	var z2 := z0 - k2 + 2.0 * G3
	var x3 := x0 - 1.0 + 3.0 * G3
	var y3 := y0 - 1.0 + 3.0 * G3
	var z3 := z0 - 1.0 + 3.0 * G3
	var ii := i & 255
	var jj := j & 255
	var kk := k & 255
	var n := 0.0
	var tt := 0.6 - x0 * x0 - y0 * y0 - z0 * z0
	if tt > 0.0:
		var g := pm[ii + perm[jj + perm[kk]]] * 3
		tt *= tt
		n += tt * tt * (GRAD3[g] * x0 + GRAD3[g + 1] * y0 + GRAD3[g + 2] * z0)
	tt = 0.6 - x1 * x1 - y1 * y1 - z1 * z1
	if tt > 0.0:
		var g := pm[ii + i1 + perm[jj + j1 + perm[kk + k1]]] * 3
		tt *= tt
		n += tt * tt * (GRAD3[g] * x1 + GRAD3[g + 1] * y1 + GRAD3[g + 2] * z1)
	tt = 0.6 - x2 * x2 - y2 * y2 - z2 * z2
	if tt > 0.0:
		var g := pm[ii + i2 + perm[jj + j2 + perm[kk + k2]]] * 3
		tt *= tt
		n += tt * tt * (GRAD3[g] * x2 + GRAD3[g + 1] * y2 + GRAD3[g + 2] * z2)
	tt = 0.6 - x3 * x3 - y3 * y3 - z3 * z3
	if tt > 0.0:
		var g := pm[ii + 1 + perm[jj + 1 + perm[kk + 1]]] * 3
		tt *= tt
		n += tt * tt * (GRAD3[g] * x3 + GRAD3[g + 1] * y3 + GRAD3[g + 2] * z3)
	return 32.0 * n

func fbm3(x: float, y: float, z: float, oct := 4) -> float:
	var s := 0.0
	var a := 1.0
	var nn := 0.0
	var f := 1.0
	for i in oct:
		s += a * noise3(x * f, y * f, z * f)
		nn += a
		a *= 0.5
		f *= 2.0
	return s / nn

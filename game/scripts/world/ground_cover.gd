class_name GroundCover
extends RefCounted
## Meshes for ferns and wildflowers (instanced through GrassBuilder chunks).

static func fern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := 7
	for f in fronds:
		var ang := TAU * f / fronds + (f % 2) * 0.2
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := 0.85 + 0.25 * ((f * 7) % 3) / 2.0
		var lift := 0.55 + 0.15 * (f % 3)
		var segs := 4
		var prev := Vector3(0, 0.03, 0)
		var prev_w := 0.04
		for i in segs:
			var u := float(i + 1) / segs
			# arching frond: rises, then droops at the tip
			var p := dir * length * u + Vector3(0, sin(u * PI * 0.85) * lift * length * 0.6 + 0.03, 0)
			var wdt := 0.16 * (1.0 - u * 0.7) * length
			var u0 := float(i) / segs
			var quad := [[prev - side * prev_w, Vector2(0, u0)], [prev + side * prev_w, Vector2(1, u0)],
				[p + side * wdt, Vector2(1, u)], [p - side * wdt, Vector2(0, u)]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv(quad[k][1])
				st.set_normal(Vector3.UP)
				st.add_vertex(quad[k][0])
			prev = p
			prev_w = wdt
	return st.commit()

static func flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.32
	# stem (two crossed quads) with a leaf at the base
	for a in [0.0, PI * 0.5]:
		var s := Vector3(cos(a), 0, sin(a)) * 0.03
		var q := [[-s, Vector2(0, 0)], [s, Vector2(1, 0)], [s + Vector3(0, h, 0), Vector2(1, 1)], [-s + Vector3(0, h, 0), Vector2(0, 1)]]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(0, 0, 0)); st.set_uv(q[k][1]); st.set_normal(Vector3.UP); st.add_vertex(q[k][0])
	# head: a slightly tilted disc quad
	var c := Vector3(0, h, 0)
	var r := 0.09
	var t := Vector3(0, 0.02, 0)
	var hq := [[c + Vector3(-r, 0, -r) + t, Vector2(0, 0)], [c + Vector3(r, 0, -r) + t, Vector2(1, 0)],
		[c + Vector3(r, 0, r) - t, Vector2(1, 1)], [c + Vector3(-r, 0, r) - t, Vector2(0, 1)]]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(1, 0, 0)); st.set_uv(hq[k][1]); st.set_normal(Vector3.UP); st.add_vertex(hq[k][0])
	return st.commit()

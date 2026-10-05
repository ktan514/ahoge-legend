extends Node2D

var session
var show_path: bool = true
var show_mesh: bool = false


func _draw() -> void:
	if session == null:
		return
	var points: PackedVector2Array = session.pose()
	if points.size() < 7:
		return
	if show_mesh:
		var mesh_node = session.attacker.find_child("AhogeDeformMesh", true, false)
		var indices: PackedInt32Array = mesh_node.profile.indices
		for i in range(0, indices.size(), 3):
			var a: Vector2 = points[indices[i]]
			var b: Vector2 = points[indices[i + 1]]
			var c: Vector2 = points[indices[i + 2]]
			draw_polyline(PackedVector2Array([a, b, c, a]), Color(0.12, 0.28, 0.7, 0.38), 0.7, true)
	if show_path:
		var centers := PackedVector2Array([points[0]])
		for i in range(1, points.size() - 1, 5):
			centers.append((points[i] + points[i + 4]) * 0.5)
		centers.append(points[-1])
		draw_polyline(centers, Color(0.13, 0.4, 0.72, 0.9), 1.6, true)
		if session.tip_history.size() >= 2:
			draw_polyline(session.tip_history, Color(0.0, 0.6, 0.5, 0.75), 2.0, true)
		draw_circle(points[0], 4.0, Color(0.16, 0.4, 0.9))
		draw_circle(points[-1], 4.0, Color(0.0, 0.6, 0.5))
		var target: Vector2 = session.defender.contact_canvas_position()
		draw_arc(target, 7.0, 0.0, TAU, 24, Color(0.9, 0.3, 0.12), 2.0, true)

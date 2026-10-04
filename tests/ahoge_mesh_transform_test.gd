extends SceneTree

const RigScript := preload("res://src/ui/ahoge_prototype_rig.gd")
const StateScript := preload("res://src/domain/combatant_state.gd")
const ConfigScript := preload("res://src/config/combat_config.gd")
const TEXTURE_PATH: String = "res://assets/characters/prototype/charactor_01/ahoge.png"
const OUT: String = "res://artifacts/ahoge-mesh/transform_report.json"
var failures: Array[String] = []
var records: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var texture: Texture2D = load(TEXTURE_PATH) as Texture2D
	_expect(texture != null, "変換試験の現行素材を読み込めません")
	if texture == null:
		quit(1)
		return
	for fps in [30, 60, 120]:
		for facing in [1.0, -1.0]:
			for charge in [0.0, 1.0]:
				_run_case(texture, fps, facing, charge)
	var report: Dictionary = {"status": "PASS" if failures.is_empty() else "FAIL", "cases": records, "failures": failures, "scope": "基準変換の回帰。実描画の検査は別途必須"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/ahoge-mesh"))
	var file: FileAccess = FileAccess.open(OUT, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	else:
		_expect(false, "変換試験の記録を保存できません")
	print("AHOGE mesh transform: %s cases=%d" % [report["status"], records.size()])
	quit(0 if failures.is_empty() else 1)


func _run_case(texture: Texture2D, fps: int, facing: float, charge: float) -> void:
	var clean = RigScript.new()
	var corrected = RigScript.new()
	root.add_child(clean)
	root.add_child(corrected)
	clean.set_process(false)
	corrected.set_process(false)
	clean.configure(texture, facing)
	corrected.configure(texture, facing)
	var clean_root: Node2D = clean.find_child("AhogeMotionRoot", true, false) as Node2D
	var corrected_root: Node2D = corrected.find_child("AhogeMotionRoot", true, false) as Node2D
	var clean_mesh = clean.find_child("AhogeDeformMesh", true, false)
	var corrected_mesh = corrected.find_child("AhogeDeformMesh", true, false)
	var label: String = "%d_%s_%d" % [fps, "left" if facing > 0.0 else "right", int(charge)]
	_expect(clean.debug_mesh_active() and corrected.debug_mesh_active(), "変換試験がSpriteへfallbackしています: " + label)
	var config = ConfigScript.new()
	var phases: Array = [
		[StateScript.ActionState.IDLE, 0.10],
		[StateScript.ActionState.CHARGING, config.max_charge_seconds if charge > 0.0 else 0.02],
		[StateScript.ActionState.WINDUP, config.attack_windup_seconds(charge)],
		[StateScript.ActionState.STRIKE, config.attack_strike_seconds(charge)],
		[StateScript.ActionState.COOLDOWN, config.attack_cooldown_seconds(charge)],
		[StateScript.ActionState.PARRY, config.parry_active_seconds],
		[StateScript.ActionState.ROUND_LOCKED, 0.10],
	]
	var maximum_basis_error: float = 0.0
	var maximum_vertex_error: float = 0.0
	var maximum_skew: float = 0.0
	var minimum_normalized_area: float = 1.0
	var samples: int = 0
	for cycle in range(3):
		for phase in phases:
			var state: int = int(phase[0])
			var duration: float = float(phase[1])
			clean.set_motion(Vector2(18.0, -3.0), Vector2(12.0, -8.0), state, true, charge, duration, config.max_charge_seconds, config.attack_contact_ratio)
			corrected.set_motion(Vector2(18.0, -3.0), Vector2(12.0, -8.0), state, true, charge, duration, config.max_charge_seconds, config.attack_contact_ratio)
			var elapsed: float = 0.0
			while elapsed < duration - 0.000001:
				var dt: float = minf(1.0 / float(fps), duration - elapsed)
				# 外部の表示補正だけを加える。同じ内部状態の対照リグは変更しない。
				# 現行の接触補正と同様、基底方向以外への非等方伸縮でskewを作る。
				var axis: Vector2 = Vector2(0.62, -0.78).normalized()
				var stretch: Transform2D = Transform2D(Vector2.RIGHT + axis * axis.x, Vector2.DOWN + axis * axis.y, Vector2.ZERO)
				corrected_root.transform = Transform2D(0.18, Vector2.ZERO) * stretch * corrected_root.transform
				clean.call("_process", dt)
				corrected.call("_process", dt)
				var a: Transform2D = clean_root.transform
				var b: Transform2D = corrected_root.transform
				maximum_basis_error = maxf(maximum_basis_error, maxf(a.x.distance_to(b.x), maxf(a.y.distance_to(b.y), a.origin.distance_to(b.origin))))
				maximum_skew = maxf(maximum_skew, absf(corrected_root.skew))
				var area: float = absf(b.determinant()) / maxf(b.x.length() * b.y.length(), 0.000001)
				minimum_normalized_area = minf(minimum_normalized_area, area)
				if corrected_mesh.configured and clean_mesh.configured:
					var points: PackedVector2Array = corrected_mesh.current_vertices
					var reference: PackedVector2Array = clean_mesh.current_vertices
					for index in [0, int(points.size() / 2), points.size() - 1]:
						maximum_vertex_error = maxf(maximum_vertex_error, corrected_mesh.to_global(points[index]).distance_to(clean_mesh.to_global(reference[index])))
				elapsed += dt
				samples += 1
	_expect(maximum_basis_error < 0.0001, "前frameの補正が新しい基準transformへ残っています: " + label)
	_expect(maximum_skew < 0.0001, "基準transformにskewが蓄積しています: " + label)
	_expect(minimum_normalized_area > 0.9999, "基準transformの面積が潰れています: " + label)
	_expect(maximum_vertex_error < 0.01, "同一入力で実メッシュ頂点にずれが出ています: " + label)
	# originもroot固定の契約。位置だけが残る更新も検出する。
	corrected_root.position = Vector2(11.0, -7.0)
	corrected.call("_apply_visual_transform")
	_expect(corrected_root.position.length() < 0.0001, "新しい基準transformの原点が0ではありません: " + label)
	records.append({"label": label, "cycles": 3, "samples": samples, "maximum_basis_error": maximum_basis_error, "maximum_vertex_error_px": maximum_vertex_error, "maximum_base_skew": maximum_skew, "minimum_normalized_area": minimum_normalized_area})
	clean.free()
	corrected.free()


func _expect(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)

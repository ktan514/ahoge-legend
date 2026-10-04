"""接触補正の数式検証。Godot実描画の検証とは分離して報告する。"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import numpy as np


def rotation(angle: float) -> np.ndarray:
    c, s = math.cos(angle), math.sin(angle)
    return np.array([[c, -s], [s, c]], dtype=float)


def verify(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    max_error = 0.0
    max_width_error = 0.0
    minimum_determinant = math.inf
    count = 0
    for points in data['keys']:
        tip = np.asarray(points[-1], dtype=float)
        if tip.shape != (2,):
            raise ValueError('毛先座標の形式が不正です')
        for angle in np.linspace(-1.5, 1.6, 17):
            for reach in [0.8, 1.0, 2.05, 2.52]:
                squash = 1.0 - 0.18 * np.clip((reach - 1.0) / 1.45, 0.0, 1.0)
                base = rotation(float(angle)) @ np.diag([0.246 * reach, 0.246 * squash])
                q = base @ tip
                axis = q / np.linalg.norm(q)
                perpendicular = np.array([-axis[1], axis[0]])
                for target in [np.array([450., -30.]), np.array([700., 0.]), np.array([850., 100.])]:
                    turn = (math.atan2(target[1], target[0]) - math.atan2(q[1], q[0]) + math.pi) % (2 * math.pi) - math.pi
                    for amount in np.linspace(0.0, 1.0, 17):
                        ratio = 1.0 + (np.linalg.norm(target) / np.linalg.norm(q) - 1.0) * amount
                        correction = rotation(turn * amount) @ (np.eye(2) + (ratio - 1.0) * np.outer(axis, axis))
                        result = correction @ base
                        determinant = float(np.linalg.det(result))
                        minimum_determinant = min(minimum_determinant, determinant)
                        if determinant <= 0 or not np.isfinite(result).all():
                            raise AssertionError('補間中に反転・非有限値が発生しました')
                        width_error = abs(float(np.linalg.norm(correction @ perpendicular)) - 1.0)
                        max_width_error = max(max_width_error, width_error)
                        if amount == 1.0:
                            for facing in [-1, 1]:
                                flip = np.diag([facing, 1.0])
                                max_error = max(max_error, float(np.linalg.norm(flip @ result @ tip - flip @ target)))
                        count += 1
    if max_error > 1e-8 or max_width_error > 1e-10:
        raise AssertionError('接触点または幅方向の保存誤差が許容範囲を超えました')
    return {'status': 'PASS', 'scope': 'Pythonによる表示補正式の検証。Godot実行・実描画は含まない', 'cases': count, 'maximum_contact_error': max_error, 'maximum_transverse_width_error': max_width_error, 'minimum_determinant': minimum_determinant}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('geometry', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = verify(args.geometry)
    text = json.dumps(report, ensure_ascii=False, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + '\n', encoding='utf-8')

"""Godotが出力した固定メッシュと実描画を検査する。"""
from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from shapely.geometry import Polygon

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts/ahoge-mesh"
SOURCE = ROOT / "assets/characters/prototype/charactor_01/ahoge.png"


def cross(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return a[..., 0] * b[..., 1] - a[..., 1] * b[..., 0]


def rgba(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0


def premultiply(pixels: np.ndarray) -> np.ndarray:
    result = pixels.copy()
    result[..., :3] *= result[..., 3:4]
    return result


def main() -> None:
    data = json.loads((OUT / "geometry.json").read_text())
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == data["source_file_sha256"], "元画像が変更されています"
    keys = np.asarray(data["keys"], dtype=np.float64)
    uv = np.asarray(data["uvs"], dtype=np.float64)
    triangles = np.asarray(data["indices"], dtype=np.int64).reshape(-1, 3)
    boundary = np.asarray(data["boundary"], dtype=np.int64)
    assert np.isfinite(keys).all() and np.isfinite(uv).all(), "有限でない頂点があります"
    assert keys.shape == (9, 427, 2), keys.shape
    assert triangles.shape == (680, 3), triangles.shape
    assert triangles.min() == 0 and triangles.max() == keys.shape[1] - 1
    assert np.max(np.abs(keys[:, 0])) < 1e-6, "根元が動いています"
    assert np.max(np.abs(keys[0] + data["root"] - uv * 1254)) < .001, "待機時UV対応がずれています"

    edges = Counter(tuple(sorted((int(a), int(b)))) for t in triangles for a, b in zip(t, np.roll(t, -1)))
    assert all(n in (1, 2) for n in edges.values()), "非多様体または重複面があります"
    expected_boundary = {tuple(sorted((int(a), int(b)))) for a, b in zip(boundary, np.roll(boundary, -1))}
    assert {edge for edge, n in edges.items() if n == 1} == expected_boundary, "内部に裂け目があります"

    def areas(points: np.ndarray) -> np.ndarray:
        p = points[triangles]
        return cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])

    # 線形補間の符号付き2倍面積は2次式。区間端だけでなく内部極値も調べる。
    interval_minima = []
    for first, second in zip(keys[:-1], keys[1:]):
        f0, f1, fm = areas(first), areas(second), areas((first + second) * .5)
        a = 2 * (f0 + f1 - 2 * fm)
        b = f1 - f0 - a
        t = np.zeros_like(a)
        np.divide(-b, 2 * a, out=t, where=np.abs(a) > 1e-9)
        t = np.clip(t, 0, 1)
        minimum = np.minimum(np.minimum(f0, f1), a * t * t + b * t + f0)
        interval_minima.append(float(minimum.min()))
    assert min(interval_minima) > .01, ("面の反転または退化", interval_minima)

    # 大域的な輪郭重複は別検査。これは257点での検査で、連続区間の証明とは記録しない。
    for amount in np.linspace(0, 1, 257):
        location = amount * (len(keys) - 1)
        index = min(int(location), len(keys) - 2)
        weight = location - index
        points = keys[index] * (1 - weight) + keys[index + 1] * weight
        assert Polygon(points[boundary]).is_valid, ("輪郭が自己交差", amount)

    sections = keys[-1, 1:-1].reshape(-1, 5, 2)
    centers = np.vstack([sections[:, 2], keys[-1, -1]])
    terminal = np.diff(centers[-18:], axis=0)
    directions = np.arctan2(terminal[:, 1], terminal[:, 0])
    tip_error = float(np.max(np.abs(directions + .85)) * 180 / np.pi)
    assert tip_error < 5, ("実際の先端側が直線になっていません", tip_error)

    reference = rgba(OUT / "reference.png")
    rest = rgba(OUT / "shape_00.png")
    difference = np.abs(premultiply(reference) - premultiply(rest))
    alpha_sum = max(float(reference[..., 3].sum()), 1)
    lost_alpha = float(np.maximum(reference[..., 3] - rest[..., 3], 0).sum() / alpha_sum)
    color_error = float(difference.sum() / (alpha_sum * 4))
    assert lost_alpha < .005, ("待機画像の輪郭欠け", lost_alpha)
    assert color_error < .01, ("待機画像が元Spriteと一致しません", color_error)
    for step in range(17):
        image = rgba(OUT / f"shape_{step:02}.png")
        assert (image[..., 3] > .2).sum() > 1500, ("画像が消えています", step)
    returned = rgba(OUT / "returned.png")
    assert np.max(np.abs(premultiply(rest) - premultiply(returned))) < .005, "復帰画像が異なります"
    straight = rgba(OUT / "shape_16.png")
    assert np.abs(straight - rest).sum() > 5000, "頂点更新が描画へ反映されていません"

    report = {
        "status": "PASS",
        "vertices": keys.shape[1],
        "triangles": len(triangles),
        "shape_keys": len(keys),
        "minimum_double_area_all_intervals": min(interval_minima),
        "boundary_intersection_samples": 257,
        "terminal_direction_error_degrees": tip_error,
        "rest_lost_alpha_ratio": lost_alpha,
        "rest_premultiplied_color_error": color_error,
        "rendered_shapes": 17,
        "human_verification": "未実施",
    }
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
